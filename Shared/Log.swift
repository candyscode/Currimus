import os

/// Where failures go instead of vanishing.
///
/// Persistence, sync and recording all used to swallow their errors (`try?`,
/// ignored completion handlers). That is fine for control flow — none of them
/// have a sensible recovery — but it left no trace at all, so a run that
/// failed to save in the field was undiagnosable. These loggers keep the
/// control flow and add the trace; they show up in Console.app and in a
/// sysdiagnose under the `com.currimus.app` subsystem.
enum Log {
    private static let subsystem = "com.currimus.app"

    /// Run log persistence and the sample sidecar files.
    static let store = Logger(subsystem: subsystem, category: "store")
    /// Watch ↔ iPhone transfer.
    static let sync = Logger(subsystem: subsystem, category: "sync")
    /// The recording engine: workout session, location, metrics.
    static let session = Logger(subsystem: subsystem, category: "session")
    /// Apple Health reads and writes.
    static let health = Logger(subsystem: subsystem, category: "health")
}
