import AppKit
import NiviCore

// The app used to be called Dictato. macOS keys both the settings and the support
// folder to the app's name, so under the new name it would find neither. Bring them
// across before any other code reads them.
if let copied = LegacyNameMigration.copySettings(
    to: Bundle.main.bundleIdentifier ?? "com.dvir.nivi",
    using: .standard) {
    Log.info("Settings brought over from the old Dictato name: \(copied) keys")
}
let supportBase = ModelPaths.appSupportBase()
if LegacyNameMigration.moveSupportDirectory(
    from: LegacyNameMigration.legacySupportDirectory(), to: supportBase) {
    Log.info("Moved the old Dictato support folder to \(supportBase.path)")
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
