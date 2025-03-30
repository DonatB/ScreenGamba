import Foundation
import FamilyControls
import DeviceActivity
import Combine
import os // Import for Logger

// Create a logger instance for this specific class
private let modelLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.Donat.ScreenGamba", category: "ScreenTimeSelectAppsModel") // Use your app's bundle ID

class ScreenTimeSelectAppsModel: ObservableObject {

    static let shared = ScreenTimeSelectAppsModel()

    let center = DeviceActivityCenter()
    // Ensure appGroupName comes from your shared constants file
    let userDefaults = UserDefaults(suiteName: appGroupName)

    @Published var activitySelection = FamilyActivitySelection() {
        didSet {
            saveSelection()
            modelLogger.info("Selection Updated and Saved") // Use logger
        }
    }
    @Published var isPickerPresented = false
    // Default state, will be updated by checkInitialMonitoringState
    @Published var isBlockingActive = false

    // Keep track of activities started *in this session* if needed,
    // but rely on prefix checking for actual state.
    private var monitoringActivities = Set<DeviceActivityName>()

    // Define the prefix used for your activity names (MUST match startBlocking)
    private let activityNamePrefix = "MyApp.BlockSelectedApps." // Or choose a unique prefix for ScreenGamba

    private init() {
        loadSelection()
        // Check the actual monitoring state when the model initializes
        checkInitialMonitoringState()
        modelLogger.debug("ScreenTimeSelectAppsModel initialized.")
    }

    // --- Function to check system monitoring state on launch ---
    func checkInitialMonitoringState() {
        Task { // Perform check asynchronously
            let currentActivities = self.center.activities
            modelLogger.log("Checking initial state. System reports \(currentActivities.count) active DeviceActivity schedules.")

            // Check if ANY current activity matches our prefix
            let isMonitoringCurrentlyActive = currentActivities.contains { $0.rawValue.hasPrefix(self.activityNamePrefix) }

            modelLogger.log("Is monitoring active based on prefix '\(self.activityNamePrefix)': \(isMonitoringCurrentlyActive)")

            // Update the UI state on the main thread
            await MainActor.run {
                self.isBlockingActive = isMonitoringCurrentlyActive
                // If monitoring is active, store the names (optional, useful for debug)
                if isMonitoringCurrentlyActive {
                    self.monitoringActivities = Set(currentActivities.filter { $0.rawValue.hasPrefix(self.activityNamePrefix) })
                    modelLogger.log("Stored currently active monitoring activities: \(self.monitoringActivities.map { $0.rawValue })")
                } else {
                    self.monitoringActivities.removeAll()
                }
            }
        }
    }

    func startBlocking(durationHours: Int = 1) {
        saveSelection() // Ensure latest selection is saved

        guard !activitySelection.applicationTokens.isEmpty ||
              !activitySelection.categoryTokens.isEmpty ||
              !activitySelection.webDomainTokens.isEmpty else {
            modelLogger.warning("StartBlocking requested but no apps/categories/websites selected.")
            // Optionally show an alert to the user here
            return
        }

        let now = Date()
        // Schedule starts immediately
        let scheduleTime = Calendar.current.dateComponents([.hour, .minute, .second], from: now)

        guard let endTime = Calendar.current.date(byAdding: .hour, value: durationHours, to: now) else {
            modelLogger.error("Error calculating end time for blocking schedule.")
            return
        }
        let endScheduleTime = Calendar.current.dateComponents([.hour, .minute, .second], from: endTime)

        let schedule = DeviceActivitySchedule(
            intervalStart: scheduleTime,
            intervalEnd: endScheduleTime,
            repeats: false // Block only once for the specified duration
        )

        // Create a unique activity name using the defined prefix
        let activityName = DeviceActivityName(activityNamePrefix + UUID().uuidString)
        modelLogger.log("Generated activity name for new schedule: \(activityName.rawValue)")

        do {
            modelLogger.log("Attempting to start monitoring for \(activityName.rawValue)...")
            // Pass empty events dictionary; selection data comes from UserDefaults in the Monitor Extension
            try center.startMonitoring(activityName, during: schedule, events: [:])

            monitoringActivities.insert(activityName) // Track the specific activity started
            // Update UI immediately on the main thread
            DispatchQueue.main.async {
                self.isBlockingActive = true
            }
            modelLogger.log("Monitoring started successfully via DeviceActivityCenter.")
        } catch {
            modelLogger.error("Error starting monitoring for \(activityName.rawValue): \(error.localizedDescription)")
            // Optionally update UI to show error or revert isBlockingActive state
            DispatchQueue.main.async {
                self.isBlockingActive = false // Revert UI if start failed
            }
        }
    }

