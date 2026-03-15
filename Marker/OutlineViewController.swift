import Cocoa
import WebKit

struct HeadingItem {
    let level: Int      // 1-6
    let text: String
    let index: Int      // position in DOM order (for scrollToHeading)
}

class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private var outlineView: NSOutlineView!
    private var headings: [HeadingItem] = []
    weak var bridge: MarkerBridge?
    var activeTabId: String?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.backgroundColor = .clear
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
    }

    /// Query DOM for headings and refresh the outline
    func refreshHeadings(webView: WKWebView?) {
        let js = """
        (function() {
            var active = document.querySelector('.editor-tab-container[style*="display: block"] .ProseMirror');
            if (!active) return [];
            var hs = active.querySelectorAll('h1, h2, h3, h4, h5, h6');
            return Array.from(hs).map(function(h, i) {
                return {level: parseInt(h.tagName[1]), text: h.textContent || '', index: i};
            });
        })()
        """

        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let items = result as? [[String: Any]] else {
                self?.headings = []
                self?.outlineView?.reloadData()
                return
            }
            self?.headings = items.compactMap { dict in
                guard let level = dict["level"] as? Int,
                      let text = dict["text"] as? String,
                      let index = dict["index"] as? Int else { return nil }
                return HeadingItem(level: level, text: text, index: index)
            }
            self?.outlineView?.reloadData()
        }
    }

    @objc private func rowClicked() {
        let row = outlineView.selectedRow
        guard row >= 0, row < headings.count,
              let tabId = activeTabId else { return }
        bridge?.scrollToHeading(tabId: tabId, index: headings[row].index)
    }

    // MARK: - NSOutlineViewDataSource (flat list)

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return headings.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return headings[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let heading = item as? HeadingItem else { return nil }

        let cellID = NSUserInterfaceItemIdentifier("HeadingCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        // Indent based on heading level
        let indent = CGFloat((heading.level - 1) * 12)
        cell.textField?.stringValue = heading.text
        cell.textField?.font = heading.level <= 2
            ? NSFont.systemFont(ofSize: 12, weight: .semibold)
            : NSFont.systemFont(ofSize: 12)
        cell.textField?.textColor = heading.level <= 2 ? .labelColor : .secondaryLabelColor

        // Update leading constraint for indent
        if let leading = cell.constraints.first(where: { $0.firstAttribute == .leading }) {
            leading.constant = 4 + indent
        }

        return cell
    }
}
