import SwiftUI
import UniformTypeIdentifiers

@main
struct KeystrokeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // Removed SettingsWindow reference
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Settings") {
                    // Implement action for Settings button if needed
                }
            }
        }
    }
}

class HistoryEntry: Encodable, Decodable {
    var keystrokesCount: Int;
    var mouseClicksCount: Int;
    
    init(keystrokesCount: Int, mouseClicksCount: Int) {
        self.keystrokesCount = keystrokesCount;
        self.mouseClicksCount = mouseClicksCount;
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var activity: NSObjectProtocol?
    var mainWindow: NSWindow!
    static private(set) var instance: AppDelegate!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    let historyDataFileName = "keycount_history.json"
    
    var currentDate: String;
    
    @Published var keystrokeCount: Int 
    @Published var mouseclickCount: Int

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let historyQueue = DispatchQueue(label: "com.keycount.history", qos: .utility)
    var menu: ApplicationMenu!
    private let popover = NSPopover()
    private var exportWindow: NSWindow?
    private var popoverMonitor: Any?
    private var exportWindowMonitor: Any?

    override init() {
        self.keystrokeCount = 0;
        self.mouseclickCount = 0;
        self.currentDate = "";
        
        super.init()

        // get current date
        self.currentDate = getCurrentDate();
        
        // load entry data from current date if exists
        let todayEntry = getTodayEntry();
        self.keystrokeCount = todayEntry.keystrokesCount;
        self.mouseclickCount = todayEntry.mouseClicksCount;
    }
    
    func getTodayEntry() -> HistoryEntry {
        let history = readHistoryJson();
        let currentDateKey: String = getCurrentDate()
        
        if (history[currentDateKey] != nil) {
            return history[currentDateKey]!;
        } else {
            return HistoryEntry(keystrokesCount: 0, mouseClicksCount: 0);
        }
    }

    func getCurrentDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    

    func getHistoryFilePath() -> String {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolderName = Bundle.main.bundleIdentifier ?? "KeyCount"
        let appSupportFolder = appSupportDirectory.appendingPathComponent(appFolderName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: appSupportFolder, withIntermediateDirectories: true)
        } catch {
            print("Failed to create Application Support folder: \(error)")
        }
        
        return appSupportFolder.appendingPathComponent(historyDataFileName).path
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent running as root for security
        if getuid() == 0 {
            let alert = NSAlert()
            alert.messageText = "Security Warning"
            alert.informativeText = "This application should not be run as root. Please run as a normal user."
            alert.alertStyle = .critical
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        // Disable App Nap
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Application counts user input data in the background")
        
        // Create a status item and set its properties
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let fontSize: CGFloat = 14.0
            let font = NSFont.systemFont(ofSize: fontSize)
            button.font = font
            updateDisplayCounter()
            updateHistoryJson()
        }

        // Create the main window but don't show it
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        mainWindow.title = "RSICounter"
        
        // Initialize ApplicationMenu only once
        menu = ApplicationMenu(mainWindow: mainWindow, appDelegate: self)

        // Create the menu
        menu.buildMenu()

        statusItem.menu = nil
        setupPopover()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Request Input Monitoring permissions
        requestInputMonitoringPermission()

        // Register for key and mouse events using CGEvent tap
        setupEventTap()
    }

    func setupPopover() {
        popover.behavior = .semitransient
        let maxWidth: CGFloat = 160
        let rootView = HistoryPopoverView(appDelegate: self).frame(width: maxWidth)
        let controller = NSHostingController(rootView: rootView)
        popover.contentViewController = controller
        controller.view.setFrameSize(NSSize(width: maxWidth, height: 1))
        controller.view.layoutSubtreeIfNeeded()
        let targetHeight = controller.view.fittingSize.height
        popover.contentSize = NSSize(width: maxWidth, height: targetHeight)
    }

