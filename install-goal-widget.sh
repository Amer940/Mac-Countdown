#!/bin/bash
# Goal Countdown — one app: a real macOS desktop widget + a menu bar countdown.
# Set your goal on the widget (right-click → Edit "Goal Countdown"); the menu bar follows it.
# Needs: macOS 14 (Sonoma) or later, and Xcode (free, from the Mac App Store).
# Run:  bash install-goal-widget.sh
set -e

SRC="$HOME/GoalWidget"          # source is kept here so you can open it in Xcode later
APP_NAME="GoalWidget"

# ---------- Checks ----------
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ Xcode is needed to build a real widget."
  echo "   1. Install Xcode from the Mac App Store (free)."
  echo "   2. Open it once and let it finish installing components."
  echo "   3. Run:  sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept"
  echo "   Then run this script again."
  open "macappstore://apps.apple.com/app/xcode/id497799835" 2>/dev/null || true
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen (project generator)..."
    brew install xcodegen
  else
    echo "❌ Homebrew is needed to install XcodeGen. Install it from https://brew.sh, then run this again."
    exit 1
  fi
fi

rm -rf "$SRC/App" "$SRC/Widget" "$SRC/Shared"
mkdir -p "$SRC/App" "$SRC/Widget" "$SRC/Shared"
cd "$SRC"

# ---------- Project definition ----------
cat > project.yml <<'EOF'
name: GoalWidget
options:
  bundleIdPrefix: com.local
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
    MARKETING_VERSION: "1.1"
    CURRENT_PROJECT_VERSION: "3"
    SWIFT_VERSION: "5.0"
targets:
  GoalWidget:
    type: application
    platform: macOS
    sources: [App, Shared]
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Goal Countdown
        LSApplicationCategoryType: public.app-category.productivity
        LSUIElement: true
    entitlements:
      path: App/App.entitlements
      properties:
        com.apple.security.app-sandbox: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.local.goalwidget
    dependencies:
      - target: GoalWidgetExtension
  GoalWidgetExtension:
    type: app-extension
    platform: macOS
    sources: [Widget, Shared]
    info:
      path: Widget/Info.plist
      properties:
        CFBundleDisplayName: Goal Countdown
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Widget/Widget.entitlements
      properties:
        com.apple.security.app-sandbox: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.local.goalwidget.widget
EOF

# ---------- Shared: the goal settings (used by both widget and menu bar) ----------
cat > Shared/GoalShared.swift <<'EOF'
import Foundation
import AppIntents
import WidgetKit

let goalWidgetKind = "GoalCountdown"

// Settings you edit by right-clicking the widget → Edit "Goal Countdown"
struct GoalConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Goal"
    static var description = IntentDescription("Name your goal and pick its date.")

    @Parameter(title: "Goal name", default: "My Goal")
    var name: String

    @Parameter(title: "Day", default: 1)
    var day: Int

    @Parameter(title: "Month (1-12)", default: 1)
    var month: Int

    @Parameter(title: "Year", default: 2027)
    var year: Int

    var goalDate: Date? {
        let cal = Calendar.current
        let m = min(max(month, 1), 12)
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: m, day: 1)),
              let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
        let safeDay = min(max(day, 1), daysInMonth.count)
        return cal.date(from: DateComponents(year: year, month: m, day: safeDay))
    }
}

func daysUntil(_ goal: Date, from now: Date = .now) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: goal)).day ?? 0
}
EOF

# ---------- The app: lives in the menu bar, mirrors the widget ----------
cat > App/GoalWidgetApp.swift <<'EOF'
import SwiftUI
import WidgetKit
import ServiceManagement

@main
struct GoalWidgetApp: App {
    @StateObject private var store = GoalStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Text(store.label)
        }
    }
}

@MainActor
final class GoalStore: ObservableObject {
    @Published var name: String?
    @Published var goal: Date?
    @Published var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var timer: Timer?

