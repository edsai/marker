import Cocoa
import WebKit

protocol EditorDelegate: AnyObject {
    func editorDidBecomeReady()
    func editor(didChangeDirty tabId: String, isDirty: Bool)
    func editor(didChangeCursor tabId: String, line: Int, col: Int)
    func editor(didReceiveMarkdown tabId: String, content: String?)
    func editor(didEvictTab tabId: String, markdown: String)
    func editor(didPasteImage tabId: String, base64: String, fileExtension: String)
}

class EditorWebViewController: NSViewController, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private(set) var bridge: MarkerBridge!
    private var messageHandler: EditorMessageHandler?
    weak var delegate: EditorDelegate?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let contentController = WKUserContentController()

        // Use separate message handler to avoid retain cycle
        // (WKUserContentController retains handlers strongly)
        let handler = EditorMessageHandler(editorVC: self)
        messageHandler = handler
        contentController.add(handler, name: "marker")
        config.userContentController = contentController

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.wantsLayer = true
        wv.layer?.backgroundColor = NSColor.black.cgColor

        webView = wv
        bridge = MarkerBridge(webView: wv)
        self.view = wv
    }

    func loadEditor() {
        guard let url = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            NSLog("Marker: ERROR - editor.html not found!")
            return
        }
        let resourceDir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
    }

    /// Remove script message handler to break WKUserContentController retain.
    /// Called from AppDelegate.applicationWillTerminate.
    func cleanup() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "marker")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("Marker: page finished loading")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Marker: navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("Marker: provisional navigation failed: \(error)")
    }
}

// MARK: - EditorMessageHandler

/// Separate class to avoid WKUserContentController → EditorWebViewController retain cycle.
/// WKUserContentController retains handlers strongly; this class holds VC weakly.
class EditorMessageHandler: NSObject, WKScriptMessageHandler {
    weak var editorVC: EditorWebViewController?

    init(editorVC: EditorWebViewController) {
        self.editorVC = editorVC
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            NSLog("Marker: editor ready")
            editorVC?.delegate?.editorDidBecomeReady()

        case "dirty":
            if let tabId = body["tabId"] as? String,
               let isDirty = body["isDirty"] as? Bool {
                editorVC?.delegate?.editor(didChangeDirty: tabId, isDirty: isDirty)
            }

        case "cursorChanged":
            if let tabId = body["tabId"] as? String,
               let line = body["line"] as? Int,
               let col = body["col"] as? Int {
                editorVC?.delegate?.editor(didChangeCursor: tabId, line: line, col: col)
            }

        case "markdown":
            let tabId = body["tabId"] as? String ?? ""
            let content = body["content"] as? String
            editorVC?.bridge.handleMarkdownResponse(tabId: tabId, content: content)
            editorVC?.delegate?.editor(didReceiveMarkdown: tabId, content: content)

        case "evicted":
            if let tabId = body["tabId"] as? String,
               let markdown = body["markdown"] as? String {
                editorVC?.delegate?.editor(didEvictTab: tabId, markdown: markdown)
            }

        case "imagePaste":
            if let tabId = body["tabId"] as? String,
               let base64 = body["base64"] as? String,
               let ext = body["extension"] as? String {
                editorVC?.delegate?.editor(didPasteImage: tabId, base64: base64, fileExtension: ext)
            }

        default:
            NSLog("Marker: unknown bridge message: \(type)")
        }
    }
}
