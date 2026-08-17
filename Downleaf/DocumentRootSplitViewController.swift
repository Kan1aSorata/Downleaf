import AppKit
import QuartzCore

private final class TrackingSplitView: NSSplitView {
    var onDividerDoubleClick: (() -> Void)?
    var onDividerDragEnded: (() -> Void)?

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
        let dividerHit = !dividerRect.isEmpty && dividerRect.insetBy(dx: -6, dy: 0).contains(point)

        if dividerHit, event.clickCount == 2 {
            onDividerDoubleClick?()
            return
        }

        super.mouseDown(with: event)
        if dividerHit {
            onDividerDragEnded?()
        }
    }
}

@MainActor
final class DocumentRootSplitViewController: NSSplitViewController {
    let contentViewController = DocumentContentViewController()
    let outlineViewController = OutlineViewController()
    private unowned let document: MarkdownDocument
    private let outlineItem: NSSplitViewItem
    private var semanticTask: Task<Void, Never>?
    private var currentHeadings: [OutlineHeading] = []
    private var currentSource = ""
    private var activeAnchor: String?
    private var isApplyingInitialLayout = true
    private var isUpdatingNarrowWindowState = false
    private var wasAutoCollapsedForNarrowWindow = false
    private var outlineAnimationTarget: Bool?
    private var outlineAnimationGeneration = 0
    private var outlineAnimationTask: Task<Void, Never>?

    private static let outlineAnimationDuration: TimeInterval = 0.2
    private static let outlineMinimumThickness: CGFloat = 80
    private static let collapsedAnimationThickness: CGFloat = 0.5

    var onModeChange: ((DocumentMode) -> Void)?
    var onDocumentStateChange: (() -> Void)?
    var onOutlineVisibilityChange: ((Bool) -> Void)?

    init(document: MarkdownDocument) {
        self.document = document
        currentSource = document.text

        let trackingSplitView = TrackingSplitView()
        trackingSplitView.isVertical = true
        trackingSplitView.dividerStyle = .thin

        let contentItem = NSSplitViewItem(viewController: contentViewController)
        contentItem.minimumThickness = AppPreferences.minimumEditorWidth

        outlineItem = NSSplitViewItem(inspectorWithViewController: outlineViewController)
        outlineItem.canCollapse = true
        outlineItem.canCollapseFromWindowResize = true
        outlineItem.minimumThickness = Self.outlineMinimumThickness
        outlineItem.maximumThickness = AppPreferences.maximumOutlineWidth
        outlineItem.preferredThicknessFraction = AppPreferences.outlineWidth / 1180

        super.init(nibName: nil, bundle: nil)
        splitView = trackingSplitView
        minimumThicknessForInlineSidebars = AppPreferences.minimumEditorWidth + AppPreferences.minimumOutlineWidth + 1
        addSplitViewItem(contentItem)
        addSplitViewItem(outlineItem)

        trackingSplitView.onDividerDoubleClick = { [weak self] in
            self?.resetOutlineWidth()
        }
        trackingSplitView.onDividerDragEnded = { [weak self] in
            self?.finishOutlineResize()
        }

        wireInteractions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        semanticTask?.cancel()
        outlineAnimationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentViewController.editorViewController.setInitialText(currentSource)
        scheduleSemanticUpdate(for: currentSource, immediate: true)

        DispatchQueue.main.async { [weak self] in
            self?.applyInitialOutlineState()
        }
    }

    var mode: DocumentMode {
        contentViewController.mode
    }

    var isOutlineVisible: Bool {
        outlineAnimationTarget ?? !outlineItem.isCollapsed
    }

    func setMode(_ mode: DocumentMode) {
        contentViewController.update(
            source: currentSource,
            headings: currentHeadings,
            baseURL: document.fileURL?.deletingLastPathComponent(),
            preserving: activeAnchor
        )
        contentViewController.setMode(mode)
    }

    func toggleReadingMode() {
        setMode(mode == .reader ? .editor : .reader)
    }

    func toggleOutline() {
        setOutlineVisible(!isOutlineVisible, persist: true)
    }

    func focusOutline() {
        if !isOutlineVisible {
            setOutlineVisible(true, persist: true)
        }
        outlineViewController.focusOutline()
    }

