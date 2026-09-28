#!/bin/bash
# Goal Countdown — shows days left until your goal date on your desktop and in the menu bar.
# Run:  bash install-goal-countdown.sh
set -e

APP_NAME="GoalCountdown"
APP_DIR="$HOME/Applications/$APP_NAME.app"
BUILD_DIR="$(mktemp -d)"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Installing Apple's Command Line Tools..."
  xcode-select --install || true
  echo "When that install finishes, run this script again."
  exit 1
fi

cat > "$BUILD_DIR/main.swift" <<'SWIFT'
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let defaults = UserDefaults.standard

    // Desktop widget
    var desktopWindow: NSWindow?
    let titleLabel = NSTextField(labelWithString: "")
    let numberLabel = NSTextField(labelWithString: "")
    let unitLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")

    var goalDate: Date? {
        get { defaults.object(forKey: "goalDate") as? Date }
        set { defaults.set(newValue, forKey: "goalDate") }
    }
    var goalTitle: String {
        get { defaults.string(forKey: "goalTitle") ?? "Goal" }
        set { defaults.set(newValue, forKey: "goalTitle") }
    }
    var showOnDesktop: Bool {
        get { defaults.object(forKey: "showOnDesktop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showOnDesktop") }
    }
    var corner: String {
        get { defaults.string(forKey: "corner") ?? "topLeft" }
        set { defaults.set(newValue, forKey: "corner") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        makeDesktopWindow()
        refresh()
        // Update every minute so the count rolls over at midnight
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.positionDesktopWindow() }
        if goalDate == nil { setGoal() }
    }

    func daysLeft() -> Int? {
        guard let goal = goalDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: goal)).day
    }

    // MARK: Desktop widget

    func makeDesktopWindow() {
        let size = NSSize(width: 260, height: 190)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: .borderless, backing: .buffered, defer: false)
        // Sit just above the wallpaper, below all normal windows
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.appearance = NSAppearance(named: .darkAqua)

        let card = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 24
        card.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        unitLabel.font = .systemFont(ofSize: 15, weight: .medium)
        unitLabel.textColor = .secondaryLabelColor
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .tertiaryLabelColor
        for l in [titleLabel, numberLabel, unitLabel, dateLabel] {
            l.alignment = .center
            l.lineBreakMode = .byTruncatingTail
        }

        let stack = NSStackView(views: [titleLabel, numberLabel, unitLabel, dateLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.setCustomSpacing(6, after: unitLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, constant: -24),
        ])

        w.contentView = card
        desktopWindow = w
        positionDesktopWindow()
    }

    func positionDesktopWindow() {
        guard let w = desktopWindow, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame, s = w.frame.size, m: CGFloat = 40
        let origin: NSPoint
        switch corner {
        case "topRight":    origin = NSPoint(x: vf.maxX - s.width - m, y: vf.maxY - s.height - m)
        case "bottomLeft":  origin = NSPoint(x: vf.minX + m, y: vf.minY + m)
        case "bottomRight": origin = NSPoint(x: vf.maxX - s.width - m, y: vf.minY + m)
        case "center":      origin = NSPoint(x: vf.midX - s.width / 2, y: vf.midY - s.height / 2)
        default:            origin = NSPoint(x: vf.minX + m, y: vf.maxY - s.height - m)
        }
        w.setFrameOrigin(origin)
    }

    // MARK: Refresh

    func refresh() {
        let f = DateFormatter(); f.dateStyle = .long
        var barTitle = "🎯 Set a goal"
        var details = ["No goal set"]

        if let days = daysLeft(), let goal = goalDate {
            titleLabel.stringValue = goalTitle
            dateLabel.stringValue = f.string(from: goal)
            details = ["\(goalTitle) — \(f.string(from: goal))"]
            if days > 0 {
                barTitle = "🎯 \(goalTitle) · \(days)d"
                numberLabel.stringValue = "\(days)"
                unitLabel.stringValue = days == 1 ? "day to go" : "days to go"
                details.append("\(days / 7) weeks, \(days % 7) days to go")
            } else if days == 0 {
                barTitle = "🎯 \(goalTitle) · TODAY"
                numberLabel.stringValue = "🎉"
                unitLabel.stringValue = "It's today!"
            } else {
                barTitle = "✅ \(goalTitle) · \(-days)d ago"
                numberLabel.stringValue = "\(-days)"
                unitLabel.stringValue = -days == 1 ? "day since" : "days since"
            }
        } else {
            titleLabel.stringValue = "No goal yet"
            numberLabel.stringValue = "–"
            unitLabel.stringValue = "Click 🎯 in the menu bar"
            dateLabel.stringValue = ""
        }

        statusItem.button?.title = barTitle
        if showOnDesktop { desktopWindow?.orderFront(nil) } else { desktopWindow?.orderOut(nil) }

        // Menu
        let menu = NSMenu()
        for line in details {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Change Goal…", action: #selector(setGoal), keyEquivalent: "g").target = self

        let toggle = NSMenuItem(title: "Show on Desktop", action: #selector(toggleDesktop), keyEquivalent: "d")
        toggle.target = self
        toggle.state = showOnDesktop ? .on : .off
        menu.addItem(toggle)

        let posItem = NSMenuItem(title: "Desktop Position", action: nil, keyEquivalent: "")
        let posMenu = NSMenu()
        for (key, name) in [("topLeft", "Top Left"), ("topRight", "Top Right"), ("center", "Center"),
                            ("bottomLeft", "Bottom Left"), ("bottomRight", "Bottom Right")] {
            let item = NSMenuItem(title: name, action: #selector(setCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = corner == key ? .on : .off
            posMenu.addItem(item)
        }
        posItem.submenu = posMenu
        menu.addItem(posItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func toggleDesktop() {
        showOnDesktop.toggle()
        refresh()
    }

    @objc func setCorner(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String { corner = key }
        positionDesktopWindow()
        refresh()
    }

    @objc func setGoal() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set your goal"
        alert.informativeText = "Give it a short name and pick the date."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 170, width: 260, height: 24))
        nameField.stringValue = goalTitle
        nameField.placeholderString = "e.g. Marathon"

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 160))
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = goalDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())!

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 198))
        container.addSubview(nameField)
        container.addSubview(picker)
        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        if alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            goalTitle = name.isEmpty ? "Goal" : name
            goalDate = picker.dateValue
            refresh()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
SWIFT

echo "Building..."
swiftc -O "$BUILD_DIR/main.swift" -o "$BUILD_DIR/$APP_NAME"

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>local.goalcountdown</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

# Start automatically at login
osascript -e "tell application \"System Events\" to delete (every login item whose name is \"$APP_NAME\")" >/dev/null 2>&1 || true
osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_DIR\", hidden:true}" >/dev/null 2>&1 \
  && echo "Added to Login Items (starts when you log in)." \
  || echo "Couldn't add to Login Items automatically — add it in System Settings > General > Login Items."

open "$APP_DIR"
echo "Done! Your countdown is on the desktop and in the menu bar."
