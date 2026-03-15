import Foundation

protocol FileWatcherDelegate: AnyObject {
    func fileWatcher(_ watcher: FileWatcher, didDetectChangesAt paths: [String])
}

class FileWatcher {
    weak var delegate: FileWatcherDelegate?

    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var pendingPaths: Set<String> = []
    private let debounceInterval: TimeInterval = 0.5

    private let ignoredNames: Set<String> = [
        ".git", "node_modules", ".DS_Store", ".build", ".swiftpm",
        ".Trash", ".Spotlight-V100", ".fseventsd"
    ]

    func watch(directory: URL) {
        stop()

        let path = directory.path as CFString
        let paths = [path] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                watcher.handleEvents(paths: Array(cfPaths.prefix(numEvents)))
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,  // latency
            flags
        ) else {
            NSLog("Marker: failed to create FSEventStream")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        NSLog("Marker: watching \(directory.path)")
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        debounceWork?.cancel()
        pendingPaths.removeAll()
    }

    deinit {
        stop()
    }

    private func handleEvents(paths: [String]) {
        let filtered = paths.filter { path in
            let components = path.split(separator: "/")
            return !components.contains(where: { ignoredNames.contains(String($0)) })
        }

        guard !filtered.isEmpty else { return }

        pendingPaths.formUnion(filtered)

        // Debounce: wait 500ms for more events before notifying
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let paths = Array(self.pendingPaths)
            self.pendingPaths.removeAll()
            DispatchQueue.main.async {
                self.delegate?.fileWatcher(self, didDetectChangesAt: paths)
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
