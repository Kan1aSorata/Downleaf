import AppKit
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

private struct PreviewRenderState: Equatable {
    let source: String
    let headings: [OutlineHeading]
    let baseURL: URL?

    static let empty = PreviewRenderState(source: "", headings: [], baseURL: nil)
}

@MainActor
final class PreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var pendingAnchor: String?
    private var desiredState = PreviewRenderState.empty
    private var loadingState: PreviewRenderState?
    private var loadedState: PreviewRenderState?
    private var currentNavigation: WKNavigation?
    private var processRecoveryAttempts = 0
    private(set) var isDocumentReady = false

    var onVisibleHeadingChange: ((String) -> Void)?

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(target: self), name: "outlinePosition")
        contentController.addUserScript(WKUserScript(
            source: Self.scrollTrackingScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = contentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .clear
        webView.setAccessibilityLabel("Markdown 阅读视图")
        view = webView
    }

    func setMarkdown(_ source: String, headings: [OutlineHeading], baseURL: URL?, preserving anchor: String?) {
        desiredState = PreviewRenderState(source: source, headings: headings, baseURL: baseURL)
        if let anchor {
            pendingAnchor = anchor
        }
        guard isViewLoaded else { return }
        loadDesiredHTMLIfNeeded()
    }

    func prepareIfNeeded() {
        loadViewIfNeeded()
        loadDesiredHTMLIfNeeded()
    }

    func scroll(to anchor: String) {
        pendingAnchor = anchor
        scrollToPendingAnchorIfPossible()
    }

    private func loadDesiredHTMLIfNeeded() {
        guard isViewLoaded else { return }
        if loadedState == desiredState, loadingState == nil {
            isDocumentReady = true
            scrollToPendingAnchorIfPossible()
            return
        }
        guard loadingState != desiredState else { return }

        currentNavigation = nil
        loadingState = nil
        webView.stopLoading()

        isDocumentReady = false
        let state = desiredState
        loadingState = state
        let html = MarkdownRenderer.html(for: state.source, headings: state.headings)
        currentNavigation = webView.loadHTMLString(html, baseURL: state.baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        loadedState = loadingState
        loadingState = nil
        currentNavigation = nil
        processRecoveryAttempts = 0
        isDocumentReady = true
        scrollToPendingAnchorIfPossible()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishFailedNavigation(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishFailedNavigation(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        currentNavigation = nil
        loadingState = nil
        loadedState = nil
        isDocumentReady = false

        guard processRecoveryAttempts < 2 else { return }
        processRecoveryAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.loadDesiredHTMLIfNeeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case "file", nil:
            decisionHandler(.allow)
        default:
            decisionHandler(.cancel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "outlinePosition", let anchor = message.body as? String else { return }
        onVisibleHeadingChange?(anchor)
    }

    private func finishFailedNavigation(_ navigation: WKNavigation?, error: Error) {
        guard navigation === currentNavigation else { return }
        currentNavigation = nil
        loadingState = nil
        isDocumentReady = false

        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        loadedState = nil
    }

    private func scrollToPendingAnchorIfPossible() {
        guard isViewLoaded, isDocumentReady, let pendingAnchor else { return }
        guard let anchorLiteral = Self.javaScriptStringLiteral(for: pendingAnchor) else {
            return
        }

        self.pendingAnchor = nil
        let script = """
        (() => {
          const element = document.getElementById(\(anchorLiteral));
          if (!element) return false;
          element.scrollIntoView({ block: 'start' });
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, (result as? Bool) != true else { return }
            self.pendingAnchor = pendingAnchor
        }
    }

    static func javaScriptStringLiteral(for value: String) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static let scrollTrackingScript = """
    (() => {
      let ticking = false;
      const report = () => {
        ticking = false;
        const headings = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6'));
        if (!headings.length) return;
        const threshold = window.scrollY + window.innerHeight * 0.25;
        let active = headings[0];
        for (const heading of headings) {
          if (heading.offsetTop <= threshold) active = heading;
          else break;
        }
        window.webkit.messageHandlers.outlinePosition.postMessage(active.id);
      };
      addEventListener('scroll', () => {
        if (!ticking) {
          ticking = true;
          requestAnimationFrame(report);
        }
      }, { passive: true });
      report();
    })();
    """
}
