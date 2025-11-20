import SwiftUI
import Carbon

struct KeyboardShortcutRecorder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update if needed
    }
}

class ShortcutRecorderView: NSView {
    private var isRecording = false
    private var eventMonitor: Any?

    private let settings = AppSettings.shared

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 150, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let text: String
        let color: NSColor

        if isRecording {
            text = "Press shortcut..."
            color = .secondaryLabelColor
        } else {
            text = formatShortcut()
            color = .labelColor
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = CGRect(x: 0, y: (bounds.height - 20) / 2, width: bounds.width, height: 20)
        text.draw(in: textRect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        needsDisplay = true

        layer?.borderColor = NSColor.controlAccentColor.cgColor

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // Ignore just modifier keys
            if event.type == .flagsChanged {
                return nil
            }

            // Get key code and modifiers
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags

            // Require at least one modifier
            var carbonModifiers: UInt32 = 0

            if modifiers.contains(.command) {
                carbonModifiers |= UInt32(cmdKey)
            }
            if modifiers.contains(.shift) {
                carbonModifiers |= UInt32(shiftKey)
            }
            if modifiers.contains(.option) {
                carbonModifiers |= UInt32(optionKey)
            }
            if modifiers.contains(.control) {
                carbonModifiers |= UInt32(controlKey)
            }

            if carbonModifiers != 0 {
                // Save the shortcut
                self.settings.keyboardShortcutKeyCode = UInt32(keyCode)
                self.settings.keyboardShortcutModifiers = carbonModifiers

                // Update the hot key registration
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.updateHotKey()
                }
            }

            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        layer?.borderColor = NSColor.separatorColor.cgColor

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        needsDisplay = true
    }

    private func formatShortcut() -> String {
        let modifiers = settings.keyboardShortcutModifiers
        let keyCode = settings.keyboardShortcutKeyCode

        var result = ""

        if modifiers & UInt32(controlKey) != 0 {
            result += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            result += "⌘"
        }

        // Convert key code to character
        if let key = keyCodeToString(UInt16(keyCode)) {
            result += key
        }

        return result.isEmpty ? "Click to set" : result
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        // Map common key codes to their string representations
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]

        return keyMap[keyCode]
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
