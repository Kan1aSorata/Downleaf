import AppKit

private final class PreviewSplitView: NSSplitView {
    var onDividerDragEnded: (() -> Void)?
    var onDividerDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dividerRect: NSRect
        if arrangedSubviews.count > 1 {
            dividerRect = NSRect(
                x: arrangedSubviews[0].frame.maxX,
                y: bounds.minY,
                width: dividerThickness,
                height: bounds.height
            )
        } else {
            dividerRect = .zero
        }
        let hitDivider = !dividerRect.isEmpty && dividerRect.insetBy(dx: -6, dy: 0).contains(point)

        if hitDivider, event.clickCount == 2 {
            onDividerDoubleClick?()
            return
        }

        super.mouseDown(with: event)
        if hitDivider {
            onDividerDragEnded?()
        }
    }
}

enum DocumentMode: Int, CaseIterable {
    case editor = 0
    case split = 1
    case reader = 2
}

@MainActor
final class DocumentContentViewController: NSViewController, NSSplitViewDelegate {
    let editorViewController = EditorViewController()
    /// 分屏模式右侧的可编辑实时预览：与左侧共享同一份文本，双向镜像。
    let previewEditorViewController = EditorViewController()
    private let previewHostView = NSView()
    private var previewViewController: PreviewViewController?
    private var isPreviewEditorInstalled = false
    private var contentSplitView: PreviewSplitView?
    private(set) var mode: DocumentMode = .editor
    private var source = ""
    private var headings: [OutlineHeading] = []
    private var baseURL: URL?
    private var activeAnchor: String?
    private var splitFraction = AppPreferences.previewSplitFraction
    private var isApplyingSplitPosition = false
    private var isApplyingModeGeometry = false

    var onModeChange: ((DocumentMode) -> Void)?
    var onPreviewVisibleHeadingChange: ((String) -> Void)?

    var isEditorSurfaceVisible: Bool {
        isViewLoaded
            && editorViewController.view.isDescendant(of: view)
            && editorViewController.view.frame.width > 1
    }

    var isPreviewSurfaceVisible: Bool {
        guard isViewLoaded else { return false }
        switch mode {
        case .editor:
            return false
        case .split:
            return isPreviewEditorInstalled
                && previewEditorViewController.view.isDescendant(of: view)
                && !previewEditorViewController.view.isHidden
                && previewHostView.frame.width > 1
        case .reader:
            guard let previewViewController else { return false }
            return previewViewController.view.isDescendant(of: view)
                && !previewViewController.view.isHidden
                && previewHostView.frame.width > 1
        }
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root
        addChild(editorViewController)
        installStableLayout()
        wireScrollSync()
        applyModeVisibility()
    }

