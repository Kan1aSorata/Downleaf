import AppKit

private struct PaletteCommand {
    let title: String
    let shortcut: String
    let searchTerms: String
    let action: () -> Void
}

private final class CommandSearchField: NSSearchField {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onMove: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onConfirm?()
        case 53:
            onCancel?()
        case 125:
            onMove?(1)
        case 126:
            onMove?(-1)
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class CommandPaletteController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private weak var documentWindowController: DocumentWindowController?
    private let searchField = CommandSearchField()
    private let tableView = NSTableView()
    private var commands: [PaletteCommand] = []
    private var filteredCommands: [PaletteCommand] = []

    init(owner: DocumentWindowController) {
        self.documentWindowController = owner

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 330),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "命令面板"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor

        super.init(window: panel)
        panel.delegate = self
        buildCommands()
        buildInterface(in: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let panel = window, let parent = documentWindowController?.window else { return }
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.setFrameOrigin(NSPoint(
            x: parent.frame.midX - panel.frame.width / 2,
            y: parent.frame.maxY - panel.frame.height - 92
        ))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        searchField.stringValue = ""
        updateFilter()
    }

    func dismiss() {
        if let panel = window, let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateFilter()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredCommands.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredCommands.indices.contains(row) else { return nil }
        let command = filteredCommands[row]
        let identifier = NSUserInterfaceItemIdentifier("CommandCell")
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let title = NSTextField(labelWithString: "")
            title.tag = 1
            title.font = .systemFont(ofSize: 13)
            title.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(title)

            let shortcut = NSTextField(labelWithString: "")
            shortcut.tag = 2
            shortcut.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            shortcut.textColor = .tertiaryLabelColor
            shortcut.alignment = .right
            shortcut.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(shortcut)

            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                shortcut.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 10),
                shortcut.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                shortcut.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        (cell.viewWithTag(1) as? NSTextField)?.stringValue = command.title
        (cell.viewWithTag(2) as? NSTextField)?.stringValue = command.shortcut
        return cell
    }

    private func buildCommands() {
        commands = [
            PaletteCommand(title: "新建文稿", shortcut: "⌘N", searchTerms: "new 新建") { [weak self] in
                self?.dismiss()
                NSDocumentController.shared.newDocument(nil)
            },
            PaletteCommand(title: "打开文稿…", shortcut: "⌘O", searchTerms: "open 打开") { [weak self] in
                self?.dismiss()
                NSDocumentController.shared.openDocument(nil)
            },
            PaletteCommand(title: "保存", shortcut: "⌘S", searchTerms: "save 保存") { [weak self] in
                self?.dismiss()
                self?.documentWindowController?.markdownDocument.save(nil)
            },
            PaletteCommand(title: "源码编辑", shortcut: "", searchTerms: "editor edit 源码 编辑") { [weak self] in
                self?.dismiss()
                self?.documentWindowController?.setMode(.editor)
            },
            PaletteCommand(title: "分栏预览", shortcut: "⌥⌘E", searchTerms: "split preview 分栏 预览") { [weak self] in
                self?.dismiss()
                self?.documentWindowController?.setMode(.split)
            },
            PaletteCommand(title: "纯阅读", shortcut: "⌘E", searchTerms: "reader reading 阅读") { [weak self] in
                self?.dismiss()
                self?.documentWindowController?.setMode(.reader)
            },
            PaletteCommand(title: "显示 / 隐藏大纲", shortcut: "⌥⌘O", searchTerms: "outline 大纲 目录") { [weak self] in
                self?.dismiss()
                self?.documentWindowController?.toggleOutline()
            },
            PaletteCommand(title: "跳转标题", shortcut: "⌘J", searchTerms: "jump heading 跳转 标题") { [weak self] in
                self?.dismiss()
                self?.documentWindowController?.focusOutline()
            },
            PaletteCommand(title: "设置…", shortcut: "⌘,", searchTerms: "settings preferences 设置 偏好") { [weak self] in
                self?.dismiss()
                (NSApp.delegate as? AppDelegate)?.showSettings(nil)
            }
        ]
        filteredCommands = commands
    }

    private func buildInterface(in panel: NSPanel) {
        guard let content = panel.contentView else { return }

        searchField.placeholderString = "搜索命令"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.onConfirm = { [weak self] in self?.runSelection() }
        searchField.onCancel = { [weak self] in self?.dismiss() }
        searchField.onMove = { [weak self] delta in self?.moveSelection(delta) }
        content.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Commands"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 34
        tableView.selectionHighlightStyle = .regular
        tableView.doubleAction = #selector(runSelection)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
    }

    private func updateFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredCommands = query.isEmpty ? commands : commands.filter {
            $0.title.lowercased().contains(query) || $0.searchTerms.lowercased().contains(query)
        }
        tableView.reloadData()
        if !filteredCommands.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredCommands.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = min(max(0, current + delta), filteredCommands.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func runSelection() {
        let row = tableView.selectedRow
        guard filteredCommands.indices.contains(row) else { return }
        filteredCommands[row].action()
    }
}
