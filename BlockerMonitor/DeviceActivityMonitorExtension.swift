import DeviceActivity
import Foundation
import ManagedSettings
import FamilyControls
import os

let logger = Logger(subsystem: "com.Donat.ScreenGamba.BlockerMonitor", category: "MonitorLogic")

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    // Bring back the store and userDefaults using the shared constant
    lazy var store = ManagedSettingsStore()
    lazy var userDefaults = UserDefaults(suiteName: appGroupName)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.log("✅ DeviceActivityMonitorExtension: Interval starting for \(activity.rawValue)")

        guard let defaults = userDefaults else {
            logger.error("❌ DeviceActivityMonitorExtension: Failed to initialize UserDefaults with suite name: \(appGroupName). App Group configured correctly?")
            return
        }
        logger.log("➡️ DeviceActivityMonitorExtension: UserDefaults initialized.")

        // --- Load selection from UserDefaults and apply restrictions ---
        handleStartEvent(defaults: defaults) // Call the function to apply shields
        // --- End loading and applying restrictions ---
        logger.log("🏁 DeviceActivityMonitorExtension: intervalDidStart completed for \(activity.rawValue).")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.log("🚫 DeviceActivityMonitorExtension: Interval ending for \(activity.rawValue)")

        // Remove all restrictions when the interval ends
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        logger.log("🛡️ DeviceActivityMonitorExtension: Shields removed for \(activity.rawValue).")
        logger.log("🏁 DeviceActivityMonitorExtension: intervalDidEnd completed for \(activity.rawValue).")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.log("⚠️ DeviceActivityMonitorExtension: Threshold reached for \(event.rawValue) in activity \(activity.rawValue)")
    }

    // --- Function to handle start using UserDefaults data ---
    // Accepts UserDefaults instance as parameter
    private func handleStartEvent(defaults: UserDefaults) {
       logger.log("➡️ DeviceActivityMonitorExtension: handleStartEvent called.")

       // Use the correct key defined in ScreenTimeShared.swift
       guard let savedData = defaults.data(forKey: selectionToDiscourageKey) else {
            logger.warning("⚠️ DeviceActivityMonitorExtension: Could not find data in UserDefaults for key: \(selectionToDiscourageKey). Was selection saved correctly by the app?")
            // Clear shields just in case
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            return
       }
       logger.log("➡️ DeviceActivityMonitorExtension: Found data in UserDefaults (\(savedData.count) bytes) for key \(selectionToDiscourageKey).")

       do {
           let decoder = JSONDecoder()
           let loadedSelection = try decoder.decode(FamilyActivitySelection.self, from: savedData)
           logger.log("➡️ DeviceActivityMonitorExtension: Successfully decoded FamilyActivitySelection.")

           let appCount = loadedSelection.applicationTokens.count
           let catCount = loadedSelection.categoryTokens.count
           let webCount = loadedSelection.webDomainTokens.count
           logger.log("➡️ DeviceActivityMonitorExtension: Applying restrictions - Apps: \(appCount), Categories: \(catCount), WebDomains: \(webCount)")

           // Apply restrictions using the lazy var 'store'
           // Ensure store is properly initialized
           store.shield.applications = loadedSelection.applicationTokens.isEmpty ? nil : loadedSelection.applicationTokens
           logger.log("➡️ DeviceActivityMonitorExtension: Applied application shield.")

           store.shield.applicationCategories = loadedSelection.categoryTokens.isEmpty ? nil : ShieldSettings.ActivityCategoryPolicy.specific(loadedSelection.categoryTokens)
           logger.log("➡️ DeviceActivityMonitorExtension: Applied category shield.")

           store.shield.webDomains = loadedSelection.webDomainTokens.isEmpty ? nil : loadedSelection.webDomainTokens
           logger.log("➡️ DeviceActivityMonitorExtension: Applied web domain shield.")

           logger.log("✅ DeviceActivityMonitorExtension: Successfully applied all shields.")

       } catch {
           logger.error("❌ DeviceActivityMonitorExtension: Failed to decode FamilyActivitySelection from UserDefaults data. Error: \(error.localizedDescription)")
           // Clear shields if decoding failed
           store.shield.applications = nil
           store.shield.applicationCategories = nil
           store.shield.webDomains = nil
       }
    }
}
