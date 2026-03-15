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

    func applicationWillTerminate(_ notification: Notification) {
        // Break WKUserContentController → MessageHandler retain before exit
        windowController.editorVC?.cleanup()
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
