import SwiftUI
import ApplicationServices

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

    private var keyEventTap: CFMachPort?
    private var mouseEventTap: CFMachPort?
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
        dateFormatter.dateFormat = "dd-MM-yyyy"
        return dateFormatter.string(from: Date())
    }
    

    func getHistoryDataFilePath() -> String {
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

        // Request accessibility permissions
        requestAccessibilityPermission()

        // Register for key events using event tap
        setupKeyUpEventTap()
        
        // Register for mouse click events using event tap
        setupMouseClickEventTap()
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
            
            button.title = displayString

            // Calculate the minimum width based on the number of digits
            var minWidth: CGFloat = 150.0
            let digitCount = keystrokeDisplay.count

            if digitCount >= 4 {
                minWidth += CGFloat(digitCount - 4) * 10.0
            }

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 1.0
                button.attributedTitle = NSAttributedString(
                    string: displayString,
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }

            // Set the minimum width
            statusItem.length = minWidth
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
            let fileURL = URL(fileURLWithPath: getHistoryDataFilePath())
            try dataJson.write(to: fileURL)
        } catch let error {
            print(error);
        }
    }
    
    func readHistoryJson() -> [String: HistoryEntry] {
        let jsonDecoder = JSONDecoder();
        let filePath = getHistoryDataFilePath()

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

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            print("Please enable accessibility permissions for the app.")
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

    func handleKeyDownEvent(_ event: CGEvent) {
        // Filter out key repeats (when key is held down)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return
        }
        
        ensureTodayCounters();
        keystrokeCount += 1;
        
        // Only update display every 100 keystrokes
        if keystrokeCount % 100 == 0 {
            updateDisplayCounter()
            updateHistoryJson()
        }
    }
    
    func handleMouseDownEvent(_ event: CGEvent) {
        ensureTodayCounters();
        mouseclickCount += 1
        
        // Only update display every 10 mouse clicks
        if mouseclickCount % 10 == 0 {
            updateDisplayCounter()
            updateHistoryJson()
        }
    }
    
    func setupKeyUpEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyUp.rawValue)
        let mask = CGEventMask(eventMask);

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        keyEventTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return nil
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                appDelegate.handleKeyDownEvent(event)

                return Unmanaged.passRetained(event)
            },
            userInfo: selfPointer
        )

        if let keyEventTap = keyEventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyEventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: keyEventTap, enable: true)
        }
    }
    
    func setupMouseClickEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        let mask = CGEventMask(eventMask);

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        mouseEventTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return nil
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                appDelegate.handleMouseDownEvent(event)

                return Unmanaged.passRetained(event)
            },
            userInfo: selfPointer
        )

        if let mouseEventTap = mouseEventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseEventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: mouseEventTap, enable: true)
        }
    }

    @objc func terminateApp() {
        if let keyEventTap = keyEventTap {
            CGEvent.tapEnable(tap: keyEventTap, enable: false)
        }
        if let mouseEventTap = mouseEventTap {
            CGEvent.tapEnable(tap: mouseEventTap, enable: false)
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