    func showExportWindow(jsonString: String) {
        let exportView = ExportJsonView(jsonString: jsonString, onClose: { [weak self] in
            self?.exportWindow?.close()
            self?.exportWindow = nil
            if let monitor = self?.exportWindowMonitor {
                NSEvent.removeMonitor(monitor)
                self?.exportWindowMonitor = nil
            }
        })
        
        let hostingController = NSHostingController(rootView: exportView)
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Export History"
        window.contentViewController = hostingController
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // Remove old monitor if exists
        if let monitor = exportWindowMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Close on outside click by monitoring click events
        exportWindowMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak window] event in
            if let window = window, window.isVisible {
                let windowFrame = window.frame
                let clickLocation = NSEvent.mouseLocation
                if !windowFrame.contains(clickLocation) {
                    window.close()
                    if let monitor = self?.exportWindowMonitor {
                        NSEvent.removeMonitor(monitor)
                        self?.exportWindowMonitor = nil
                    }
                }
            }
            return event
        }
        
        exportWindow = window
    }

    @objc func handleStatusItemClick() {
        guard let button = statusItem.button else { return }
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.type == .rightMouseDown {
            menu.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startMonitoringPopoverClicks()
        }
    }

    func startMonitoringPopoverClicks() {
        popoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            guard self.popover.isShown else { return }
            
            // Don't close if clicking in export window
            if let exportWindow = self.exportWindow, exportWindow.isVisible {
                let clickLocation = NSEvent.mouseLocation
                if exportWindow.frame.contains(clickLocation) {
                    return
                }
            }
            
            // Check if click is outside popover
            if let popoverWindow = self.popover.contentViewController?.view.window {
                let clickLocation = NSEvent.mouseLocation
                if !popoverWindow.frame.contains(clickLocation) {
                    self.closePopover()
                }
            }
        }
    }

    func closePopover() {
        popover.performClose(nil)
        if let monitor = popoverMonitor {
            NSEvent.removeMonitor(monitor)
            popoverMonitor = nil
        }
    }
    
    func formatCount(_ count: Int) -> String {
        let rounded = Double(count / 100) / 10.0
        return String(format: "%.1f", rounded)
    }
    
    func updateDisplayCounter() {
        if let button = statusItem.button {
            let keystrokeDisplay = formatCount(keystrokeCount)
            let mouseclickDisplay = formatCount(mouseclickCount)
            let displayString = "\(keystrokeDisplay)K \(mouseclickDisplay)M"

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 1.0
                button.attributedTitle = NSAttributedString(
                    string: displayString,
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }

            // Let the system automatically size based on content
            statusItem.length = NSStatusItem.variableLength
        }
    }
    
    func updateHistoryJson() {
        var history = readHistoryJson();
        
        let currentDateKey = getCurrentDate();

        // create today's entry
        let todayEntry = HistoryEntry(keystrokesCount: keystrokeCount, mouseClicksCount: mouseclickCount);

        // add entry
        history[currentDateKey] = todayEntry;
        
        // save new history
        saveHistoryJson(data: history);
    }
    
    func saveHistoryJson(data: [String: HistoryEntry]) {
        historyQueue.async {
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.prettyPrinted]
            
            do {
                let dataJson = try jsonEncoder.encode(data)
                let fileURL = URL(fileURLWithPath: self.getHistoryFilePath())
                try dataJson.write(to: fileURL, options: .atomic)
            } catch {
                print("Failed to save history: \(error.localizedDescription)")
                print("Path: \(self.getHistoryFilePath())")
                // App continues to function with in-memory counts even if file save fails
            }
        }
    }
    
    func readHistoryJson() -> [String: HistoryEntry] {
        return historyQueue.sync {
            let jsonDecoder = JSONDecoder()
            let filePath = getHistoryFilePath()

            if !FileManager.default.fileExists(atPath: filePath) {
                return [:]
            }
            
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let history = try jsonDecoder.decode([String: HistoryEntry].self, from: data)
                return history
            } catch {
                print("Failed to read history: \(error.localizedDescription)")
                print("Path: \(filePath)")
                
                // If file is corrupted, attempt to rename it and start fresh
                do {
                    let corruptedPath = filePath + ".corrupted.\(Date().timeIntervalSince1970)"
                    try FileManager.default.moveItem(atPath: filePath, toPath: corruptedPath)
                    print("Moved corrupted file to: \(corruptedPath)")
                } catch {
                    print("Failed to move corrupted file: \(error.localizedDescription)")
                }
                
                // Return empty dictionary - app will start fresh
                return [:]
            }
        }
    }

    func requestInputMonitoringPermission() {
        // Check if Input Monitoring permission has been granted
        let hasPermission = CGPreflightListenEventAccess()
        
        if hasPermission {
            print("Input Monitoring permission has been granted")
        } else {
            print("Input Monitoring permission has NOT been granted")
            let requested = CGRequestListenEventAccess()
            print("Input Monitoring permission request issued: \(requested)")
            print("The system will automatically prompt for Input Monitoring permission")
            print("If prompted, grant access in System Settings → Privacy & Security → Input Monitoring")
        }
    }
    
    func ensureTodayCounters() {
        let date = getCurrentDate()
        
        if (self.currentDate != date) {
            // Save yesterday's counts before switching to new day
            updateHistoryJson()
            
            self.currentDate = date
            
            let entry = getTodayEntry()
            self.keystrokeCount = entry.keystrokesCount
            self.mouseclickCount = entry.mouseClicksCount
            
            updateDisplayCounter()
        }
    }

    func handleKeyEvent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureTodayCounters()
            self.keystrokeCount += 1
            
            self.updateDisplayCounter()
            
            // Save to file every 50 events
            let totalCount = self.keystrokeCount + self.mouseclickCount
            if totalCount % 50 == 0 {
                self.updateHistoryJsonAsync()
            }
        }
    }
    
    func handleMouseEvent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureTodayCounters()
            self.mouseclickCount += 1
            
            self.updateDisplayCounter()
            
            // Save to file every 50 events
            let totalCount = self.keystrokeCount + self.mouseclickCount
            if totalCount % 50 == 0 {
                self.updateHistoryJsonAsync()
            }
        }
    }
    
    func updateHistoryJsonAsync() {
        let keystrokes = keystrokeCount
        let mouseClicks = mouseclickCount
        let currentDateKey = getCurrentDate()
        var history = self.readHistoryJson()
        history[currentDateKey] = HistoryEntry(keystrokesCount: keystrokes, mouseClicksCount: mouseClicks)
        self.saveHistoryJson(data: history)
    }
    
    func setupEventTap() {
        if eventTap != nil {
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                       (1 << CGEventType.leftMouseDown.rawValue) |
                       (1 << CGEventType.rightMouseDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                
                switch type {
                case .keyDown:
                    // Filter out key repeats
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    if !isRepeat {
                        appDelegate.handleKeyEvent()
                    }
                case .leftMouseDown, .rightMouseDown:
                    appDelegate.handleMouseEvent()
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    appDelegate.reenableEventTap()
                default:
                    break
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.setupEventTap()
            }
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.eventTap = tap
        self.runLoopSource = runLoopSource
    }

    func reenableEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    @objc func terminateApp() {
        // Save current counts before terminating
        updateHistoryJson()
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let monitor = popoverMonitor {
            NSEvent.removeMonitor(monitor)
            popoverMonitor = nil
        }
        if let monitor = exportWindowMonitor {
            NSEvent.removeMonitor(monitor)
            exportWindowMonitor = nil
        }
        if let activity = activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        NSApplication.shared.terminate(self)
    }
}

class ApplicationMenu: ObservableObject {
    var appDelegate: AppDelegate
    var menu: NSMenu!
    var mainWindow: NSWindow?
    var settingsWindow: NSWindow?

    init(mainWindow: NSWindow?, appDelegate: AppDelegate) {
        self.mainWindow = mainWindow
        self.appDelegate = appDelegate
        buildMenu()
    }

    func buildMenu() {
        menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(terminateApp), keyEquivalent: "q")
    }
    
    @objc func terminateApp() {
        appDelegate.terminateApp()
    }

    @objc func toggleMenu() {
        if let button = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength).button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }
}

