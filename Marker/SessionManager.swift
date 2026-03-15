import Foundation

struct SessionState: Codable {
    struct TabState: Codable {
        let id: String
        let title: String
        let filePath: String?
        let isDirty: Bool
    }

    var tabs: [TabState]
    var activeTabId: String?
    var workspaceURL: String?
}

class SessionManager {
    private static let sessionDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Marker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var sessionFile: URL {
        sessionDir.appendingPathComponent("session.json")
    }

    static func save(tabManager: TabManager, workspaceURL: URL?) {
        let state = SessionState(
            tabs: tabManager.tabs.map { tab in
                SessionState.TabState(id: tab.id, title: tab.title, filePath: tab.filePath, isDirty: tab.isDirty)
            },
            activeTabId: tabManager.activeTabId,
            workspaceURL: workspaceURL?.path
        )

        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: sessionFile, options: .atomic)
        } catch {
            NSLog("Marker: failed to save session: \(error)")
        }
    }

    static func restore() -> SessionState? {
        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return nil }
        do {
            let data = try Data(contentsOf: sessionFile)
            return try JSONDecoder().decode(SessionState.self, from: data)
        } catch {
            NSLog("Marker: failed to restore session: \(error)")
            return nil
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: sessionFile)
    }
}
