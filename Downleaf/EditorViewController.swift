import AppKit
import QuartzCore

private final class EditorScrollEdgeEffectView: NSVisualEffectView {
    private let fadeMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .headerView
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true

        fadeMask.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0, 1]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 1)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.mask = fadeMask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        fadeMask.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class MarkdownTextView: NSTextView {
    @objc func toggleMarkdownBold(_ sender: Any?) {
        toggleWrapping(prefix: "**", suffix: "**")
    }

    @objc func toggleMarkdownItalic(_ sender: Any?) {
        toggleWrapping(prefix: "_", suffix: "_")
    }

    @objc func toggleMarkdownCode(_ sender: Any?) {
        toggleWrapping(prefix: "`", suffix: "`")
    }

    @objc func toggleTaskState(_ sender: Any?) {
        guard let textStorage else { return }
        let source = textStorage.string as NSString
        let selection = selectedRange()
        let safeLocation = min(selection.location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = source.substring(with: lineRange)

        let replacement: String
        if let range = line.range(of: #"^(\s*[-*+]\s+)\[ \]"#, options: .regularExpression) {
            replacement = line.replacingCharacters(in: range, with: line[range].replacingOccurrences(of: "[ ]", with: "[x]"))
        } else if let range = line.range(of: #"^(\s*[-*+]\s+)\[[xX]\]"#, options: .regularExpression) {
            replacement = line.replacingCharacters(in: range, with: line[range].replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression))
        } else {
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            let content = line.dropFirst(indentation.count)
            replacement = "\(indentation)- [ ] \(content)"
        }

        guard shouldChangeText(in: lineRange, replacementString: replacement) else { return }
        textStorage.replaceCharacters(in: lineRange, with: replacement)
        didChangeText()
        let delta = (replacement as NSString).length - lineRange.length
        setSelectedRange(NSRange(location: max(0, selection.location + delta), length: selection.length))
    }

    private func toggleWrapping(prefix: String, suffix: String) {
        guard let textStorage else { return }
        let source = textStorage.string as NSString
        let selection = selectedRange()
        let selectedText = source.substring(with: selection)
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length

        let replacement: String
        let updatedSelection: NSRange

        if selection.length > 0,
           selectedText.hasPrefix(prefix),
           selectedText.hasSuffix(suffix),
           selection.length >= prefixLength + suffixLength {
            replacement = String(selectedText.dropFirst(prefix.count).dropLast(suffix.count))
            updatedSelection = NSRange(location: selection.location, length: (replacement as NSString).length)
        } else {
            replacement = prefix + selectedText + suffix
            if selection.length == 0 {
                updatedSelection = NSRange(location: selection.location + prefixLength, length: 0)
            } else {
                updatedSelection = NSRange(location: selection.location + prefixLength, length: selection.length)
            }
        }

        guard shouldChangeText(in: selection, replacementString: replacement) else { return }
        textStorage.replaceCharacters(in: selection, with: replacement)
        didChangeText()
        setSelectedRange(updatedSelection)
    }
}

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {
    let textView = MarkdownTextView(usingTextLayoutManager: true)
    private let scrollView = NSScrollView()
    private let topEdgeEffectView = EditorScrollEdgeEffectView(frame: .zero)
    private var highlightTask: Task<Void, Never>?
    private var isApplyingProgrammaticText = false
    private var isHighlighting = false
    private var preferencesTask: Task<Void, Never>?

    var onTextChange: ((String) -> Void)?
    var onCaretOffsetChange: ((Int) -> Void)?

    /// 覆盖全局实时预览偏好：分屏模式下左侧强制源码（false）、右侧强制实时预览（true）。
    var forcedLivePreview: Bool? {
        didSet {
            guard oldValue != forcedLivePreview, isViewLoaded else { return }
            applySyntaxHighlighting()
        }
    }

    private struct MarkerState {
        let elementIndex: Int
        let range: NSRange
        let visibleFont: NSFont
    }

    private var concealableElements: [LivePreviewElement] = []
    private var markerStates: [MarkerState] = []
    private var revealedElementIndices: Set<Int> = []
    private var concealmentIsStale = false
    private static let hiddenMarkerFont = NSFont.systemFont(ofSize: 0.1)

    var caretOffset: Int {
        min(textView.selectedRange().location, (textView.string as NSString).length)
    }

    deinit {
        highlightTask?.cancel()
        preferencesTask?.cancel()
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.frame = scrollView.contentView.bounds
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 46, height: 48)
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.32),
            .foregroundColor: NSColor.labelColor
        ]
        textView.setAccessibilityLabel("Markdown 编辑器")

        scrollView.documentView = textView
        container.addSubview(scrollView)

        topEdgeEffectView.autoresizingMask = [.width, .minYMargin]
        container.addSubview(topEdgeEffectView)

        preferencesTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard !Task.isCancelled, let self else { return }
                self.applySyntaxHighlighting()
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let availableWidth = scrollView.contentSize.width
        let horizontalInset = max(30, (availableWidth - 820) / 2)
        textView.textContainerInset = NSSize(width: horizontalInset, height: 48)
        topEdgeEffectView.frame = NSRect(
            x: 0,
            y: max(0, view.bounds.height - 48),
            width: view.bounds.width,
            height: min(48, view.bounds.height)
        )
    }

    func setInitialText(_ text: String) {
        isApplyingProgrammaticText = true
        textView.string = text
        isApplyingProgrammaticText = false
        applySyntaxHighlighting()
    }

    func replaceTextAfterRevert(_ text: String) {
        let selectedLocation = min(textView.selectedRange().location, (text as NSString).length)
        isApplyingProgrammaticText = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: selectedLocation, length: 0))
        isApplyingProgrammaticText = false
        applySyntaxHighlighting()
    }

    /// 从另一侧编辑器镜像文本：只替换首尾公共部分之间的最小差异范围，
    /// 保住本侧的滚动位置与选区，避免整篇重设。
    func applyMirroredText(_ text: String) {
        guard isViewLoaded, let storage = textView.textStorage else { return }
        let old = storage.string as NSString
        let new = text as NSString
        guard !old.isEqual(to: text) else { return }

        var prefix = 0
        let minLength = min(old.length, new.length)
        while prefix < minLength, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < minLength - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }

        isApplyingProgrammaticText = true
        concealmentIsStale = true
        storage.replaceCharacters(
            in: NSRange(location: prefix, length: old.length - prefix - suffix),
            with: new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        )
        isApplyingProgrammaticText = false
        scheduleHighlighting()
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    func jump(to range: NSRange) {
        let length = (textView.string as NSString).length
        let location = min(max(0, range.location), length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: min(1, max(0, length - location))))
        focusEditor()
        onCaretOffsetChange?(location)
    }

    /// 滚动到指定源码范围但不抢焦点，用于分屏模式的两侧同步。
    func reveal(_ range: NSRange) {
        let length = (textView.string as NSString).length
        let location = min(max(0, range.location), length)
        textView.scrollRangeToVisible(NSRange(location: location, length: min(1, max(0, length - location))))
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticText, !isHighlighting else { return }
        concealmentIsStale = true
        onTextChange?(textView.string)
        onCaretOffsetChange?(textView.selectedRange().location)
        scheduleHighlighting()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticText else { return }
        onCaretOffsetChange?(textView.selectedRange().location)
        updateMarkerConcealment()
    }

    private func scheduleHighlighting() {
        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled, !self.textView.hasMarkedText() else { return }
            self.applySyntaxHighlighting()
        }
    }

    private func applySyntaxHighlighting() {
        guard isViewLoaded, !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let source = storage.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard fullRange.length <= 2_000_000 else {
            concealableElements = []
            markerStates = []
            storage.setAttributes(baseAttributes(), range: fullRange)
            return
        }

        isHighlighting = true
        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: fullRange)

        apply(pattern: #"(?m)^(#{1})\s+.*$"#, attributes: headingAttributes(size: 26, weight: .bold), to: storage, source: source)
        apply(pattern: #"(?m)^(#{2})\s+.*$"#, attributes: headingAttributes(size: 22, weight: .bold), to: storage, source: source)
        apply(pattern: #"(?m)^(#{3})\s+.*$"#, attributes: headingAttributes(size: 18, weight: .semibold), to: storage, source: source)
        apply(pattern: #"(?m)^(#{4,6})\s+.*$"#, attributes: headingAttributes(size: AppPreferences.editorFontSize, weight: .semibold), to: storage, source: source)
        apply(pattern: #"(?m)^\s*>.*$"#, attributes: [.foregroundColor: NSColor.secondaryLabelColor], to: storage, source: source)
        apply(pattern: #"(?m)^\s*([-*+]\s+|\d+\.\s+)"#, attributes: [.foregroundColor: NSColor.controlAccentColor], to: storage, source: source)
        apply(pattern: #"(?m)^\s*```[\s\S]*?^\s*```\s*$"#, attributes: codeAttributes(), to: storage, source: source)
        apply(pattern: #"`[^`\n]+`"#, attributes: codeAttributes(), to: storage, source: source)
        apply(pattern: #"\[[^\]]+\]\([^\)]+\)"#, attributes: [.foregroundColor: NSColor.linkColor], to: storage, source: source)
        apply(pattern: #"(?m)^(---|\*\*\*|___)\s*$"#, attributes: [.foregroundColor: NSColor.tertiaryLabelColor], to: storage, source: source)

        rebuildLivePreviewStyling(in: storage, source: source)

        storage.endEditing()
        isHighlighting = false
        concealmentIsStale = false
        updateMarkerConcealment(force: true)
    }

    // MARK: - 实时预览（Live Preview）

    /// 在同一份源文本上叠加内容样式，并登记可折叠的语法标记。
    private func rebuildLivePreviewStyling(in storage: NSTextStorage, source: String) {
        concealableElements = []
        markerStates = []
        revealedElementIndices = []
        guard forcedLivePreview ?? AppPreferences.livePreviewEnabled else { return }

        concealableElements = LivePreviewParser.elements(in: source)
        for (index, element) in concealableElements.enumerated() {
            switch element.kind {
            case .strong:
                applyFontTraits(.boldFontMask, in: contentRange(of: element), to: storage)
            case .emphasis:
                applyFontTraits(.italicFontMask, in: contentRange(of: element), to: storage)
            case .strikethrough:
                storage.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: contentRange(of: element)
                )
            case .heading, .inlineCode, .link:
                break
            }

            for markerRange in element.markerRanges where markerRange.upperBound <= storage.length {
                let font = storage.attribute(.font, at: markerRange.location, effectiveRange: nil) as? NSFont
                markerStates.append(MarkerState(
                    elementIndex: index,
                    range: markerRange,
                    visibleFont: font ?? NSFont.systemFont(ofSize: AppPreferences.editorFontSize)
                ))
            }
        }
        revealedElementIndices = Set(concealableElements.indices)
    }

    /// 根据当前光标/选区折叠或恢复语法标记；只触碰状态发生变化的范围。
    private func updateMarkerConcealment(force: Bool = false) {
        guard isViewLoaded,
              !concealmentIsStale,
              !markerStates.isEmpty,
              !textView.hasMarkedText(),
              let storage = textView.textStorage else { return }

        let selection = textView.selectedRange()
        var revealed: Set<Int> = []
        for (index, element) in concealableElements.enumerated()
        where selection.location <= element.range.upperBound
            && selection.upperBound >= element.range.location {
            revealed.insert(index)
        }
        guard force || revealed != revealedElementIndices else { return }

        isHighlighting = true
        storage.beginEditing()
        for state in markerStates where state.range.upperBound <= storage.length {
            let shouldReveal = revealed.contains(state.elementIndex)
            guard force || shouldReveal != revealedElementIndices.contains(state.elementIndex) else { continue }
            if shouldReveal {
                storage.addAttributes([
                    .font: state.visibleFont,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ], range: state.range)
            } else {
                storage.addAttributes([
                    .font: Self.hiddenMarkerFont,
                    .foregroundColor: NSColor.clear
                ], range: state.range)
            }
        }
        storage.endEditing()
        isHighlighting = false
        revealedElementIndices = revealed
    }

    private func contentRange(of element: LivePreviewElement) -> NSRange {
        guard let first = element.markerRanges.first, let last = element.markerRanges.last,
              element.markerRanges.count == 2, last.location >= first.upperBound else {
            return element.range
        }
        return NSRange(location: first.upperBound, length: last.location - first.upperBound)
    }

    private func applyFontTraits(_ traits: NSFontTraitMask, in range: NSRange, to storage: NSTextStorage) {
        guard range.length > 0, range.upperBound <= storage.length else { return }
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: AppPreferences.editorFontSize)
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: subrange)
        }
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        paragraphStyle.paragraphSpacing = 4
        return [
            .font: NSFont.systemFont(ofSize: AppPreferences.editorFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func headingAttributes(size: CGFloat, weight: NSFont.Weight) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private func codeAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: max(12, AppPreferences.editorFontSize - 1), weight: .regular),
            .foregroundColor: NSColor.systemOrange
        ]
    }

    private func apply(
        pattern: String,
        attributes: [NSAttributedString.Key: Any],
        to storage: NSTextStorage,
        source: String
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (source as NSString).length)
        expression.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttributes(attributes, range: match.range)
        }
    }
}
