import SwiftUI

/// The active recording problem, published down the view tree.
///
/// Run, Pacer and Trail all build on `RunScaffold`, and all three summaries on
/// `SummaryScroller` — putting the issue in the environment means those two
/// places show it for every screen, with no call site having to remember.
private struct RecordingIssueKey: EnvironmentKey {
    static let defaultValue: RunSession.RecordingIssue? = nil
}

extension EnvironmentValues {
    var recordingIssue: RunSession.RecordingIssue? {
        get { self[RecordingIssueKey.self] }
        set { self[RecordingIssueKey.self] = newValue }
    }
}

/// One quiet line above the footer while the run is live.
///
/// Deliberately not a modal: the run is still worth recording, and a dialog
/// mid-stride is the wrong trade. It is loud enough to notice at a glance and
/// small enough to ignore until the end.
struct RecordingIssueNote: View {
    var issue: RunSession.RecordingIssue

    var body: some View {
        HStack(spacing: 4) {
            TriangleMark()
                .fill(Theme.signal)
                .frame(width: 6, height: 5.5)
            Text(issue.headline)
                .font(.sg(9, weight: .medium))
                .foregroundStyle(Theme.signal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording problem: \(issue.headline). \(issue.detail)")
    }
}

/// The same problem on the summary, where there is room to say what to do.
struct RecordingIssueCard: View {
    var issue: RunSession.RecordingIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                TriangleMark()
                    .fill(Theme.signal)
                    .frame(width: 7, height: 6)
                Text(issue.headline)
                    .font(.sg(11, weight: .semibold))
                    .foregroundStyle(Theme.signal)
            }
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