struct HistoryPopoverView: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var selectedDate = Date()
    @State private var keystrokes = 0
    @State private var mouseClicks = 0

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Counter")
                .font(.headline)
            GraphicalDatePicker(selection: $selectedDate)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Keystrokes")
                    Spacer()
                    Text("\(keystrokes)")
                        .monospacedDigit()
                }
                HStack {
                    Text("Mouse clicks")
                    Spacer()
                    Text("\(mouseClicks)")
                        .monospacedDigit()
                }
            }
            HStack(spacing: 8) {
                Button("Export") {
                    exportSelectedDate()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Text(privacyDisclaimerText())
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .allowsTightening(true)
            Text(generalDisclaimerText())
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .allowsTightening(true)
            Text(appVersionText())
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
        .padding(12)
        .onAppear { loadCounts(for: selectedDate) }
        .onChange(of: selectedDate) { newDate in
            loadCounts(for: newDate)
        }
        .onChange(of: appDelegate.keystrokeCount) { newCount in
            if isToday(selectedDate) {
                keystrokes = newCount
            }
        }
        .onChange(of: appDelegate.mouseclickCount) { newCount in
            if isToday(selectedDate) {
                mouseClicks = newCount
            }
        }
    }

    private func loadCounts(for date: Date) {
        let key = dateFormatter.string(from: date)
        let history = appDelegate.readHistoryJson()
        if let entry = history[key] {
            keystrokes = entry.keystrokesCount
            mouseClicks = entry.mouseClicksCount
        } else {
            keystrokes = 0
            mouseClicks = 0
        }
    }

    private func isToday(_ date: Date) -> Bool {
        let today = dateFormatter.string(from: Date())
        let selected = dateFormatter.string(from: date)
        return today == selected
    }

    private func exportSelectedDate() {
        let history = appDelegate.readHistoryJson()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonString: String
        do {
            let data = try encoder.encode(history)
            jsonString = String(data: data, encoding: .utf8) ?? "Error encoding JSON"
        } catch {
            jsonString = "Error: \(error.localizedDescription)"
        }
        appDelegate.showExportWindow(jsonString: jsonString)
    }

    private func appVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (Build \(build))"
    }

    private func privacyDisclaimerText() -> String {
        return "This app only stores local counts of keystrokes and mouse clicks. It does not record which keys are pressed and does not collect or transmit any data. The code is open source for transparency."
    }

    private func generalDisclaimerText() -> String {
        return "This app provides informational activity metrics only. It is not a medical device and should not be used for diagnosis or treatment. Consult a qualified healthcare professional for medical concerns."
    }
}

struct ExportJsonView: View {
    let jsonString: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Export History")
                .font(.headline)
            ScrollView {
                Text(jsonString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 200, maxHeight: 300)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            HStack(spacing: 12) {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonString, forType: .string)
                }
                Button("Close") {
                    onClose()
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct GraphicalDatePicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.isBordered = false
        picker.focusRingType = .none
        picker.drawsBackground = false
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        nsView.dateValue = selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        @Binding var selection: Date

        init(selection: Binding<Date>) {
            _selection = selection
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            selection = sender.dateValue
        }
    }
}
