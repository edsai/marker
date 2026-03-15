import Cocoa

class PreferencesWindowController: NSWindowController {
    private let fontSizeField = NSTextField()
    private let fontFamilyPopup = NSPopUpButton()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()

        self.init(window: window)
        setupUI()
        loadPreferences()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])

        // Font Size
        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 8
        let sizeLabel = NSTextField(labelWithString: "Font Size:")
        sizeLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        fontSizeField.placeholderString = "16"
        fontSizeField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let sizePx = NSTextField(labelWithString: "px")
        sizeRow.addArrangedSubview(sizeLabel)
        sizeRow.addArrangedSubview(fontSizeField)
        sizeRow.addArrangedSubview(sizePx)
        stack.addArrangedSubview(sizeRow)

        // Font Family
        let familyRow = NSStackView()
        familyRow.orientation = .horizontal
        familyRow.spacing = 8
        let familyLabel = NSTextField(labelWithString: "Font Family:")
        familyLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        fontFamilyPopup.addItems(withTitles: [
            "System Default", "Menlo", "SF Mono", "Monaco", "Courier New",
            "Source Code Pro", "JetBrains Mono", "Fira Code"
        ])
        fontFamilyPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        familyRow.addArrangedSubview(familyLabel)
        familyRow.addArrangedSubview(fontFamilyPopup)
        stack.addArrangedSubview(familyRow)

        // Apply button
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyPreferences))
        applyButton.bezelStyle = .rounded
        stack.addArrangedSubview(applyButton)
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        fontSizeField.integerValue = defaults.integer(forKey: "editorFontSize") > 0 ? defaults.integer(forKey: "editorFontSize") : 16
        let family = defaults.string(forKey: "editorFontFamily") ?? "System Default"
        fontFamilyPopup.selectItem(withTitle: family)
    }

    @objc private func applyPreferences() {
        let defaults = UserDefaults.standard
        let fontSize = fontSizeField.integerValue > 0 ? fontSizeField.integerValue : 16
        let fontFamily = fontFamilyPopup.titleOfSelectedItem ?? "System Default"

        defaults.set(fontSize, forKey: "editorFontSize")
        defaults.set(fontFamily, forKey: "editorFontFamily")

        // Apply to editor via bridge
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.windowController.editorVC?.bridge.setFontSize(fontSize)
            if fontFamily != "System Default" {
                appDelegate.windowController.editorVC?.bridge.setFontFamily(fontFamily)
            }
        }
    }
}
