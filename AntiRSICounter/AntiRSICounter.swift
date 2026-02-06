import SwiftUI

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
    
    // Store history data in a map
    let historyData: [String: HistoryEntry] = [:]
    let historyDataFileName = "keycount_history.json"
    
    var currentDate: String;
    
    @Published var keystrokeCount: Int 
    @Published var mouseclickCount: Int

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let historyQueue = DispatchQueue(label: "com.keycount.history", qos: .utility)
    var menu: ApplicationMenu!

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
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(historyDataFileName).path
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

        statusItem.menu = menu.menu
        statusItem.button?.action = #selector(menu.toggleMenu)

        // Request Input Monitoring permissions
        requestInputMonitoringPermission()

        // Register for key and mouse events using CGEvent tap
        setupEventTap()
    }
    
    func formatCount(_ count: Int) -> String {
        return String(count)
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
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted]
        
        do {
            let dataJson = try jsonEncoder.encode(data)
            let fileURL = URL(fileURLWithPath: getHistoryFilePath())
            try dataJson.write(to: fileURL)
        } catch let error {
            print(error);
        }
    }
    
    func readHistoryJson() -> [String: HistoryEntry] {
        let jsonDecoder = JSONDecoder();
        let filePath = getHistoryFilePath()

        if !FileManager.default.fileExists(atPath: filePath) {
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let history = try jsonDecoder.decode([String: HistoryEntry].self, from: data)
            return history;
        } catch let error {
            print(error);
        }
        
        return [:];
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
        historyQueue.async { [weak self] in
            guard let self = self else { return }
            var history = self.readHistoryJson()
            history[currentDateKey] = HistoryEntry(keystrokesCount: keystrokes, mouseClicksCount: mouseClicks)
            self.saveHistoryJson(data: history)
        }
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
        NSApplication.shared.terminate(self)
    }

    @objc func toggleMenu() {
        if let button = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength).button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }
}
