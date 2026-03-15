import WebKit

/// Typed Swift API over the JS marker.* bridge.
/// All marker.* functions are async in JS — uses callAsyncJavaScript to await them.
class MarkerBridge {
    private weak var webView: WKWebView?

    /// Pending requestMarkdown callbacks keyed by tabId
    private var markdownCallbacks: [String: (String?) -> Void] = [:]

    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Tab Operations

    func openTab(id: String, content: String, completion: ((Bool) -> Void)? = nil) {
        callAsync("await marker.openTab(tabId, content)",
                  arguments: ["tabId": id, "content": content]) { success in
            completion?(success)
        }
    }

    func switchTab(id: String) {
        callAsync("await marker.switchTab(tabId, content)",
                  arguments: ["tabId": id, "content": ""])
    }

    func closeTab(id: String) {
        callAsync("await marker.closeTab(tabId)",
                  arguments: ["tabId": id])
    }

    // MARK: - Content

    func requestMarkdown(id: String, completion: @escaping (String?) -> Void) {
        markdownCallbacks[id] = completion
        callAsync("await marker.requestMarkdown(tabId)",
                  arguments: ["tabId": id])
    }

    /// Called by MessageHandler when JS posts {type: "markdown", tabId, content}
    func handleMarkdownResponse(tabId: String, content: String?) {
        let callback = markdownCallbacks.removeValue(forKey: tabId)
        callback?(content)
    }

    // MARK: - Navigation

    func scrollToHeading(tabId: String, index: Int) {
        callAsync("marker.scrollToHeading(tabId, index)",
                  arguments: ["tabId": tabId, "index": index])
    }

    // MARK: - Appearance

    func setTheme(_ theme: String) {
        callAsync("marker.setTheme(theme)", arguments: ["theme": theme])
    }

    func setFontSize(_ px: Int) {
        callAsync("marker.setFontSize(px)", arguments: ["px": px])
    }

    func setFontFamily(_ family: String) {
        callAsync("marker.setFontFamily(family)", arguments: ["family": family])
    }

    // MARK: - Private

    private func callAsync(_ script: String, arguments: [String: Any] = [String: Any](),
                           completion: ((Bool) -> Void)? = nil) {
        webView?.callAsyncJavaScript(
            script, arguments: arguments,
            in: nil, in: .page
        ) { result in
            switch result {
            case .failure(let error):
                NSLog("Marker bridge: \(script) failed: \(error)")
                completion?(false)
            case .success:
                completion?(true)
            }
        }
    }
}
