import SwiftUI

/// The one glance: time, distance, pace, zone. The screen title lives in
/// content ("RUN" / "MAX"); the system clock owns the top line.
/// Tap to pause (the both-buttons hardware gesture pauses too).
struct RunView: View {
    @ObservedObject var session: RunSession
    @Environment(\.isLuminanceReduced) private var systemDimmed

    private var dimmed: Bool { systemDimmed || AlwaysOn.forcedForDebug }
    private var palette: RunPalette { RunPalette(dimmed: dimmed) }

    var body: some View {
        ZStack {
            if session.type == .pacer {
                PacerRunView(session: session)
            } else {
                quickRun
            }

            if let alert = session.kilometerAlert {
                KilometerAlertView(alert: alert)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.kilometerAlert)
        .contentShape(Rectangle())
        .onTapGesture { session.pause() }
        // Caption owned by the container so both Run and Pacer show it — a
        // consistent nav bar keeps their heroes at the same height. Hidden
        // while the kilometer alert owns the whole canvas.
        .topBarCaption {
            if session.kilometerAlert == nil {
                switch session.type {
                case .pacer:
                    TopBarCaption(text: "PACER", color: palette.label)
                default:
                    if session.currentZone >= 5 {
                        TopBarCaption(text: "MAX", color: palette.signal)
                    } else {
                        TopBarCaption(text: "RUN", color: palette.label)
                    }
                }
            }
        }
    }

    private var quickRun: some View {
        RunTimeline(session: session) { elapsed in
            quickRunBody(elapsed: elapsed)
        }
    }

    @ViewBuilder
    private func quickRunBody(elapsed: TimeInterval) -> some View {
        let zone = session.currentZone
        RunScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // The digit morph is a wrist-up nicety: animations do not run
                // in always-on, and a half-tweened glyph at 1 Hz would read as
                // a rendering fault.
                Text(Format.clock(elapsed))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(dimmed ? .identity : .numericText())
                    .animation(dimmed ? nil : .linear(duration: 0.25), value: elapsed)

                // Run only shows two values, and the Ultra leaves ~120 pt of
                // air under them — so they grow to 28 pt and float centered
                // between the time and the zone bar, a middle "dashboard row"
                // rather than an appendix of the hero. The bottom pad offsets
                // the line-box slop above (15 pt descender + cap headroom),
                // landing the *ink* a hair above center — measured on Ultra.
                Spacer(minLength: 0)
                // Same two-column grid as Trail (equal columns, 18 pt gap),
                // so PACE /KM sits at the same x on every run screen.
                // 30 pt: five tabular glyphs ("16.93") run 1.4 pt past the
                // half-width column, so the values paint over the edge at
                // full size (valueOutsideLayout) exactly like the design's
                // CSS grid — never scaled, baselines locked.
                HStack(alignment: .top, spacing: 18) {
                    BigStat(value: Format.km(session.distanceKm), label: "KM",
                            valueColor: palette.stat,
                            size: 30, labelSize: 11, labelGap: 4,
                            valueOutsideLayout: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Pace gives up its orange when dimmed — the reduced screen
                    // keeps exactly one accent, and it belongs to the zone.
                    BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM",
                            valueColor: dimmed ? palette.stat : Theme.signal,
                            size: 30, labelSize: 11, labelGap: 4,
                            valueOutsideLayout: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 14)
                Spacer(minLength: 0)
            }
        } footer: {
            ZoneFooter(zone: zone, position: session.zones.position(forHR: session.heartRate))
        }
    }
}

