import AppKit

private extension NSToolbarItem.Identifier {
    static let downleafMode = NSToolbarItem.Identifier("Downleaf.Mode")
    static let downleafOutline = NSToolbarItem.Identifier("Downleaf.Outline")
}

@MainActor
final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    unowned let markdownDocument: MarkdownDocument
    private let rootSplitViewController: DocumentRootSplitViewController
    private var modeControl: NSSegmentedControl?
    private var outlineButton: NSButton?
    private var commandPaletteController: CommandPaletteController?

    private static let defaultContentSize = NSSize(width: 1180, height: 760)
    private static let frameAutosaveName = "Downleaf.DocumentWindow"

    init(document: MarkdownDocument) {
        markdownDocument = document
        rootSplitViewController = DocumentRootSplitViewController(document: document)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = rootSplitViewController
        window.minSize = NSSize(width: 660, height: 460)
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unifiedCompact
        window.tabbingMode = .disallowed
        window.isRestorable = false
        let hasSavedFrame = UserDefaults.standard.object(
            forKey: "NSWindow Frame \(Self.frameAutosaveName)"
        ) != nil
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "Downleaf.DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar

        if !hasSavedFrame {
            window.setContentSize(Self.defaultContentSize)
            window.center()
        }

        rootSplitViewController.onModeChange = { [weak self] mode in
            self?.updateModeControl(mode)
        }
        rootSplitViewController.onDocumentStateChange = { [weak self] in
            self?.refreshDocumentIdentity()
        }
        rootSplitViewController.onOutlineVisibilityChange = { [weak self] visible in
            self?.updateOutlineButton(visible: visible)
        }

        refreshDocumentIdentity()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        refreshDocumentIdentity()
    }

    func setMode(_ mode: DocumentMode) {
        rootSplitViewController.setMode(mode)
        updateModeControl(mode)
    }

    func toggleReadingMode() {
        rootSplitViewController.toggleReadingMode()
        updateModeControl(rootSplitViewController.mode)
    }

    func toggleOutline() {
        rootSplitViewController.toggleOutline()
    }

    func focusOutline() {
        rootSplitViewController.focusOutline()
    }

    func showCommandPalette() {
        if commandPaletteController == nil {
            commandPaletteController = CommandPaletteController(owner: self)
        }
        commandPaletteController?.present()
    }

    func replaceEditorTextAfterRevert(_ text: String) {
        rootSplitViewController.replaceEditorTextAfterRevert(text)
        refreshDocumentIdentity()
    }

    func preferencesDidChange() {
        rootSplitViewController.preferencesDidChange()
    }

    func refreshDocumentIdentity() {
        guard let window else { return }
        synchronizeWindowTitleWithDocumentName()
        window.title = markdownDocument.displayName
        window.representedURL = markdownDocument.fileURL
        window.isDocumentEdited = markdownDocument.isDocumentEdited

        if markdownDocument.fileURL == nil || markdownDocument.isDraft {
            window.subtitle = "暂存于缓冲区"
        } else if markdownDocument.isDocumentEdited {
            window.subtitle = AppPreferences.autoSaveEnabled ? "等待自动保存" : "未保存"
        } else {
            window.subtitle = "已保存"
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .downleafMode, .flexibleSpace, .downleafOutline]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .space, .downleafMode, .downleafOutline]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .downleafMode:
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "pencil", accessibilityDescription: "编辑")!,
                    NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "分栏")!,
                    NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "阅读")!
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(modeChanged(_:))
            )
            if #available(macOS 26.0, *) {
                control.segmentStyle = .automatic
                control.borderShape = .capsule
            } else {
                control.segmentStyle = .texturedSquare
            }
            control.selectedSegment = rootSplitViewController.mode.rawValue
            control.setToolTip("源码编辑", forSegment: 0)
            control.setToolTip("分栏预览", forSegment: 1)
            control.setToolTip("纯阅读", forSegment: 2)
            control.translatesAutoresizingMaskIntoConstraints = false
            let controlSize = if #available(macOS 26.0, *) {
                NSSize(width: 112, height: 30)
            } else {
                NSSize(width: 104, height: 26)
            }
            NSLayoutConstraint.activate([
                control.widthAnchor.constraint(equalToConstant: controlSize.width),
                control.heightAnchor.constraint(equalToConstant: controlSize.height)
            ])
            modeControl = control

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "阅读方式"
            item.paletteLabel = "阅读方式"
            item.view = control
            return item

        case .downleafOutline:
            let button = NSButton(
                image: outlineImage(visible: rootSplitViewController.isOutlineVisible),
                target: self,
                action: #selector(toggleOutlineFromToolbar(_:))
            )
            if #available(macOS 26.0, *) {
                button.bezelStyle = .glass
                button.borderShape = .circle
            } else {
                button.bezelStyle = .texturedRounded
            }
            button.toolTip = "显示或隐藏大纲（⌥⌘O）"
            button.translatesAutoresizingMaskIntoConstraints = false
            let buttonSide: CGFloat = if #available(macOS 26.0, *) { 30 } else { 26 }
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: buttonSide),
                button.heightAnchor.constraint(equalToConstant: buttonSide)
            ])
            outlineButton = button

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "大纲"
            item.paletteLabel = "大纲"
            item.view = button
            return item
        default:
            return nil
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshDocumentIdentity()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let mode = DocumentMode(rawValue: sender.selectedSegment) else { return }
        setMode(mode)
    }

    @objc private func toggleOutlineFromToolbar(_ sender: Any?) {
        toggleOutline()
    }

    private func updateModeControl(_ mode: DocumentMode) {
        modeControl?.selectedSegment = mode.rawValue
    }

    private func updateOutlineButton(visible: Bool) {
        outlineButton?.image = outlineImage(visible: visible)
        outlineButton?.contentTintColor = visible ? .controlAccentColor : .secondaryLabelColor
    }

    private func outlineImage(visible: Bool) -> NSImage {
        let name = visible ? "sidebar.right" : "sidebar.right"
        return NSImage(systemSymbolName: name, accessibilityDescription: visible ? "隐藏大纲" : "显示大纲")!
    }
}
