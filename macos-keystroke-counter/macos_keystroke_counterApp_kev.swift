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
    var updateInterval = Int(UserDefaults.standard.string(forKey: "updateInterval") ?? "30") ?? 30
    
    // Variables for maintaining keystroke data
    var keystrokeData: [Int] = []
    var currentTimeIndex: Int = 0
    var endpointURL: String = ""
    
    // Store history data in a map
    let historyData: [String: [HistoryEntry]] = [:]
    let historyDataFileName = "keycount_history.json"
    
    // The number of keystrokes at the beginning of the interval, so that when we send the data we can add the keystrokes from the leystroke data on to this value incrementally
    var keystrokesAtBeginningOfInterval: Int = 0
    
    // how precise the key detection logic is. keystrokeData data will be an array of Integers where each Int represents the number of keystrokes that took place in each period. If updatePrecision = 4, then it will be the number of keystrokes in each 250ms period (4 periods per second)
    var updatePrecision: Int = 20
    
    // keys for UserDefaults data
    let sendingUpdatesEnabledKey = "sendingUpdatesEnabled"
    let updateEndpointURIKey = "updateEndpointURI"
    let updateIntervalKey = "updateInterval"
    
    private var currentDateKey: String {
       let dateFormatter = DateFormatter()
       dateFormatter.dateFormat = "yyyy-MM-dd"
       return dateFormatter.string(from: Date())
    }
    
    @Published var keystrokeCount: Int {
        didSet {
            UserDefaults.standard.set(keystrokeCount, forKey: "keystrokesToday")
        }
    }
   
    @Published var mouseclickCount: Int {
        didSet {
            UserDefaults.standard.set(mouseclickCount, forKey: "mouseclickCount")
        }
    }

    private var eventTap: CFMachPort?
    var menu: ApplicationMenu!

    override init() {
        self.keystrokeCount = UserDefaults.standard.integer(forKey: "keystrokesToday")
        self.keystrokesAtBeginningOfInterval = UserDefaults.standard.integer(forKey: "keystrokesToday")
        self.endpointURL = UserDefaults.standard.string(forKey: updateEndpointURIKey) ?? ""
        self.keystrokeData = Array(repeating: 0, count: updateInterval * updatePrecision)
        self.mouseclickCount = UserDefaults.standard.integer(forKey: "mouseclickCount")
        super.init()
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
            updateCount()
            updateHistoryJson()

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 1.0
                button.attributedTitle = NSAttributedString(
                    string: "\(keystrokeCount) K  -  \(mouseclickCount) M",
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }
        }

        // Create the main window but don't show it
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        mainWindow.title = "Keystroke Counter"
        
        // Initialize ApplicationMenu only once
        menu = ApplicationMenu(mainWindow: mainWindow, appDelegate: self)

        // Create the menu
        menu.buildMenu()

        statusItem.menu = menu.menu
        statusItem.button?.action = #selector(menu.toggleMenu)

        // Request accessibility permissions
        requestAccessibilityPermission()

        // Register for key events using event tap
        setupKeyDownEventTap()
        
        // Register for mouse click events using event tap
        setupMouseClickEventTap()
        
        // If sending updates is enabled start timer to send update data after every interval
        if UserDefaults.standard.bool(forKey: self.sendingUpdatesEnabledKey) {
            setupTimeIndexIncrementer()
        }
    }
    
    func updateCount() {
        if let button = statusItem.button {
            let displayString = "\(keystrokeCount) K  -  \(mouseclickCount) M"
            
            button.title = displayString

            // Calculate the minimum width based on the number of digits
            var minWidth: CGFloat = 110.0
            let digitCount = "\(keystrokeCount)".count

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
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let currentDateKey = dateFormatter.string(from: Date())

        // create today's entry
        let todayEntry = HistoryEntry(keystrokesCount: keystrokeCount, mouseClicksCount: mouseclickCount);

        // add entry
        history[currentDateKey] = [todayEntry];
        
        // save new history
        saveHistoryJson(data: history);
    }
    
    func saveHistoryJson(data: [String: [HistoryEntry]]) {
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
    
    func readHistoryJson() -> [String: [HistoryEntry]] {
        let jsonDecoder = JSONDecoder();
        let filePath = getHistoryDataFilePath()

        if !FileManager.default.fileExists(atPath: filePath) {
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let history = try jsonDecoder.decode([String: [HistoryEntry]].self, from: data)
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

    func handleKeyDownEvent(_ event: CGEvent) {
        keystrokeCount += 1;
        updateCount()
    }
    
    func handleMouseDownEvent(_ event: CGEvent) {
        mouseclickCount += 1
        updateCount()
    }
    
    func setupTimeIndexIncrementer() {
        // Create a timer that calls the incrementTimeIndex method [updatePrecision] times per second
        let timer = Timer.scheduledTimer(timeInterval: 1.0/Double(updatePrecision), target: self, selector: #selector(incrementTimeIndex), userInfo: nil, repeats: true)
        
        // Run the timer on the current run loop
        RunLoop.current.add(timer, forMode: .common)
    }
    
    @objc func incrementTimeIndex() {
        // Increment currentTimeIndex
        currentTimeIndex += 1
        
        // Uncommment print statement for timer increment debugging
        // print("Timestamp: \(Date()) - Current Time Index: \(currentTimeIndex)")
    }
    
    func setupKeyDownEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let mask = CGEventMask(eventMask);

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
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

        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
        }
    }
    
    func setupMouseClickEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        let mask = CGEventMask(eventMask);

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
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

        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
        }
    }
    
//    func setupEventTap(eventMask: CGEventMask, eventHandler: (CGEvent) -> Void) {
//        let mask = CGEventMask(eventMask) | CGEventFlags.maskCommand.rawValue
//
//        let selfPointer = Unmanaged.passUnretained(eventHandler).toOpaque()
//
//        eventTap = CGEvent.tapCreate(
//            tap: .cgAnnotatedSessionEventTap,
//            place: .tailAppendEventTap,
//            options: .listenOnly,
//            eventsOfInterest: mask,
//            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
//                guard let refcon = refcon else {
//                    return nil
//                }
//                
//                // Call the event handler
//                eventHandler(event);
//
//                return Unmanaged.passRetained(event)
//            },
//            userInfo: selfPointer
//        )
//
//        if let eventTap = eventTap {
//            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
//            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
//            CGEvent.tapEnable(tap: eventTap, enable: true)
//            CFRunLoopRun()
//        }
//    }

    @objc func terminateApp() {
        UserDefaults.standard.synchronize()
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
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

        let settingsItem = NSMenuItem(title: "Reset Keystrokes", action: #selector(resetKeystrokes), keyEquivalent: "")
        settingsItem.target = self

        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(terminateApp), keyEquivalent: "q")
    }

    @objc func resetKeystrokes() {
        let confirmResetAlert = NSAlert()
        confirmResetAlert.messageText = "Reset Keystrokes"
        confirmResetAlert.informativeText = "Are you sure you want to reset the keystrokes count?"
        confirmResetAlert.addButton(withTitle: "Reset")
        confirmResetAlert.addButton(withTitle: "Cancel")
        confirmResetAlert.alertStyle = .warning

        let response = confirmResetAlert.runModal()

        if response == .alertFirstButtonReturn {
            appDelegate.keystrokeCount = 0
            appDelegate.updateCount()
        }
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


struct KeystrokeDataObject: Codable {
    let timestamp: String
    let intervalData: [Int]
    let keystrokeCountBefore: Int
    let keystrokeCountAfter: Int
    let intervalLength: Int
    let updatePrecision: Int
}
