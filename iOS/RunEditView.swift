import SwiftUI

/// The three things about a run that are a judgement rather than a
/// measurement: what it was called, whether it was a trail, and which kind of
/// session it counts as.
///
/// Distance, time, heart rate and the track are not editable and should not
/// be — they were measured, and a log you can rewrite is not a record. The
/// classification is different: it is a heuristic over split spread and zone
/// time, it leads every row in the log, and it is wrong often enough that
/// living with it is worse than allowing a correction.
struct RunEditView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.dismiss) private var dismiss

    private let original: Run
    @State private var name: String
    @State private var isTrail: Bool
    @State private var classification: RunClass?
    @State private var loaded = false

    init(run: Run) {
        original = run
        _name = State(initialValue: run.name)
        _isTrail = State(initialValue: run.isTrail)
        _classification = State(initialValue: run.classificationOverride)
    }

    /// What the heuristic would say, with any override removed — so the
    /// "Automatic" row can name the answer it is offering.
    private var automaticLabel: String {
        var stripped = original
        stripped.classificationOverride = nil
        stripped.type = .quick
        return stripped.classification.label
    }

    /// Road sessions only. A trail run is classified by how it was recorded.
    private static let choices: [RunClass] = [.easy, .tempo, .intervals, .long, .race]

    var body: some View {
        PushedScreen(title: "Edit run") {
            VStack(alignment: .leading, spacing: 0) {
                if original.isImported {
                    imported
                } else {
                    editor
                }
            }
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        fieldLabel("NAME")
        TextField("Run name", text: $name)
            .font(.sg(16)).tint(Theme.signal)
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
            .background(Theme.glassCardFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.glassCardStroke, lineWidth: 1))
            .padding(.top, 10)

        fieldLabel("SURFACE").padding(.top, 26)
        SegmentChips(options: [(false, "Road"), (true, "Trail")], selection: $isTrail)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.top, 12)
        Text("Trail runs are measured by climb and grade-adjusted pace rather than pace alone.")
            .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 10)

        if !isTrail {
            fieldLabel("SESSION").padding(.top, 30)
            VStack(spacing: 0) {
                choiceRow(nil, title: "Automatic", detail: "Currently reads as \(automaticLabel)")
                ForEach(Self.choices, id: \.self) { option in
                    Theme.hairline.frame(height: 1)
                    choiceRow(option, title: option.label, detail: nil)
                }
            }
            .padding(.top, 8)
        }

        Button(action: save) {
            Text("Save").font(.sg(17, weight: .bold)).foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.signal, in: Capsule())
        }
        .buttonStyle(.plain).padding(.top, 30)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
    }

    private func choiceRow(_ option: RunClass?, title: String, detail: String?) -> some View {
        Button { classification = option } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.sg(16))
                    if let detail {
                        Text(detail).font(.sg(13)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Image(systemName: classification == option ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(classification == option ? Theme.signal : Theme.chipStroke)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Imported

    /// Currimus is only reading this one, so it must not offer to rewrite it.
    private var imported: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recorded by \(original.name)").font(.sg(16, weight: .semibold))
            Text("This run came from Apple Health. Currimus counts it towards every total, but the run itself belongs to the app that recorded it — edit or delete it there.")
                .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
        }
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t).kicker(13, color: Theme.bright, tracking: 0.12)
    }

    private func save() {
        var edited = original
        edited.name = name.trimmingCharacters(in: .whitespaces)
        edited.type = isTrail ? .trail : (original.type == .trail ? .quick : original.type)
        edited.classificationOverride = isTrail ? nil : classification
        store.update(edited)
        dismiss()
    }
}
