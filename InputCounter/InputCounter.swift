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
        popover.behavior = .transient
        let maxWidth: CGFloat = 160
        let rootView = HistoryPopoverView(appDelegate: self).frame(width: maxWidth)
        let controller = NSHostingController(rootView: rootView)
        popover.contentViewController = controller
        controller.view.setFrameSize(NSSize(width: maxWidth, height: 1))
        controller.view.layoutSubtreeIfNeeded()
        let targetHeight = controller.view.fittingSize.height
        popover.contentSize = NSSize(width: maxWidth, height: targetHeight)
    }

    @objc func handleStatusItemClick() {
        guard let button = statusItem.button else { return }
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.type == .rightMouseDown {
            menu.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
                try dataJson.write(to: fileURL)
            } catch let error {
                print(error)
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
            } catch let error {
                print(error)
            }
            
            return [:]
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
            self.currentDate = date;
            
            let entry = getTodayEntry();
            self.keystrokeCount = entry.keystrokesCount;
            self.mouseclickCount = entry.mouseClicksCount;
        }
    }

    func handleKeyEvent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureTodayCounters()
            self.keystrokeCount += 1
            
            self.updateDisplayCounter()
            self.updateHistoryJsonAsync()
        }
    }
    
    func handleMouseEvent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureTodayCounters()
            self.mouseclickCount += 1
            
            self.updateDisplayCounter()
            self.updateHistoryJsonAsync()
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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
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
    @State private var showExportSheet = false
    @State private var exportJson = ""

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
        .sheet(isPresented: $showExportSheet) {
            ExportJsonView(jsonString: exportJson, isPresented: $showExportSheet)
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
        do {
            let data = try encoder.encode(history)
            exportJson = String(data: data, encoding: .utf8) ?? "Error encoding JSON"
        } catch {
            exportJson = "Error: \(error.localizedDescription)"
        }
        showExportSheet = true
    }

    private func appVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (Build \(build))"
    }

    private func privacyDisclaimerText() -> String {
        return "This app only keeps keystroke and mouse click counters locally. It does not know which keys are pressed. No data is collected or transmitted through the network. The code is open source and can be reviewed by anyone for transparency."
    }

    private func generalDisclaimerText() -> String {
        return "This app provides activity metrics for informational purposes only. It is not a medical device and should not be used for medical diagnosis or treatment. Always consult with a qualified healthcare professional for any medical concerns."
    }
}

struct ExportJsonView: View {
    let jsonString: String
    @Binding var isPresented: Bool

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
                    isPresented = false
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
