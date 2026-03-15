# B3: EditorWebViewController + MarkerBridge

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract WKWebView setup from AppDelegate into a proper `EditorWebViewController`, and create a typed `MarkerBridge` that wraps all `callAsyncJavaScript` calls with a clean Swift API. Handle the `markdown` callback and `cursorChanged` message.

**Architecture:** `EditorWebViewController` is an `NSViewController` whose view IS the WKWebView. It owns the `MarkerBridge` and `MessageHandler`. `MarkerBridge` provides typed methods (`openTab`, `switchTab`, `closeTab`, `requestMarkdown`, etc.) so callers never write JS strings. `MainWindowController` replaces its raw `webView` property with an `EditorWebViewController` embedded in the center pane. `AppDelegate` becomes thin — just lifecycle + file open routing.

**Tech Stack:** Swift 5.9, AppKit, WebKit (WKWebView, callAsyncJavaScript), macOS 12+

**What changes from B2:**
- `AppDelegate.swift` — remove WKWebView creation, MessageHandler, navigation delegate. Becomes thin.
- `MainWindowController.swift` — replace `var webView: WKWebView?` with `var editorVC: EditorWebViewController`. Remove all `callAsyncJavaScript` calls (moved to MarkerBridge). TabManagerDelegate calls bridge methods instead.
- `MessageHandler` — moves from AppDelegate.swift into EditorWebViewController.swift

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Marker/MarkerBridge.swift` | Create | Typed Swift API: `openTab(id:content:)`, `switchTab(id:)`, `closeTab(id:)`, `requestMarkdown(id:completion:)`, `scrollToHeading(id:index:)`, `setTheme(_:)`, `setFontSize(_:)`, `setFontFamily(_:)`. Wraps `callAsyncJavaScript`. |
| `Marker/EditorWebViewController.swift` | Create | `NSViewController` that owns WKWebView + MarkerBridge + MessageHandler. Handles WKNavigationDelegate, WKScriptMessageHandler. Posts delegate callbacks for bridge events (ready, dirty, cursorChanged, markdown, evicted, imagePaste). |
| `Marker/MainWindowController.swift` | Modify | Replace `var webView` with `var editorVC`. TabManagerDelegate calls `editorVC.bridge.xxx()` instead of raw JS. Remove direct webview management. |
| `Marker/AppDelegate.swift` | Modify | Remove WKWebView creation, MessageHandler class, navigation delegate. Create EditorWebViewController, embed in MainWindowController. Keep file open routing + bridgeReady logic. |

---

## Chunk 1: MarkerBridge (typed JS bridge API)

### Task 1: Create MarkerBridge

**Files:**
- Create: `Marker/MarkerBridge.swift`

- [ ] **Step 1: Write MarkerBridge.swift**

```swift
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
        // scrollToHeading is sync in JS, but callAsync handles it fine
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

    private func callAsync(_ script: String, arguments: [String: Any] = {},
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
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd /Users/esaipetch/devwork/marker-swift
xcodegen generate
xcodebuild -project Marker.xcodeproj -scheme Marker -configuration Debug build
```

- [ ] **Step 3: Commit**

```bash
git add Marker/MarkerBridge.swift
git commit -m "feat(B3): add MarkerBridge typed API over JS bridge"
```

---

## Chunk 2: EditorWebViewController

### Task 2: Create EditorWebViewController + refactor AppDelegate + MainWindowController

This is the big refactor. EditorWebViewController takes over WKWebView ownership from AppDelegate.

**Files:**
- Create: `Marker/EditorWebViewController.swift`
- Modify: `Marker/AppDelegate.swift`
- Modify: `Marker/MainWindowController.swift`

- [ ] **Step 1: Write EditorWebViewController.swift**

```swift
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

class EditorWebViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private(set) var webView: WKWebView!
    private(set) var bridge: MarkerBridge!
    weak var delegate: EditorDelegate?

    override func loadView() {
        // Create WKWebView as the view
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let contentController = WKUserContentController()
        contentController.add(self, name: "marker")
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

    // MARK: - Cleanup

    deinit {
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

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            NSLog("Marker: editor ready")
            delegate?.editorDidBecomeReady()

        case "dirty":
            if let tabId = body["tabId"] as? String,
               let isDirty = body["isDirty"] as? Bool {
                delegate?.editor(didChangeDirty: tabId, isDirty: isDirty)
            }

        case "cursorChanged":
            if let tabId = body["tabId"] as? String,
               let line = body["line"] as? Int,
               let col = body["col"] as? Int {
                delegate?.editor(didChangeCursor: tabId, line: line, col: col)
            }

        case "markdown":
            let tabId = body["tabId"] as? String ?? ""
            let content = body["content"] as? String
            bridge.handleMarkdownResponse(tabId: tabId, content: content)
            delegate?.editor(didReceiveMarkdown: tabId, content: content)

        case "evicted":
            if let tabId = body["tabId"] as? String,
               let markdown = body["markdown"] as? String {
                delegate?.editor(didEvictTab: tabId, markdown: markdown)
            }

        case "imagePaste":
            if let tabId = body["tabId"] as? String,
               let base64 = body["base64"] as? String,
               let ext = body["extension"] as? String {
                delegate?.editor(didPasteImage: tabId, base64: base64, fileExtension: ext)
            }

        default:
            NSLog("Marker: unknown bridge message: \(type)")
        }
    }
}
```

- [ ] **Step 2: Refactor MainWindowController.swift**

Key changes:
- Replace `var webView: WKWebView?` with `var editorVC: EditorWebViewController?`
- TabManagerDelegate calls `editorVC?.bridge.xxx()` instead of raw callAsyncJavaScript
- `tabBarDidRequestNewTab` uses `editorVC?.bridge.openTab()`
- Store cursor position for status bar update

Replace the webView property and all delegate methods. The full updated file:

Remove the `import WebKit` (no longer needed).

Replace the `webView` property with:
```swift
    var editorVC: EditorWebViewController? {
        didSet {
            oldValue?.view.removeFromSuperview()
            oldValue?.removeFromParent()
            guard let editorVC = editorVC else { return }
            addChild(editorVC)  // NSWindowController is not NSViewController — see note below
        }
    }
