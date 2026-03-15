import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var pendingFiles: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Marker: applicationDidFinishLaunching")

        // Create window
        let windowRect = NSRect(x: 0, y: 0, width: 1200, height: 800)
        window = NSWindow(contentRect: windowRect,
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered,
                         defer: false)
        window.center()
        window.title = "Marker"
        window.minSize = NSSize(width: 600, height: 400)

        // Create WKWebView
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let contentController = WKUserContentController()
        contentController.add(MessageHandler(), name: "marker")
        config.userContentController = contentController

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self

        // Ensure the WebView is properly visible
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView?.addSubview(webView)
        window.contentView?.wantsLayer = true

        // Load editor from bundle resources
        let editorURL = Bundle.main.url(forResource: "editor", withExtension: "html")
        NSLog("Marker: editor URL = \(String(describing: editorURL))")
        NSLog("Marker: bundle path = \(Bundle.main.bundlePath)")
        NSLog("Marker: resource path = \(String(describing: Bundle.main.resourcePath))")

        if let url = editorURL {
            NSLog("Marker: loading \(url)")
            let resourceDir = url.deletingLastPathComponent()
            NSLog("Marker: allowing read access to \(resourceDir)")
            webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
        } else {
            NSLog("Marker: ERROR - editor.html not found!")
            // Show error in the window
            let label = NSTextField(labelWithString: "editor.html not found in bundle")
            label.frame = NSRect(x: 50, y: 400, width: 500, height: 30)
            label.textColor = .red
            window.contentView?.addSubview(label)
        }

        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("Marker: page finished loading")

        // Check if marker bridge is available
        webView.evaluateJavaScript("typeof window.marker") { result, error in
            NSLog("Marker: bridge check = \(String(describing: result)), error = \(String(describing: error))")

            if let result = result as? String, result == "object" {
                NSLog("Marker: bridge loaded OK, opening pending files")
                for file in self.pendingFiles {
                    self.openFile(path: file)
                }
                self.pendingFiles.removeAll()
            }
        }

        // Also check for JS errors
        webView.evaluateJavaScript("document.body.innerHTML.substring(0, 200)") { result, error in
            NSLog("Marker: body = \(String(describing: result))")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Marker: navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("Marker: provisional navigation failed: \(error)")
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            if webView != nil {
                openFile(path: filename)
            } else {
                pendingFiles.append(filename)
            }
        }
        application.reply(toOpenOrPrint: .success)
    }

    func openFile(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                            .replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        webView.evaluateJavaScript("marker.openTab('\(tabId)', '\(escaped)')") { _, error in
            if let error = error {
                NSLog("Marker: Failed to open tab: \(error)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

class MessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        NSLog("Marker: bridge message: \(type)")
    }
}
