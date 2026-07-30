import Foundation

/// What a run is called when nobody named it.
///
/// One rule for two sources that used to disagree completely. The watch named
/// its own runs by the time of day; a run read out of Apple Health took
/// `sourceRevision.source.name`, which is the recording app's name only for
/// third-party apps — for anything Apple's own Workout app recorded it is the
/// *device* name. So half the log read "Apple Watch von Andreas", which says
/// nothing about the run and repeats itself on every row.
///
/// No reverse geocoding, tempting as "Run in Munich" is: this app makes no
/// network calls at all, and that is worth more than a nicer noun.
enum RunNaming {
    /// The name to give a run with nothing else to go on.
    static func defaultName(for date: Date, type: RunType = .quick,
                            isIndoor: Bool = false) -> String {
        if type == .trail { return String(localized: "Trail run") }
        // A treadmill session has a time of day like any other, but "Indoor
        // Run" is the thing about it worth putting in a name.
        if isIndoor { return String(localized: "Indoor Run") }
        switch Calendar.current.component(.hour, from: date) {
        case ..<5: return String(localized: "Night Run")
        case ..<11: return String(localized: "Morning Run")
        case ..<17: return String(localized: "Afternoon Run")
        case ..<22: return String(localized: "Evening Run")
        default: return String(localized: "Night Run")
        }
    }
}