```

Wait — `NSWindowController` is NOT an `NSViewController`, so `addChild` doesn't work. Instead, embed the editor VC's view directly in the center container:

```swift
    var editorVC: EditorWebViewController? {
        didSet {
            oldValue?.view.removeFromSuperview()
            guard let editorVC = editorVC else { return }
            let editorView = editorVC.view
            editorView.translatesAutoresizingMaskIntoConstraints = false
            centerContainer.addSubview(editorView)
            NSLayoutConstraint.activate([
                editorView.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                editorView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
                editorView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                editorView.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            ])
        }
    }
```

Replace TabBarViewDelegate `tabBarDidRequestNewTab`:
```swift
    func tabBarDidRequestNewTab() {
        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        editorVC?.bridge.openTab(id: tabId, content: "") { [weak self] success in
            guard success else { return }
            self?.tabManager.addTab(id: tabId, title: "Untitled")
        }
    }
```

Replace TabManagerDelegate methods:
```swift
    func tabManager(_ manager: TabManager, didSwitchTo tab: Tab) {
        tabBarView.setActiveTab(id: tab.id)
        editorVC?.bridge.switchTab(id: tab.id)
    }

    func tabManager(_ manager: TabManager, didClose tab: Tab) {
        tabBarView.removeTab(id: tab.id)
        editorVC?.bridge.closeTab(id: tab.id)
    }
```

Add status bar update:
```swift
    func updateCursorPosition(line: Int, col: Int) {
        statusBar.stringValue = "  Ln \(line), Col \(col)"
    }