    /// 分屏两侧按可见区顶部的源码偏移互相对齐。
    private func wireScrollSync() {
        editorViewController.onScroll = { [weak self] offset in
            guard let self, self.mode == .split, self.isPreviewEditorInstalled else { return }
            self.previewEditorViewController.alignTop(toCharacterOffset: offset)
        }
        previewEditorViewController.onScroll = { [weak self] offset in
            guard let self, self.mode == .split else { return }
            self.editorViewController.alignTop(toCharacterOffset: offset)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if mode != .split {
            applyModeGeometry()
        }
    }

    func setMode(_ newMode: DocumentMode) {
        guard newMode != mode else {
            focusPrimaryContent()
            return
        }
        captureSplitFractionIfNeeded()
        mode = newMode
        if isViewLoaded {
            applyModeVisibility()
        }
        onModeChange?(newMode)
    }

    func toggleReadingMode() {
        setMode(mode == .reader ? .editor : .reader)
    }

    func update(source: String, headings: [OutlineHeading], baseURL: URL?, preserving anchor: String?) {
        self.source = source
        self.headings = headings
        self.baseURL = baseURL
        activeAnchor = anchor
        editorViewController.textView.linkBaseURL = baseURL
        previewEditorViewController.textView.linkBaseURL = baseURL
        switch mode {
        case .editor:
            break
        case .split:
            if isPreviewEditorInstalled {
                previewEditorViewController.applyMirroredText(source)
            }
        case .reader:
            ensurePreview().setMarkdown(source, headings: headings, baseURL: baseURL, preserving: anchor)
        }
    }

    /// 一侧编辑器产生用户编辑后，把文本镜像到另一侧（仅分屏模式需要）。
    func mirrorEditedSource(_ text: String, from editor: EditorViewController) {
        guard mode == .split, isPreviewEditorInstalled else { return }
        let counterpart = editor === editorViewController ? previewEditorViewController : editorViewController
        counterpart.applyMirroredText(text)
    }

    func preserveActiveAnchor(_ anchor: String?) {
        activeAnchor = anchor
    }

    func scrollPreview(to anchor: String) {
        activeAnchor = anchor
        switch mode {
        case .editor:
            break
        case .split:
            if let heading = headings.first(where: { $0.anchor == anchor }) {
                previewEditorViewController.reveal(heading.sourceRange)
            }
        case .reader:
            ensurePreview().scroll(to: anchor)
        }
    }

    func focusPrimaryContent() {
        guard isViewLoaded else { return }
        if mode == .reader {
            view.window?.makeFirstResponder(ensurePreview().view)
        } else {
            editorViewController.focusEditor()
        }
    }

    func synchronizeLayoutAfterContainerResize() {
        guard isViewLoaded else { return }
        view.layoutSubtreeIfNeeded()
        contentSplitView?.layoutSubtreeIfNeeded()
        applyModeGeometry()
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let availableWidth = max(0, splitView.bounds.width - splitView.dividerThickness)
        switch mode {
        case .editor:
            return availableWidth
        case .reader:
            return 0
        case .split:
            break
        }

        let minimumPaneWidth: CGFloat = 240
        let maximumPosition = max(minimumPaneWidth, splitView.bounds.width - splitView.dividerThickness - minimumPaneWidth)
        return min(max(proposedPosition, minimumPaneWidth), maximumPosition)
    }

    private func ensurePreview() -> PreviewViewController {
        if let previewViewController {
            return previewViewController
        }
        let controller = PreviewViewController()
        controller.onVisibleHeadingChange = { [weak self] anchor in
            self?.activeAnchor = anchor
            self?.onPreviewVisibleHeadingChange?(anchor)
        }
        addChild(controller)
        controller.setMarkdown(source, headings: headings, baseURL: baseURL, preserving: activeAnchor)
        controller.view.frame = previewHostView.bounds
        controller.view.autoresizingMask = [.width, .height]
        previewHostView.addSubview(controller.view)
        previewViewController = controller
        return controller
    }

    private func installStableLayout() {
        let splitView = PreviewSplitView(frame: view.bounds)
        splitView.autoresizingMask = [.width, .height]
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.onDividerDragEnded = { [weak self] in
            self?.captureSplitFractionIfNeeded(persist: true)
        }
        splitView.onDividerDoubleClick = { [weak self] in
            guard let self else { return }
            self.splitFraction = 0.5
            AppPreferences.previewSplitFraction = 0.5
            self.applyStoredSplitPosition()
        }
        splitView.addArrangedSubview(editorViewController.view)
        splitView.addArrangedSubview(previewHostView)
        view.addSubview(splitView)
        contentSplitView = splitView
    }

    private func ensurePreviewEditorInstalled() {
        guard !isPreviewEditorInstalled else { return }
        previewEditorViewController.forcedLivePreview = true
        addChild(previewEditorViewController)
        previewEditorViewController.view.frame = previewHostView.bounds
        previewEditorViewController.view.autoresizingMask = [.width, .height]
        previewHostView.addSubview(previewEditorViewController.view)
        previewEditorViewController.setInitialText(source)
        isPreviewEditorInstalled = true
    }

    private func applyModeVisibility() {
        switch mode {
        case .editor:
            editorViewController.forcedLivePreview = nil
        case .reader:
            editorViewController.forcedLivePreview = nil
            let preview = ensurePreview()
            preview.prepareIfNeeded()
            preview.setMarkdown(source, headings: headings, baseURL: baseURL, preserving: activeAnchor)
        case .split:
            // 左侧固定为源码样式，右侧是可编辑的实时预览。
            editorViewController.forcedLivePreview = false
            ensurePreviewEditorInstalled()
            previewEditorViewController.applyMirroredText(source)
        }

        previewViewController?.view.isHidden = mode != .reader
        if isPreviewEditorInstalled {
            previewEditorViewController.view.isHidden = mode != .split
        }
        editorViewController.view.isHidden = false
        previewHostView.isHidden = false
        applyModeGeometry()
        let expectedMode = mode
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode == expectedMode else { return }
            self.applyModeGeometry()
            self.focusPrimaryContent()
        }
    }

    private func applyModeGeometry() {
        guard !isApplyingModeGeometry,
              let splitView = contentSplitView,
              splitView.bounds.width > 0 else { return }
        isApplyingModeGeometry = true
        defer { isApplyingModeGeometry = false }

        let availableWidth = max(0, splitView.bounds.width - splitView.dividerThickness)
        switch mode {
        case .editor:
            splitView.setPosition(availableWidth, ofDividerAt: 0)
        case .reader:
            splitView.setPosition(0, ofDividerAt: 0)
        case .split:
            applyStoredSplitPosition()
        }
        splitView.layoutSubtreeIfNeeded()
        previewViewController?.view.frame = previewHostView.bounds
        previewViewController?.view.needsLayout = true
        previewViewController?.view.needsDisplay = true
        if isPreviewEditorInstalled {
            previewEditorViewController.view.frame = previewHostView.bounds
        }
    }

    private func applyStoredSplitPosition() {
        guard mode == .split,
              let splitView = contentSplitView,
              splitView.bounds.width > 0 else { return }
        let availableWidth = splitView.bounds.width - splitView.dividerThickness
        guard availableWidth > 0 else { return }

        isApplyingSplitPosition = true
        splitView.setPosition(availableWidth * splitFraction, ofDividerAt: 0)
        isApplyingSplitPosition = false
    }

    private func captureSplitFractionIfNeeded(persist: Bool = false) {
        guard mode == .split,
              !isApplyingSplitPosition,
              let splitView = contentSplitView,
              splitView.arrangedSubviews.count == 2 else {
            return
        }
        let availableWidth = splitView.bounds.width - splitView.dividerThickness
        guard availableWidth > 0 else { return }

        splitFraction = min(max(splitView.arrangedSubviews[0].frame.width / availableWidth, 0.25), 0.75)
        if persist {
            AppPreferences.previewSplitFraction = splitFraction
        }
    }
}
