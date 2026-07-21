import SwiftUI

/// The active recording problem, published down the view tree.
///
/// Run, Pacer and Trail all build on `RunScaffold`, and all three summaries on
/// `SummaryScroller` — putting the issue in the environment means those two
/// places show it for every screen, with no call site having to remember.
private struct RecordingIssueKey: EnvironmentKey {
    static let defaultValue: RecordingIssue? = nil
}

extension EnvironmentValues {
    var recordingIssue: RecordingIssue? {
        get { self[RecordingIssueKey.self] }
        set { self[RecordingIssueKey.self] = newValue }
    }

    /// The finished run measured no distance and was therefore not filed.
    var runNotSaved: Bool {
        get { self[RunNotSavedKey.self] }
        set { self[RunNotSavedKey.self] = newValue }
    }
}

private struct RunNotSavedKey: EnvironmentKey {
    static let defaultValue = false
}

/// The gap between tapping Start and the run starting, while Health is asked.
/// Usually a frame or two — it only becomes visible when the permission sheet
/// is up, and then a countdown running behind that sheet would be worse.
struct PreparingView: View {
    var body: some View {
        VStack(spacing: 5) {
            Text("CURRIMUS")
                .font(.sg(16, weight: .bold))
                .kerning(16 * 0.04)
            Text("Checking Health…")
                .font(.sg(11))
                .foregroundStyle(Theme.bright)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One quiet line above the footer while the run is live.
///
/// Deliberately not a modal: the run is still worth recording, and a dialog
/// mid-stride is the wrong trade. It is loud enough to notice at a glance and
/// small enough to ignore until the end.
struct RecordingIssueNote: View {
    var issue: RecordingIssue
    @Environment(\.runPalette) private var palette

    var body: some View {
        // No glyph: the triangle belongs to trail and climb, and borrowing it
        // for a warning would give one mark two meanings. Signal on its own
        // already reads as "look here".
        Text(issue.headline)
            .font(.sg(9, weight: .medium))
            .foregroundStyle(palette.signal)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording problem: \(issue.headline). \(issue.detail)")
    }
}

/// Why a run will not start, and what to change so it will.
///
/// A refusal is only acceptable if it explains itself: the headline names the
/// problem, the body says why Currimus cannot work around it, and the path is
/// spelled out because watchOS has no URL that opens Settings for us.
struct RecordingBlockedView: View {
    var issue: RecordingIssue
    var onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(issue.headline)
                    .font(.sg(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(issue.detail)
                    .font(.sg(11))
                    .foregroundStyle(Theme.bright)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)

                if let recovery = issue.recovery {
                    Text(recovery)
                        .font(.sg(10, weight: .medium))
                        .foregroundStyle(Theme.signal)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 9)
                        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.signal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                Button(action: onBack) {
                    Text("Back")
                        .font(.sg(13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                        .background(Theme.button, in: Capsule())
                        .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(EdgeInsets(top: 4, leading: 20, bottom: 16, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .topBarCaption { TopBarCaption(text: "CANNOT RECORD", color: Theme.signal) }
    }
}

/// The same problem on the summary, where there is room to say what to do.
struct RecordingIssueCard: View {
    var issue: RecordingIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(issue.headline)
                .font(.sg(11, weight: .semibold))
                .foregroundStyle(Theme.signal)
                .fixedSize(horizontal: false, vertical: true)
            Text(issue.detail)
                .font(.sg(9))
                .foregroundStyle(Theme.bright)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
        .background(Theme.signal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.signal.opacity(0.3), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}
