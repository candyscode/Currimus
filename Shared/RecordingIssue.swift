import Foundation

/// Something the recording cannot do, in the user's terms.
///
/// These used to be silent `return`s. A denied Health prompt left the
/// clock ticking over a distance frozen at 0.00 with nothing on screen to
/// explain it — the worst failure this app has, because a run cannot be
/// run again.
///
/// Two kinds live here. `blocksRecording` ones make a run pointless before
/// it starts, so the run never starts. The rest only degrade it, and the
/// user gets to decide whether that is worth running for.
enum RecordingIssue: Equatable, Hashable {
    case healthUnavailable
    case healthDenied
    case workoutFailed
    case locationDenied
    /// The run started, but distance never moved.
    ///
    /// This is the one failure no check can catch at the door: Health hides
    /// read authorization, so someone can allow "save workouts" — which is all
    /// the gate can see — and refuse Distance separately. It only becomes
    /// visible once the run is under way and the number stays at zero.
    case noDistance

    /// Distance and heart rate both come from the workout builder. Without
    /// it there is nothing to record but the clock, so these stop the run
    /// at the door rather than let it produce an empty log entry.
    var blocksRecording: Bool {
        switch self {
        case .healthUnavailable, .healthDenied, .workoutFailed: return true
        // Both surface only once a run is already under way.
        case .locationDenied, .noDistance: return false
        }
    }

    var headline: String {
        switch self {
        case .healthUnavailable: return String(localized: "No Health data")
        case .healthDenied: return String(localized: "Health access needed")
        case .workoutFailed: return String(localized: "Workout not started")
        case .locationDenied: return String(localized: "Location off")
        case .noDistance: return String(localized: "No distance")
        }
    }

    /// What is lost, and why. Written to explain rather than to scold —
    /// a refusal the user cannot account for reads like a bug.
    var detail: String {
        switch self {
        case .healthUnavailable:
            return String(localized: "This watch has no Health data, so a run cannot record heart rate or distance.")
        case .healthDenied:
            return String(localized: "Currimus records your run as an Apple Health workout. Distance and heart rate come from there, so without access there is nothing to record.")
        case .workoutFailed:
            return String(localized: "The workout session did not start. Another app may be recording a workout already.")
        case .locationDenied:
            return String(localized: "Without location there is no route, climb or elevation. Heart rate and distance still record.")
        case .noDistance:
            return String(localized: "Health is not reporting distance for this run, so it cannot be saved. Check that Distance is allowed for Currimus.")
        }
    }

    /// Where to go to fix it. watchOS has no URL that opens Settings, so
    /// naming the exact path is the whole recovery path.
    var recovery: String? {
        switch self {
        case .healthDenied:
            return String(localized: "iPhone › Watch › Privacy › Health › Currimus")
        case .locationDenied:
            return String(localized: "iPhone › Watch › Privacy › Location › Currimus")
        case .workoutFailed:
            return String(localized: "End the other workout, then try again.")
        case .noDistance:
            return String(localized: "iPhone › Watch › Privacy › Health › Currimus")
        case .healthUnavailable:
            return nil
        }
    }
}
