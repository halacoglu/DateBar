import SwiftUI
import AppKit

// MARK: - Constants

private let appName: String =
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "DateBar"
private let appVersion: String =
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"

// All panel measurements live here. The panel height is computed from the
// content, so there is no leftover space and the outer padding is the same
// on all four sides.
private enum Layout {
    static let padding: CGFloat = 16
    static let width: CGFloat = 300
    static let headerHeight: CGFloat = 22
    static let weekdayHeight: CGFloat = 16
    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 4
    static let sectionSpacing: CGFloat = 12
    static let gridHeight: CGFloat = rowHeight * 6 + rowSpacing * 5
    static let contentHeight: CGFloat = headerHeight + weekdayHeight + gridHeight + sectionSpacing * 2
}

private let panelSize = CGSize(width: Layout.width,
                               height: Layout.contentHeight + Layout.padding * 2)

// MARK: - State

enum Page {
    case calendar, settings, about
}

@MainActor
final class AppState: ObservableObject {
    @Published var page: Page = .calendar
    @Published var displayedMonth: Date = AppState.startOfCurrentMonth()
    @Published var today: Date = Date()
    @Published var isPinned: Bool {
        didSet { UserDefaults.standard.set(isPinned, forKey: "keepFloating") }
    }

    init() {
        isPinned = UserDefaults.standard.bool(forKey: "keepFloating")
    }

    static func startOfCurrentMonth() -> Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    func shiftMonth(by value: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = d
        }
    }

    func goToCurrentMonth() {
        displayedMonth = AppState.startOfCurrentMonth()
    }
}

// MARK: - Views

struct RootView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            switch state.page {
            case .calendar: CalendarView(state: state)
            case .settings: SettingsView(state: state)
            case .about:    AboutView(state: state)
            }
        }
        .padding(Layout.padding)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
    }
}

struct CalendarView: View {
    @ObservedObject var state: AppState
    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            header
                .frame(height: Layout.headerHeight)
            weekdayRow
                .frame(height: Layout.weekdayHeight)
            LazyVGrid(columns: columns, spacing: Layout.rowSpacing) {
                ForEach(cells, id: \.date) { cell in
                    dayCell(cell)
                }
            }
            .frame(height: Layout.gridHeight, alignment: .top)
        }
    }

    // Header: nav buttons (left), month title (center), menu (right)
    private var header: some View {
        ZStack {
            Text(state.displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)

            HStack(spacing: 0) {
                navButton("chevron.left", help: "Previous month") { state.shiftMonth(by: -1) }
                navButton("circle", help: "Current month") { state.goToCurrentMonth() }
                navButton("chevron.right", help: "Next month") { state.shiftMonth(by: 1) }
                Spacer()
                Menu {
                    Button("Settings") { state.page = .settings }
                    Button("About") { state.page = .about }
                    Divider()
                    Button("Quit") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gear")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private func navButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private struct DayCell {
        let date: Date
        let inMonth: Bool
    }

    // Always 6 weeks (42 days) so every month has the same height.
    // The rows not used by the month are split evenly above and below it,
    // keeping the current month vertically centered (with an odd number of
    // spare rows, the extra one goes below). Days outside the month are faded.
    private var cells: [DayCell] {
        let first = state.displayedMonth
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = cal.component(.weekday, from: first)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        let monthRows = (offset + daysInMonth + 6) / 7
        let rowsAbove = (6 - monthRows) / 2
        let leading = offset + rowsAbove * 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0..<42).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            return DayCell(date: d, inMonth: cal.isDate(d, equalTo: first, toGranularity: .month))
        }
    }

    private func dayCell(_ cell: DayCell) -> some View {
        let isToday = cal.isDate(cell.date, inSameDayAs: state.today)
        let color: Color = isToday ? .white : (cell.inMonth ? .primary : Color.secondary.opacity(0.45))
        return ZStack {
            if isToday {
                Circle().fill(Color.accentColor)
            }
            Text("\(cal.component(.day, from: cell.date))")
                .monospacedDigit()
                .foregroundColor(color)
                .fontWeight(isToday ? .semibold : .regular)
        }
        .frame(height: Layout.rowHeight)
    }
}

struct SubPageHeader: View {
    let title: String
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            Text(title).font(.headline)
            HStack {
                Button {
                    state.page = .calendar
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Back to calendar")
                Spacer()
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubPageHeader(title: "Settings", state: state)
            Divider()
            Toggle("Keep calendar floating on screen", isOn: $state.isPinned)
                .toggleStyle(.switch)
            Spacer()
        }
    }
}

struct AboutView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            SubPageHeader(title: "About", state: state)
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text(appName)
                .font(.title2).bold()
            Text("Version \(appVersion)")
                .foregroundColor(.secondary)
            Spacer()
            Text("Made with 🍫 and ❤️ by")
                .font(.system(size: 14))
            Text("Osman Halaçoğlu")
                .font(.title2).bold()
            Link("github.com/halacoglu",
                destination: URL(string: "https://github.com/halacoglu")!)
            Spacer()
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let state = AppState()
    private var contextMenu: NSMenu!
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusImage()

        // Popover
        let hosting = NSHostingController(rootView: RootView(state: state))
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: panelSize.width, height: panelSize.height)
        popover.animates = true
        // The popover never closes by itself. "Close when clicking elsewhere"
        // is handled explicitly below, so it can be switched off by the
        // floating setting at any time.
        popover.behavior = .applicationDefined
        popover.delegate = self

        // Right-click menu
        contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: ""))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        contextMenu.items.forEach { $0.target = self }

        // Keep the icon's day number up to date.
        NotificationCenter.default.addObserver(
            self, selector: #selector(dayChanged),
            name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(dayChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    // MARK: Status item

    private func updateStatusImage() {
        let text = "\(Calendar.current.component(.day, from: Date()))"
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { rect in
            let box = rect.insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.4
            NSColor.black.setStroke()
            path.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let size = str.size()
            str.draw(at: NSPoint(x: rect.midX - size.width / 2,
                                 y: rect.midY - size.height / 2))
            return true
        }
        image.isTemplate = true // adapts to light/dark menu bar
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("Calendar, day \(text)")
    }

    @objc private func dayChanged() {
        updateStatusImage()
        state.today = Date()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    // MARK: Popover

    // Close the panel when the user clicks outside of it (in another app or
    // on the desktop), unless "keep floating" is on. The setting is read at
    // click time, so toggling it takes effect immediately.
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.state.isPinned else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // Also close when the app loses focus (e.g. Cmd-Tab to another app).
    @objc private func appDidResignActive() {
        if popover.isShown && !state.isPinned {
            popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            state.page = .calendar
            state.goToCurrentMonth()
            state.today = Date()
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startOutsideClickMonitor()
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Menu actions

    @objc private func openSettings() {
        state.page = .settings
        if !popover.isShown { showPopover() }
    }

    @objc private func openAbout() {
        state.page = .about
        if !popover.isShown { showPopover() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

@main
struct DateBarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
