import AppKit
import UniformTypeIdentifiers

private struct MarkdownContentState: Sendable {
    var text: String
    var fileFormat: MarkdownFileFormat

    static let empty = MarkdownContentState(text: "", fileFormat: .standard)
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