```

- [ ] **Step 3: Refactor AppDelegate.swift**

Remove: WKWebView creation, MessageHandler class, WKNavigationDelegate conformance, `webView` property, `messageHandler` property.

Add: EditorWebViewController creation, EditorDelegate conformance.

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, EditorDelegate {
    var windowController: MainWindowController!
    var pendingFiles: [String] = []
    private var bridgeReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Marker: applicationDidFinishLaunching")

        windowController = MainWindowController()

        // Create and embed editor view controller
        let editorVC = EditorWebViewController()
        editorVC.delegate = self
        windowController.editorVC = editorVC
        editorVC.loadEditor()

        windowController.showWindow(nil)
        windowController.setInitialDividerPositions()
        windowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            if bridgeReady {
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
        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        let title = (path as NSString).lastPathComponent

        windowController.editorVC?.bridge.openTab(id: tabId, content: content) { [weak self] success in
            guard success else { return }
            self?.windowController.tabManager.addTab(id: tabId, title: title, filePath: path)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - EditorDelegate

    func editorDidBecomeReady() {
        guard !bridgeReady else { return }
        bridgeReady = true
        windowController.tabManager.addTab(id: "welcome", title: "Welcome")
        NSLog("Marker: bridge ready, opening \(pendingFiles.count) pending files")
        for file in pendingFiles {
            openFile(path: file)
        }
        pendingFiles.removeAll()
    }

    func editor(didChangeDirty tabId: String, isDirty: Bool) {
        windowController.tabManager.setDirty(id: tabId, isDirty: isDirty)
    }

    func editor(didChangeCursor tabId: String, line: Int, col: Int) {
        windowController.updateCursorPosition(line: line, col: col)
    }

    func editor(didReceiveMarkdown tabId: String, content: String?) {
        // Used by B7 (file save) — log for now
        NSLog("Marker: received markdown for \(tabId), length=\(content?.count ?? 0)")
    }

    func editor(didEvictTab tabId: String, markdown: String) {
        // Used by B9 (session persistence) — log for now
        NSLog("Marker: tab \(tabId) evicted from pool")
    }

    func editor(didPasteImage tabId: String, base64: String, fileExtension: String) {
        // Used by B7 (image save) — log for now
        NSLog("Marker: image pasted in \(tabId)")
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
cd /Users/esaipetch/devwork/marker-swift
xcodegen generate
xcodebuild -project Marker.xcodeproj -scheme Marker -configuration Debug build
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild -project Marker.xcodeproj -scheme MarkerTests -configuration Debug test -destination 'platform=macOS'
```

- [ ] **Step 6: Run the app and manually verify**

Launch the app. Expected:
- Tab bar with "Welcome" tab appears
- + adds tabs, ✕ closes tabs, click to switch
- Dirty indicator works
- Status bar updates cursor position (Ln X, Col Y)
- Sidebars still visible and collapsible

- [ ] **Step 7: Commit**

```bash
git add Marker/EditorWebViewController.swift Marker/MainWindowController.swift Marker/AppDelegate.swift
git commit -m "feat(B3): extract EditorWebViewController, refactor AppDelegate and MainWindowController

- EditorWebViewController owns WKWebView + MarkerBridge + MessageHandler
- EditorDelegate protocol for bridge event callbacks
- MainWindowController uses editorVC.bridge instead of raw JS calls
- AppDelegate is now thin — just lifecycle + file routing
- Cursor position updates flow to status bar
- deinit removes script message handler (fixes B3.5 crash recovery)"
```

---

## Chunk 3: getMarkdown round-trip verification

### Task 3: Verify getMarkdown round-trip

The `requestMarkdown` → `postMessage("markdown")` callback is wired but needs verification.

**Files:**
- None (manual test only — the code is already in MarkerBridge + EditorWebViewController)

- [ ] **Step 1: Add a temporary test in AppDelegate to verify the round-trip**

In `editorDidBecomeReady()`, add after the pending files flush:

```swift
// Verify getMarkdown round-trip
windowController.editorVC?.bridge.requestMarkdown(id: "welcome") { content in
    NSLog("Marker: getMarkdown round-trip test: \(content?.prefix(50) ?? "nil")")
}
```

- [ ] **Step 2: Run the app, check logs for the round-trip result**

Expected log: `Marker: getMarkdown round-trip test: # Welcome to Marker`

- [ ] **Step 3: Remove the test code and commit if needed**

---

## Acceptance Criteria Verification

| Criteria | Status |
|----------|--------|
| WKWebView loads editor.html and Milkdown renders | Already working (B1/B2), preserved |
| Can open tabs, switch between them, content changes | Already working (B2), now via MarkerBridge |
| Dirty flag propagates to Swift tab bar | Already working (B2), now via EditorDelegate |
| Cursor position updates in (future) status bar | NEW — wired in EditorDelegate → MainWindowController.updateCursorPosition |
| getMarkdown round-trip works | NEW — MarkerBridge.requestMarkdown → JS postMessage → handleMarkdownResponse |