    func stopBlocking() {
        // More robust: Stop ALL activities matching the prefix found by the system NOW.
        let currentActivities = center.activities // Get current activities from the system
        let activitiesToStop = currentActivities.filter { $0.rawValue.hasPrefix(self.activityNamePrefix) }

        if activitiesToStop.isEmpty {
             modelLogger.warning("StopBlocking called, but no activities found matching prefix '\(self.activityNamePrefix)'. State might be inconsistent.")
             // Attempt to stop any locally stored activities as a fallback
             if !self.monitoringActivities.isEmpty {
                  modelLogger.log("Attempting to stop locally stored activities as fallback: \(self.monitoringActivities.map { $0.rawValue })")
                  center.stopMonitoring(Array(self.monitoringActivities))
             }
        } else {
             modelLogger.log("Stopping monitoring for activities matching prefix: \(activitiesToStop.map { $0.rawValue })")
             center.stopMonitoring(activitiesToStop)
        }

        monitoringActivities.removeAll() // Clear local tracking
        // Update UI immediately on the main thread
        DispatchQueue.main.async {
            self.isBlockingActive = false
        }
        modelLogger.log("Monitoring stopped command sent.")
    }

    // --- Persistence Functions (Using App Group UserDefaults) ---
    func saveSelection() {
        let encoder = JSONEncoder()
        do {
             let encoded = try encoder.encode(activitySelection)
             // Use the shared key constant
             userDefaults?.set(encoded, forKey: selectionToDiscourageKey)
             // synchronize() might help ensure data is written promptly, especially before extension might need it.
             // Consider adding if you face timing issues, but often not strictly necessary.
             // userDefaults?.synchronize()
             modelLogger.debug("Selection saved to UserDefaults for key '\(selectionToDiscourageKey)'.")
        } catch {
             modelLogger.error("Failed to encode or save selection to UserDefaults: \(error.localizedDescription)")
        }
    }

    func loadSelection() {
        guard let defaults = userDefaults else {
            modelLogger.error("Failed to initialize UserDefaults in loadSelection. App Group correct?")
            return
        }
        // Use the shared key constant
        guard let savedData = defaults.data(forKey: selectionToDiscourageKey) else {
            modelLogger.info("No saved selection found in UserDefaults for key '\(selectionToDiscourageKey)'. Initializing empty selection.")
            // Initialize with empty if loading fails or doesn't exist
            DispatchQueue.main.async {
                 // Only reset if it's truly empty, avoid overwriting if picker just set it
                if self.activitySelection.applicationTokens.isEmpty &&
                   self.activitySelection.categoryTokens.isEmpty &&
                   self.activitySelection.webDomainTokens.isEmpty {
                     self.activitySelection = FamilyActivitySelection()
                }
            }
            return
        }

        do {
            let decoder = JSONDecoder()
            let loadedSelection = try decoder.decode(FamilyActivitySelection.self, from: savedData)
            DispatchQueue.main.async {
                self.activitySelection = loadedSelection
                modelLogger.debug("Selection successfully loaded from UserDefaults.")
            }
        } catch {
            modelLogger.error("Failed to decode selection loaded from UserDefaults: \(error.localizedDescription)")
            // Consider resetting to empty if decoding fails
            DispatchQueue.main.async {
                self.activitySelection = FamilyActivitySelection()
            }
        }
    }
}