    init() {
        // Turn on "launch at login" the first time the app runs
        if !UserDefaults.standard.bool(forKey: "didSetupLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // Read the goal straight from the widget on your desktop
    func refresh() {
        now = Date()
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            var config: GoalConfig?
            if case .success(let infos) = result,
               let info = infos.first(where: { $0.kind == goalWidgetKind }) {
                config = info.widgetConfigurationIntent(of: GoalConfig.self)
            }
            let name = config?.name
            let goal = config?.goalDate
            Task { @MainActor in
                self?.name = name
                self?.goal = goal
            }
        }
    }

    var days: Int? { goal.map { daysUntil($0, from: now) } }

    var label: String {
        guard let d = days else { return "🎯 Add widget" }
        let n = name ?? "Goal"
        if d > 0 { return "🎯 \(n) · \(d)d" }
        if d == 0 { return "🎯 \(n) · TODAY" }
        return "✅ \(n) · \(-d)d ago"
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct MenuContent: View {
    @ObservedObject var store: GoalStore

    var body: some View {
        Group {
            if let goal = store.goal, let d = store.days {
                Text("\(store.name ?? "Goal") — \(goal.formatted(date: .long, time: .omitted))")
                if d > 0 { Text("\(d / 7) weeks, \(d % 7) days to go") }
            } else {
                Text("No Goal Countdown widget on your desktop yet")
            }
            Divider()
            Button("How to Change the Goal…") { showHelp() }
            Button("Refresh") { store.refresh() }
            Toggle("Launch at Login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { _ in store.toggleLaunchAtLogin() }))
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear { store.refresh() }
    }

    func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set your goal from the widget"
        alert.informativeText = """
        1. Right-click the desktop → Edit Widgets… and add "Goal Countdown" (if it isn't there yet).
        2. Right-click the widget → Edit "Goal Countdown".
        3. Set the name, day, month and year.

        The menu bar picks up the change within a few seconds.
        """
        alert.runModal()
    }
}
EOF

# ---------- The widget ----------
cat > Widget/GoalWidget.swift <<'EOF'
import WidgetKit
import SwiftUI
import AppIntents

struct GoalEntry: TimelineEntry {
    let date: Date
    let name: String
    let goal: Date?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GoalEntry {
        GoalEntry(date: .now, name: "My Goal",
                  goal: Calendar.current.date(byAdding: .day, value: 42, to: .now))
    }

    func snapshot(for configuration: GoalConfig, in context: Context) async -> GoalEntry {
        GoalEntry(date: .now, name: configuration.name,
                  goal: configuration.goalDate ?? placeholder(in: context).goal)
    }

    // One entry now, then one at each midnight for the next 30 days
    func timeline(for configuration: GoalConfig, in context: Context) async -> Timeline<GoalEntry> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let goal = configuration.goalDate
        var entries = [GoalEntry(date: .now, name: configuration.name, goal: goal)]
        for i in 1...30 {
            if let d = cal.date(byAdding: .day, value: i, to: today) {
                entries.append(GoalEntry(date: d, name: configuration.name, goal: goal))
            }
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct GoalWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: GoalEntry

    var days: Int? { entry.goal.map { daysUntil($0, from: entry.date) } }

    var numberText: String {
        guard let d = days else { return "–" }
        return d == 0 ? "🎉" : "\(abs(d))"
    }

    var unitText: String {
        guard let d = days else { return "Right-click → Edit to set a date" }
        if d == 0 { return "It's today!" }
        if d == 1 { return "day to go" }
        if d > 1 { return "days to go" }
        if d == -1 { return "day since" }
        return "days since"
    }

    var dateText: String {
        entry.goal?.formatted(date: .abbreviated, time: .omitted) ?? ""
    }

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        // Follows your Mac's Light/Dark appearance and the desktop widget style
        .containerBackground(.background, for: .widget)
    }

    var small: some View {
        VStack(spacing: 2) {
            Text("🎯 \(entry.name)")
                .font(.headline).lineLimit(1)
            Text(numberText)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .widgetAccentable()
            Text(unitText)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(dateText)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                Text(numberText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .widgetAccentable()
                Text(unitText).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("🎯 \(entry.name)").font(.title3.bold()).lineLimit(2)
                Text(dateText).font(.subheadline).foregroundStyle(.secondary)
                if let d = days, d > 0 {
                    Text("\(d / 7) weeks, \(d % 7) days").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct GoalWidgetBundle: WidgetBundle {
    var body: some Widget { GoalCountdownWidget() }
}

struct GoalCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: goalWidgetKind, intent: GoalConfig.self, provider: Provider()) { entry in
            GoalWidgetView(entry: entry)
        }
        .configurationDisplayName("Goal Countdown")
        .description("Days left until your goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
EOF

# ---------- Build & install ----------
echo "Generating Xcode project..."
xcodegen generate --quiet

echo "Building (takes a minute the first time)..."
xcodebuild -project GoalWidget.xcodeproj -scheme GoalWidget -configuration Release \
  -derivedDataPath build -quiet build

# Replace the older separate menu bar app, if it's installed
pkill -x GoalCountdown 2>/dev/null || true
osascript -e 'tell application "System Events" to delete (every login item whose name is "GoalCountdown")' >/dev/null 2>&1 || true
rm -rf "$HOME/Applications/GoalCountdown.app"

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "build/Build/Products/Release/$APP_NAME.app" /Applications/

# Make macOS pick up the new widget version
killall chronod 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true

open "/Applications/$APP_NAME.app"
echo ""
echo "✅ Done! Goal Countdown is now one app: widget + menu bar."
echo "   Add the widget: right-click desktop → Edit Widgets… → \"Goal Countdown\"."
echo "   Set your goal: right-click the widget → Edit \"Goal Countdown\". The menu bar follows it."
