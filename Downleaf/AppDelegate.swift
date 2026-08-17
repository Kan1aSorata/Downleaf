import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var settingsWindowController: SettingsWindowController?
    private var pendingInitialDocumentWorkItem: DispatchWorkItem?
    private var documentsPendingTermination: [MarkdownDocument] = []
    private var isReviewingDocumentsForTermination = false
    private var terminationRequiresApplicationReply = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppPreferences.registerDefaults()
        NSApp.mainMenu = MenuBuilder.build(delegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        restoreRecoveredDrafts()

        let item = DispatchWorkItem {
            guard NSDocumentController.shared.documents.isEmpty else { return }
            do {
                _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            } catch {
                NSApp.presentError(error)
            }
        }
        pendingInitialDocumentWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    private func restoreRecoveredDrafts() {
        for recoveredDraft in RecoveryStore.loadAll() {
            let document = MarkdownDocument(recoveredDraft: recoveredDraft)
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pendingInitialDocumentWorkItem?.cancel()
        guard !NSDocumentController.shared.documents.isEmpty else { return .terminateNow }
        guard !isReviewingDocumentsForTermination else { return .terminateLater }

        beginTerminationReview(requiresApplicationReply: true)
        return .terminateLater
    }

    @objc func requestQuit(_ sender: Any?) {
        pendingInitialDocumentWorkItem?.cancel()
        guard !isReviewingDocumentsForTermination else { return }
        guard !NSDocumentController.shared.documents.isEmpty else {
            NSApp.terminate(sender)
            return
        }
        beginTerminationReview(requiresApplicationReply: false)
    }

    private func beginTerminationReview(requiresApplicationReply: Bool) {
        documentsPendingTermination = NSDocumentController.shared.documents.compactMap { $0 as? MarkdownDocument }
        isReviewingDocumentsForTermination = true
        terminationRequiresApplicationReply = requiresApplicationReply
        reviewNextDocumentForTermination()
    }

    private func reviewNextDocumentForTermination() {
        guard let document = documentsPendingTermination.first else {
            isReviewingDocumentsForTermination = false
            let requiresReply = terminationRequiresApplicationReply
            terminationRequiresApplicationReply = false
            if requiresReply {
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApp.terminate(nil)
            }
            return
        }

        document.showWindows()
        document.primaryWindowController?.window?.makeKeyAndOrderFront(nil)
        document.canClose(
            withDelegate: self,
            shouldClose: #selector(document(_:shouldClose:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func document(
        _ document: NSDocument,
        shouldClose: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard isReviewingDocumentsForTermination else { return }

        guard shouldClose else {
            documentsPendingTermination.removeAll()
            isReviewingDocumentsForTermination = false
            let requiresReply = terminationRequiresApplicationReply
            terminationRequiresApplicationReply = false
            if requiresReply {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
            return
        }

        documentsPendingTermination.removeAll { $0 === document }
        document.close()
        DispatchQueue.main.async { [weak self] in
            self?.reviewNextDocumentForTermination()
        }
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(sender)
        settingsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    @objc func toggleReadingMode(_ sender: Any?) {
        activeWindowController?.toggleReadingMode()
    }

    @objc func showSplitMode(_ sender: Any?) {
        activeWindowController?.setMode(.split)
    }

    @objc func showEditorMode(_ sender: Any?) {
        activeWindowController?.setMode(.editor)
    }

    @objc func toggleLivePreview(_ sender: Any?) {
        AppPreferences.livePreviewEnabled.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLivePreview(_:)) {
            menuItem.state = AppPreferences.livePreviewEnabled ? .on : .off
        }
        return true
    }

    @objc func toggleOutline(_ sender: Any?) {
        activeWindowController?.toggleOutline()
    }

    @objc func focusOutline(_ sender: Any?) {
        activeWindowController?.focusOutline()
    }

    @objc func showCommandPalette(_ sender: Any?) {
        activeWindowController?.showCommandPalette()
    }

    private var activeWindowController: DocumentWindowController? {
        if let document = NSDocumentController.shared.currentDocument as? MarkdownDocument {
            return document.primaryWindowController
        }
        return NSApp.keyWindow?.windowController as? DocumentWindowController
    }
}
