import Cocoa

/// An NSView that automatically updates its layer background color when the
/// system appearance changes (dark ↔ light). Semantic NSColors like
/// .windowBackgroundColor resolve differently per appearance, but their
/// CGColor snapshots are static — this view re-snapshots on each change.
class AppearanceAwareView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = color.cgColor
    }
}
