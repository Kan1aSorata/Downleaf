import AppKit
import UniformTypeIdentifiers

private struct MarkdownContentState: Sendable {
    var text: String
    var fileFormat: MarkdownFileFormat

    static let empty = MarkdownContentState(text: "", fileFormat: .standard)
}

/// 外部（Git、终端、其他编辑器）改动磁盘文件后的处理决策。
enum ExternalChangeResolution: Equatable {
    /// 磁盘内容与内存一致（多半是自己的保存落盘），或已就同一磁盘版本问过用户。
    case ignore
    /// 本地无未保存修改，直接安静重载。
    case autoReload
    /// 本地有未保存修改且磁盘内容不同：必须让用户选择，绝不静默覆盖。
    case askUser

    static func decide(diskText: String, memoryText: String, isEdited: Bool, resolvedConflictText: String?) -> Self {
        guard diskText != memoryText else { return .ignore }
        guard isEdited else { return .autoReload }
        return diskText == resolvedConflictText ? .ignore : .askUser
    }
}

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override class var preservesVersions: Bool { false }

    nonisolated private let contentLock = NSLock()
    nonisolated(unsafe) private var contentState = MarkdownContentState.empty
    nonisolated var text: String { contentSnapshot().text }
    private var namedAutoSaveTask: Task<Void, Never>?
    private var recoverySaveTask: Task<Void, Never>?
    private var preferencesTask: Task<Void, Never>?
    private var externalChangeTask: Task<Void, Never>?
    private var isPresentingExternalChangeAlert = false
    /// 用户在冲突弹窗中选择“保留我的修改”时对应的磁盘内容；同一磁盘版本不再重复打扰。
    private var resolvedConflictDiskText: String?
    private var draftIdentifier = UUID()
    weak var primaryWindowController: DocumentWindowController?

    override init() {
        super.init()
        fileType = "net.daringfireball.markdown"
        hasUndoManager = true
        preferencesTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard !Task.isCancelled, let self else { return }
                self.preferencesDidChange()
            }
        }
    }

    convenience init(recoveredDraft: RecoveredDraft) {
        self.init()
        draftIdentifier = recoveredDraft.identifier
        replaceText(recoveredDraft.text)
        updateChangeCount(.changeDone)
    }

    deinit {
        namedAutoSaveTask?.cancel()
        recoverySaveTask?.cancel()
        preferencesTask?.cancel()
        externalChangeTask?.cancel()
    }

    // MARK: - 外部变更监测

    nonisolated override func presentedItemDidChange() {
        Task { @MainActor [weak self] in
            self?.scheduleExternalChangeCheck()
        }
    }

    private func scheduleExternalChangeCheck() {
        externalChangeTask?.cancel()
        externalChangeTask = Task { @MainActor [weak self] in
            // 合并 git checkout 等短时间内的连续文件事件。
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.handleExternalChange()
        }
    }

    private func handleExternalChange() {
        guard let url = fileURL,
              !isPresentingExternalChangeAlert,
              let data = try? Data(contentsOf: url),
              let decoded = try? MarkdownCodec.decode(data) else {
            return
        }

        switch ExternalChangeResolution.decide(
            diskText: decoded.text,
            memoryText: text,
            isEdited: isDocumentEdited,
            resolvedConflictText: resolvedConflictDiskText
        ) {
        case .ignore:
            break
        case .autoReload:
            reloadFromDisk(url: url)
        case .askUser:
            presentExternalChangeConflict(url: url, diskText: decoded.text)
        }
    }

    private func reloadFromDisk(url: URL) {
        do {
            try revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
            resolvedConflictDiskText = nil
            primaryWindowController?.refreshDocumentIdentity()
        } catch {
            presentError(error)
        }
    }

    private func presentExternalChangeConflict(url: URL, diskText: String) {
        isPresentingExternalChangeAlert = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(displayName ?? "文稿")”在磁盘上已被修改"
        alert.informativeText = "另一个应用修改了这个文件，而你在 Downleaf 中还有未保存的修改。请选择保留哪个版本。"
        alert.addButton(withTitle: "保留我的修改")
        alert.addButton(withTitle: "载入磁盘版本")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isPresentingExternalChangeAlert = false
            if response == .alertSecondButtonReturn {
                self.reloadFromDisk(url: url)
            } else {
                // 保留内存版本：记录磁盘内容避免重复弹窗；下一次保存会覆盖磁盘（用户已确认）。
                self.resolvedConflictDiskText = diskText
            }
        }

        if let parentWindow = primaryWindowController?.window {
            alert.beginSheetModal(for: parentWindow, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController(document: self)
        primaryWindowController = controller
        addWindowController(controller)
    }

    override func data(ofType typeName: String) throws -> Data {
        let content = contentSnapshot()
        return try MarkdownCodec.encode(content.text, format: content.fileFormat)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try MarkdownCodec.decode(data)
        replaceContent(with: MarkdownContentState(text: decoded.text, fileFormat: decoded.format))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.primaryWindowController?.replaceEditorTextAfterRevert(self.text)
        }
    }

    func userDidEdit(text newText: String) {
        replaceText(newText)
        updateChangeCount(.changeDone)
        scheduleRecoverySaveIfNeeded()
        scheduleNamedAutoSaveIfNeeded()
    }

    override func scheduleAutosaving() {
        // Downleaf owns both named-file autosave and untitled recovery timing.
    }

    override func close() {
        namedAutoSaveTask?.cancel()
        recoverySaveTask?.cancel()
        RecoveryStore.remove(identifier: draftIdentifier)
        super.close()
    }

    func scheduleNamedAutoSaveIfNeeded() {
        namedAutoSaveTask?.cancel()
        guard AppPreferences.autoSaveEnabled,
              isDocumentEdited,
              let url = fileURL,
              let type = fileType,
              !isDraft else {
            return
        }

        namedAutoSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard let self,
                  !Task.isCancelled,
                  AppPreferences.autoSaveEnabled,
                  self.isDocumentEdited,
                  let currentURL = self.fileURL,
                  currentURL == url else {
                return
            }

            self.save(to: url, ofType: type, for: .saveOperation) { error in
                if let error {
                    self.presentError(error)
                }
                self.primaryWindowController?.refreshDocumentIdentity()
            }
        }
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        namedAutoSaveTask?.cancel()
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let self {
                self.recoverySaveTask?.cancel()
                RecoveryStore.remove(identifier: self.draftIdentifier)
                self.resolvedConflictDiskText = nil
            }
            self?.primaryWindowController?.refreshDocumentIdentity()
            completionHandler(error)
        }
    }

    private func scheduleRecoverySaveIfNeeded() {
        recoverySaveTask?.cancel()
        guard AppPreferences.autoSaveEnabled,
              fileURL == nil,
              isDocumentEdited else {
            return
        }

        let identifier = draftIdentifier
        let snapshot = text
        recoverySaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self,
                  !Task.isCancelled,
                  AppPreferences.autoSaveEnabled,
                  self.fileURL == nil,
                  self.isDocumentEdited,
                  self.text == snapshot else {
                return
            }
            try? RecoveryStore.save(identifier: identifier, text: snapshot)
        }
    }

    nonisolated private func contentSnapshot() -> MarkdownContentState {
        contentLock.withLock { contentState }
    }

    nonisolated private func replaceContent(with newState: MarkdownContentState) {
        contentLock.withLock {
            contentState = newState
        }
    }

    nonisolated private func replaceText(_ newText: String) {
        contentLock.withLock {
            contentState.text = newText
        }
    }

    override func canClose(
        withDelegate delegate: Any,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard isDocumentEdited else {
            replyToCloseRequest(
                delegate: delegate,
                selector: shouldCloseSelector,
                shouldClose: true,
                contextInfo: contextInfo
            )
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "要保存对“\(displayName ?? "未命名")”所做的更改吗？"
        alert.informativeText = fileURL == nil || isDraft
            ? "这份文稿仍暂存在缓冲区。关闭后，未保存的内容将被丢弃。"
            : "如果不保存，最近的修改将被丢弃。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.saveForClosing { shouldClose in
                    self.replyToCloseRequest(
                        delegate: delegate,
                        selector: shouldCloseSelector,
                        shouldClose: shouldClose,
                        contextInfo: contextInfo
                    )
                }
            case .alertSecondButtonReturn:
                self.replyToCloseRequest(
                    delegate: delegate,
                    selector: shouldCloseSelector,
                    shouldClose: true,
                    contextInfo: contextInfo
                )
            default:
                self.replyToCloseRequest(
                    delegate: delegate,
                    selector: shouldCloseSelector,
                    shouldClose: false,
                    contextInfo: contextInfo
                )
            }
        }

        if let parentWindow = primaryWindowController?.window {
            alert.beginSheetModal(for: parentWindow, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func saveForClosing(completion: @escaping (Bool) -> Void) {
        guard let type = fileType else {
            completion(false)
            return
        }

        if let url = fileURL, !isDraft {
            save(to: url, ofType: type, for: .saveOperation) { [weak self] error in
                if let error {
                    self?.presentError(error)
                    completion(false)
                } else {
                    completion(true)
                }
            }
            return
        }

        let panel = NSSavePanel()
        panel.title = "保存 Markdown 文稿"
        panel.prompt = "保存"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }

        let handlePanelResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            self.save(to: url, ofType: type, for: .saveAsOperation) { error in
                if let error {
                    self.presentError(error)
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }

        if let parentWindow = primaryWindowController?.window {
            DispatchQueue.main.async {
                panel.beginSheetModal(for: parentWindow, completionHandler: handlePanelResponse)
            }
        } else {
            handlePanelResponse(panel.runModal())
        }
    }

    private var suggestedFilename: String {
        let currentName = displayName ?? "未命名"
        let base = currentName == "未命名" || currentName == "Untitled" ? "未命名" : currentName
        return base.lowercased().hasSuffix(".md") ? base : "\(base).md"
    }

    private func replyToCloseRequest(
        delegate: Any,
        selector: Selector?,
        shouldClose: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let selector, let object = delegate as? NSObject else { return }
        typealias Callback = @convention(c) (
            AnyObject,
            Selector,
            NSDocument,
            Bool,
            UnsafeMutableRawPointer?
        ) -> Void
        let implementation = object.method(for: selector)
        let callback = unsafeBitCast(implementation, to: Callback.self)
        callback(object, selector, self, shouldClose, contextInfo)
    }

    private func preferencesDidChange() {
        primaryWindowController?.preferencesDidChange()
        if AppPreferences.autoSaveEnabled {
            scheduleRecoverySaveIfNeeded()
            scheduleNamedAutoSaveIfNeeded()
        } else {
            namedAutoSaveTask?.cancel()
            recoverySaveTask?.cancel()
            RecoveryStore.remove(identifier: draftIdentifier)
        }
    }
}