    func replaceEditorTextAfterRevert(_ text: String) {
        currentSource = text
        contentViewController.editorViewController.replaceTextAfterRevert(text)
        contentViewController.mirrorEditedSource(text, from: contentViewController.editorViewController)
        scheduleSemanticUpdate(for: text, immediate: true)
    }

    func preferencesDidChange() {
        contentViewController.editorViewController.view.needsDisplay = true
    }

    override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let systemRect = super.splitView(
            splitView,
            effectiveRect: proposedEffectiveRect,
            forDrawnRect: drawnRect,
            ofDividerAt: dividerIndex
        )
        return systemRect.insetBy(dx: -5, dy: 0)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        contentViewController.synchronizeLayoutAfterContainerResize()
        if let outlineAnimationTarget {
            onOutlineVisibilityChange?(outlineAnimationTarget)
            return
        }
        updateNarrowWindowStateIfNeeded()
        guard !isApplyingInitialLayout, !outlineItem.isCollapsed else {
            onOutlineVisibilityChange?(!outlineItem.isCollapsed)
            return
        }

        let width = outlineViewController.view.frame.width
        if width >= AppPreferences.minimumOutlineWidth {
            AppPreferences.outlineWidth = width
        }
        onOutlineVisibilityChange?(true)
    }

    private func wireInteractions() {
        contentViewController.editorViewController.onTextChange = { [weak self] text in
            self?.handleUserEdit(text, from: self?.contentViewController.editorViewController)
        }

        contentViewController.previewEditorViewController.onTextChange = { [weak self] text in
            self?.handleUserEdit(text, from: self?.contentViewController.previewEditorViewController)
        }

        contentViewController.editorViewController.onCaretOffsetChange = { [weak self] offset in
            self?.updateActiveAnchorForEditorOffset(offset)
        }

        contentViewController.previewEditorViewController.onCaretOffsetChange = { [weak self] offset in
            guard self?.contentViewController.mode == .split else { return }
            self?.updateActiveAnchorForEditorOffset(offset)
        }

        contentViewController.onModeChange = { [weak self] mode in
            self?.onModeChange?(mode)
        }

        contentViewController.onPreviewVisibleHeadingChange = { [weak self] anchor in
            self?.activeAnchor = anchor
            self?.contentViewController.preserveActiveAnchor(anchor)
            self?.outlineViewController.selectHeading(anchor: anchor)
        }

        outlineViewController.onActivate = { [weak self] heading in
            guard let self else { return }
            self.activeAnchor = heading.anchor
            self.contentViewController.preserveActiveAnchor(heading.anchor)
            if self.mode != .reader {
                self.contentViewController.editorViewController.jump(to: heading.sourceRange)
            }
            self.contentViewController.scrollPreview(to: heading.anchor)
        }
    }

    private func handleUserEdit(_ text: String, from editor: EditorViewController?) {
        currentSource = text
        document.userDidEdit(text: text)
        if let editor {
            contentViewController.mirrorEditedSource(text, from: editor)
        }
        onDocumentStateChange?()
        scheduleSemanticUpdate(for: text)
    }

    private func scheduleSemanticUpdate(for source: String, immediate: Bool = false) {
        semanticTask?.cancel()
        semanticTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(130))
            }
            guard !Task.isCancelled else { return }
            let headings = await Task.detached(priority: .userInitiated) {
                MarkdownOutlineParser.headings(in: source)
            }.value
            guard !Task.isCancelled, let self, self.currentSource == source else { return }
            self.applySemanticUpdate(headings)
        }
    }

    private func applySemanticUpdate(_ headings: [OutlineHeading]) {
        currentHeadings = headings
        outlineViewController.update(headings: headings)

        if mode != .reader {
            activeAnchor = anchor(atSourceOffset: contentViewController.editorViewController.caretOffset)
        } else if let activeAnchor, !headings.contains(where: { $0.anchor == activeAnchor }) {
            self.activeAnchor = headings.first?.anchor
        } else if activeAnchor == nil {
            activeAnchor = headings.first?.anchor
        }
        contentViewController.preserveActiveAnchor(activeAnchor)
        if let activeAnchor {
            outlineViewController.selectHeading(anchor: activeAnchor)
        }
        contentViewController.update(
            source: currentSource,
            headings: headings,
            baseURL: document.fileURL?.deletingLastPathComponent(),
            preserving: activeAnchor
        )
    }

    private func updateActiveAnchorForEditorOffset(_ offset: Int) {
        outlineViewController.selectHeading(atSourceOffset: offset)
        activeAnchor = anchor(atSourceOffset: offset)
        contentViewController.preserveActiveAnchor(activeAnchor)
    }

    private func anchor(atSourceOffset offset: Int) -> String? {
        currentHeadings.last(where: { $0.sourceRange.location <= offset })?.anchor
            ?? currentHeadings.first?.anchor
    }

    private func applyInitialOutlineState() {
        isApplyingInitialLayout = true
        if AppPreferences.outlineVisible, !isNarrowWindow {
            outlineItem.isCollapsed = false
            applyOutlineWidth(AppPreferences.outlineWidth)
        } else {
            outlineItem.isCollapsed = true
            wasAutoCollapsedForNarrowWindow = AppPreferences.outlineVisible && isNarrowWindow
        }
        isApplyingInitialLayout = false
        synchronizeContentLayoutAfterOutlineChange()
        onOutlineVisibilityChange?(!outlineItem.isCollapsed)
    }

    private func setOutlineVisible(_ visible: Bool, persist: Bool) {
        guard visible != isOutlineVisible else {
            if persist {
                AppPreferences.outlineVisible = visible
            }
            return
        }

        wasAutoCollapsedForNarrowWindow = false
        if persist {
            AppPreferences.outlineVisible = visible
        }

        outlineAnimationTask?.cancel()
        outlineAnimationGeneration += 1
        let generation = outlineAnimationGeneration
        outlineAnimationTarget = visible
        onOutlineVisibilityChange?(visible)

        let shouldAnimate = view.window != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            restoreOutlineThicknessConstraints()
            outlineItem.isCollapsed = !visible
            if visible {
                applyOutlineWidth(AppPreferences.outlineWidth)
            }
            finishOutlineTransition(visible: visible, generation: generation)
            return
        }

        animateOutlineTransition(visible: visible, generation: generation)
    }

    private func resetOutlineWidth() {
        AppPreferences.outlineWidth = AppPreferences.defaultOutlineWidth
        if !isOutlineVisible {
            setOutlineVisible(true, persist: true)
        } else if outlineAnimationTarget == nil {
            applyOutlineWidth(AppPreferences.defaultOutlineWidth)
        }
    }

    private func finishOutlineResize() {
        guard !outlineItem.isCollapsed else { return }
        let width = outlineViewController.view.frame.width
        if width < AppPreferences.minimumOutlineWidth {
            setOutlineVisible(false, persist: true)
        } else {
            AppPreferences.outlineWidth = width
        }
    }

    private func applyOutlineWidth(_ width: CGFloat) {
        guard splitView.bounds.width > 0, !outlineItem.isCollapsed else { return }
        let constrained = constrainedOutlineWidth(width)
        let position = splitView.bounds.width - constrained - splitView.dividerThickness
        splitView.setPosition(position, ofDividerAt: 0)
    }

    private func animateOutlineTransition(visible: Bool, generation: Int) {
        guard splitView.bounds.width > 0 else {
            outlineItem.isCollapsed = !visible
            finishOutlineTransition(visible: visible, generation: generation)
            return
        }

        outlineItem.minimumThickness = 0
        outlineItem.maximumThickness = AppPreferences.maximumOutlineWidth

        let wasCollapsed = outlineItem.isCollapsed
        if wasCollapsed {
            outlineItem.isCollapsed = false
            setOutlineWidthForAnimation(Self.collapsedAnimationThickness)
            splitView.layoutSubtreeIfNeeded()
        }

        let startWidth = wasCollapsed
            ? Self.collapsedAnimationThickness
            : max(Self.collapsedAnimationThickness, outlineViewController.view.frame.width)
        let endWidth = visible
            ? constrainedOutlineWidth(AppPreferences.outlineWidth)
            : Self.collapsedAnimationThickness
        let startTime = CACurrentMediaTime()

        outlineAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1, max(0, elapsed / Self.outlineAnimationDuration))
                let easedProgress = progress * progress * (3 - 2 * progress)
                let width = startWidth + (endWidth - startWidth) * easedProgress
                self.setOutlineWidthForAnimation(width)

                if progress >= 1 {
                    self.finishOutlineTransition(visible: visible, generation: generation)
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(8))
                } catch {
                    return
                }
            }
        }
    }

    private func finishOutlineTransition(visible: Bool, generation: Int) {
        guard outlineAnimationGeneration == generation else { return }
        outlineAnimationTask = nil

        if visible {
            outlineItem.isCollapsed = false
            let targetWidth = constrainedOutlineWidth(AppPreferences.outlineWidth)
            setOutlineWidthForAnimation(targetWidth)
            if splitView.bounds.width > 0 {
                outlineItem.preferredThicknessFraction = targetWidth / splitView.bounds.width
            }
        } else {
            outlineItem.isCollapsed = true
        }

        restoreOutlineThicknessConstraints()
        outlineAnimationTarget = nil
        view.layoutSubtreeIfNeeded()
        synchronizeContentLayoutAfterOutlineChange()
        onOutlineVisibilityChange?(visible)
    }

    private func setOutlineWidthForAnimation(_ width: CGFloat) {
        let position = Self.outlineDividerPosition(
            splitWidth: splitView.bounds.width,
            dividerThickness: splitView.dividerThickness,
            outlineWidth: width
        )
        splitView.setPosition(position, ofDividerAt: 0)
    }

    static func outlineDividerPosition(
        splitWidth: CGFloat,
        dividerThickness: CGFloat,
        outlineWidth: CGFloat
    ) -> CGFloat {
        let availableWidth = max(0, splitWidth - dividerThickness)
        let clampedOutlineWidth = min(max(0, outlineWidth), availableWidth)
        return availableWidth - clampedOutlineWidth
    }

    private func restoreOutlineThicknessConstraints() {
        outlineItem.minimumThickness = Self.outlineMinimumThickness
        outlineItem.maximumThickness = AppPreferences.maximumOutlineWidth
    }

    private func constrainedOutlineWidth(_ width: CGFloat) -> CGFloat {
        let maximumKeepingEditorVisible = max(
            0,
            splitView.bounds.width - splitView.dividerThickness - AppPreferences.minimumEditorWidth
        )
        let upperBound = max(
            0,
            min(
                AppPreferences.maximumOutlineWidth,
                splitView.bounds.width * 0.4,
                maximumKeepingEditorVisible
            )
        )
        let lowerBound = min(AppPreferences.minimumOutlineWidth, upperBound)
        return max(lowerBound, min(width, upperBound))
    }

    private func synchronizeContentLayoutAfterOutlineChange() {
        contentViewController.synchronizeLayoutAfterContainerResize()
        DispatchQueue.main.async { [weak self] in
            self?.contentViewController.synchronizeLayoutAfterContainerResize()
        }
    }

    private var isNarrowWindow: Bool {
        splitView.bounds.width < minimumThicknessForInlineSidebars
    }

    private func updateNarrowWindowStateIfNeeded() {
        guard !isApplyingInitialLayout,
              !isUpdatingNarrowWindowState,
              outlineAnimationTarget == nil else { return }
        isUpdatingNarrowWindowState = true
        defer { isUpdatingNarrowWindowState = false }

        if isNarrowWindow,
           AppPreferences.outlineVisible,
           !outlineItem.isCollapsed {
            wasAutoCollapsedForNarrowWindow = true
            outlineItem.isCollapsed = true
            synchronizeContentLayoutAfterOutlineChange()
            onOutlineVisibilityChange?(false)
        } else if !isNarrowWindow,
                  wasAutoCollapsedForNarrowWindow,
                  AppPreferences.outlineVisible {
            wasAutoCollapsedForNarrowWindow = false
            outlineItem.isCollapsed = false
            applyOutlineWidth(AppPreferences.outlineWidth)
            synchronizeContentLayoutAfterOutlineChange()
            onOutlineVisibilityChange?(true)
        }
    }
}