struct BigStat: View {
    var value: String
    var label: String
    var valueColor: Color = Theme.ink
    var size: CGFloat = 21
    var labelSize: CGFloat = 8
    /// nil → follow the ambient palette, so labels dim with the screen.
    var labelColor: Color?
    /// The design's margin under the value (run cards 3, trail cards 2.5).
    var labelGap: CGFloat = 3
    /// In a `1fr` grid the design lets a long label paint past its column
    /// edge without widening it; SwiftUI would widen. `true` takes the label
    /// out of layout: a ghost keeps the line height, an overlay draws it.
    var labelOutsideLayout = false
    /// Same, for the value: paint past the column edge at full size (CSS
    /// overflow) instead of scaling down. Five tabular glyphs ("16.93",
    /// "10:00") outgrow a half-width column at 30 pt; scaling one column
    /// would break the shared baseline with its neighbour.
    var valueOutsideLayout = false
    @Environment(\.runPalette) private var palette

    var body: some View {
        // Only the value line is cropped in the design; the label keeps its
        // natural box there too.
        VStack(alignment: .leading, spacing: LineBox.gap(labelGap, cropping: size)) {
            Text(value)
                .font(.stat(size))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .fixedSize(horizontal: valueOutsideLayout, vertical: false)
                // Compress rather than truncate when the value must stay in
                // its column (summaries' three-across rows).
                .minimumScaleFactor(valueOutsideLayout ? 1 : 0.85)
            if labelOutsideLayout {
                Text(verbatim: " ")
                    .kicker(labelSize, tracking: 0.1)
                    .overlay(alignment: .leading) {
                        Text(label)
                            .kicker(labelSize, color: labelColor ?? palette.label, tracking: 0.1)
                            .lineLimit(1)
                            .fixedSize()
                    }
            } else {
                Text(label)
                    .kicker(labelSize, color: labelColor ?? palette.label, tracking: 0.1)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Auto kilometer alert — shows for 5 s over the run screen.
struct KilometerAlertView: View {
    var alert: RunSession.KilometerAlert
    @Environment(\.isLuminanceReduced) private var systemDimmed

    private var dimmed: Bool { systemDimmed || AlwaysOn.forcedForDebug }
    private var palette: RunPalette { RunPalette(dimmed: dimmed) }

    var body: some View {
        // If a split lands with the wrist down it renders in the reduced
        // palette too. The haptic still fires at full strength — that is what
        // actually gets attention; waking the panel to full brightness would
        // spend exactly what this mode protects.
        VStack(spacing: 0) {
            Text("KILOMETER").kicker(8.5, color: palette.label, tracking: 0.16)
            Text("\(alert.km)")
                .font(.stat(65))
                .kerning(-3.25)
                .foregroundStyle(palette.hero)
                .padding(.top, 3)
            Text(Format.pace(alert.splitSeconds))
                .font(.stat(20))
                .foregroundStyle(palette.signal)
                .padding(.top, 10)
            Text("\(Format.paceDelta(alert.deltaVsAvg)) vs avg")
                .font(.stat(8.5, weight: .regular))
                .foregroundStyle(palette.label)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

/// Same screen in every mode.
struct PausedView: View {
    @ObservedObject var session: RunSession
    var onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(session.elapsed))
                    .font(.stat(42))
                    .kerning(-1.9)
                    .foregroundStyle(Theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    StatInline(value: Format.km(session.distanceKm), unit: "km", size: 15, color: Theme.dim)
                    StatInline(value: Format.pace(session.averagePace), unit: "/km", size: 15, color: Theme.dim)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 12)

            // Design ratio: End 1 : Resume 1.4.
            GeometryReader { proxy in
                let endWidth = (proxy.size.width - 8) / 2.4
                HStack(spacing: 8) {
                    Button(action: onEnd) {
                        Text("End")
                            .font(.sg(15, weight: .semibold))
                            .frame(width: endWidth, height: 50)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.75))
                    }
                    Button(action: { session.resume() }) {
                        Text("Resume")
                            .font(.sg(15, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                            .background(Theme.signal, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 50)
        }
        .padding(EdgeInsets(top: 6, leading: 20, bottom: 16, trailing: 20))
        .topBarCaption { TopBarCaption(text: "PAUSED", color: Theme.signal) }
    }
}
