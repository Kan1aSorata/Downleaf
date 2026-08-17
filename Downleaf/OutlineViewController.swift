import AppKit

private final class OutlineNode: NSObject {
    let heading: OutlineHeading
    weak var parent: OutlineNode?
    var children: [OutlineNode] = []

    init(heading: OutlineHeading) {
        self.heading = heading
    }
}

private final class KeyboardOutlineView: NSOutlineView {
    var activateSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            activateSelection?()
        case 115:
            if numberOfRows > 0 {
                selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                scrollRowToVisible(0)
            }
        case 119:
            if numberOfRows > 0 {
                let row = numberOfRows - 1
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                scrollRowToVisible(row)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

private final class OutlineScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}

@MainActor
final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outlineView = KeyboardOutlineView()
    private let scrollView = OutlineScrollView()
    private let emptyLabel = NSTextField(labelWithString: "输入标题后会显示大纲")
    private var roots: [OutlineNode] = []
    private var flatHeadings: [OutlineHeading] = []
    private var nodesByID: [String: OutlineNode] = [:]
    private var nodesByAnchor: [String: OutlineNode] = [:]
    private var collapsedIDs: Set<String> = []
    private var isFollowingSource = false
    private var suppressFollowingUntil = Date.distantPast
    private var activeHeadingID: String?

    var onActivate: ((OutlineHeading) -> Void)?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root

        let header = NSTextField(labelWithString: "大纲")
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(activateClickedRow(_:))
        outlineView.indentationPerLevel = 13
        outlineView.rowHeight = 24
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = false
        outlineView.autosaveExpandedItems = false
        outlineView.focusRingType = .default
        outlineView.setAccessibilityLabel("文稿大纲")
        outlineView.activateSelection = { [weak self] in self?.activateSelectedRow() }

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.onUserScroll = { [weak self] in
            self?.suppressFollowingUntil = Date().addingTimeInterval(1.2)
        }
        root.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 15),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 18),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -18)
        ])
    }

    func update(headings: [OutlineHeading]) {
        captureCollapsedState()
        flatHeadings = headings
        roots = buildTree(headings)
        nodesByID.removeAll(keepingCapacity: true)
        nodesByAnchor.removeAll(keepingCapacity: true)
        index(nodes: roots)

        outlineView.reloadData()
        restoreExpansion(nodes: roots)
        emptyLabel.isHidden = !headings.isEmpty
        scrollView.isHidden = headings.isEmpty

        if let activeHeadingID,
           let node = nodesByID[activeHeadingID] {
            select(node: node, reveal: false)
        } else if let first = headings.first {
            activeHeadingID = first.id
        }
    }

    func selectHeading(atSourceOffset offset: Int) {
        guard Date() >= suppressFollowingUntil,
              let heading = flatHeadings.last(where: { $0.sourceRange.location <= offset }),
              heading.id != activeHeadingID,
              let node = nodesByID[heading.id] else {
            return
        }
        activeHeadingID = heading.id
        select(node: node, reveal: true)
    }

    func selectHeading(anchor: String) {
        guard Date() >= suppressFollowingUntil,
              let node = nodesByAnchor[anchor],
              node.heading.id != activeHeadingID else {
            return
        }
        activeHeadingID = node.heading.id
        select(node: node, reveal: true)
    }

    func focusOutline() {
        guard !flatHeadings.isEmpty else { return }
        if outlineView.selectedRow < 0, let first = roots.first {
            select(node: first, reveal: true)
        }
        view.window?.makeFirstResponder(outlineView)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? OutlineNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? OutlineNode {
            return node.children[index]
        }
        return roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? OutlineNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("OutlineCell")
        let cell: NSTableCellView

        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = node.heading.title
        cell.textField?.font = .systemFont(ofSize: node.heading.level == 1 ? 12.5 : 12, weight: node.heading.level <= 2 ? .medium : .regular)
        cell.textField?.textColor = node.heading.id == activeHeadingID ? .labelColor : .secondaryLabelColor
        cell.toolTip = node.heading.title
        return cell
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? OutlineNode {
            collapsedIDs.insert(node.heading.id)
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? OutlineNode {
            collapsedIDs.remove(node.heading.id)
        }
    }

    private func activateSelectedRow() {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
        activeHeadingID = node.heading.id
        outlineView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows), columnIndexes: IndexSet(integer: 0))
        onActivate?(node.heading)
    }

    @objc private func activateClickedRow(_ sender: NSOutlineView) {
        guard !isFollowingSource else { return }
        activateSelectedRow()
    }

    private func buildTree(_ headings: [OutlineHeading]) -> [OutlineNode] {
        var roots: [OutlineNode] = []
        var stack: [OutlineNode] = []

        for heading in headings {
            let node = OutlineNode(heading: heading)
            while let last = stack.last, last.heading.level >= heading.level {
                stack.removeLast()
            }

            if let parent = stack.last {
                node.parent = parent
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }
        return roots
    }

    private func index(nodes: [OutlineNode]) {
        for node in nodes {
            nodesByID[node.heading.id] = node
            nodesByAnchor[node.heading.anchor] = node
            index(nodes: node.children)
        }
    }

    private func captureCollapsedState() {
        func walk(_ nodes: [OutlineNode]) {
            for node in nodes where !node.children.isEmpty {
                if outlineView.isItemExpanded(node) {
                    collapsedIDs.remove(node.heading.id)
                } else {
                    collapsedIDs.insert(node.heading.id)
                }
                walk(node.children)
            }
        }
        walk(roots)
    }

    private func restoreExpansion(nodes: [OutlineNode]) {
        for node in nodes {
            if !node.children.isEmpty, !collapsedIDs.contains(node.heading.id) {
                outlineView.expandItem(node)
            }
            restoreExpansion(nodes: node.children)
        }
    }

    private func select(node: OutlineNode, reveal: Bool) {
        var parent = node.parent
        while let current = parent {
            outlineView.expandItem(current)
            parent = current.parent
        }

        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        isFollowingSource = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if reveal {
            outlineView.scrollRowToVisible(row)
        }
        isFollowingSource = false

        if outlineView.numberOfRows > 0 {
            outlineView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows), columnIndexes: IndexSet(integer: 0))
        }
    }
}
