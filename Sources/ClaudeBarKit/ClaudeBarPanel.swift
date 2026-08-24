import SwiftUI
import GlassKit

public enum Layout {
    /// Wider than PomoDot's 268 because the detail rows carry paths and branch names.
    public static let panelWidth: CGFloat = 300
}

/// The ClaudeBar panel.
///
/// Every visual element here comes from GlassKit — `DotMatrixView`, `SegmentGauge`,
/// `GaugeRow`, `DetailRow`, `Legend`, `Hairline`, and the single `.glassEffect` surface.
/// Nothing in this file defines a colour, a font, or a spring. That's the test of the
/// extraction: a second app should be composition only.
public struct ClaudeBarPanel: View {
    @Bindable private var reader: UsageReader
    private let onQuit: () -> Void
    private let now: () -> Date

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(reader: UsageReader,
                now: @escaping () -> Date = { Date() },
                onQuit: @escaping () -> Void) {
        self.reader = reader
        self.now = now
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = reader.snapshot {
                header(snapshot)
                headline(snapshot)
                secondary(snapshot)
                context(snapshot)
                session(snapshot)
                flags(snapshot)
            } else {
                empty
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: Layout.panelWidth)
        .glassSurface()
    }

    /// The accent is driven by the 5-hour window, because that's the constraint that bites.
    private func accent(_ snapshot: UsageSnapshot) -> Color {
        Theme.accent(forLoad: snapshot.fiveHour.used)
    }

    // MARK: - Header

    private func header(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 7) {
            // Status LED, same idiom as PomoDot: colour beside a word, never inside it.
            Circle()
                .fill(snapshot.isLive(now: now()) ? accent(snapshot) : Color.primary.opacity(0.25))
                .frame(width: 5, height: 5)
            Legend("CLAUDE CODE", opacity: 0.9)
            Spacer()
            Legend(snapshot.statusText(now: now()), size: 8, opacity: 0.38)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Headline: the 5-hour window

    private func headline(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                // The one number a glance is for, in the matrix.
                DotMatrixView(snapshot.headlineText,
                              dotSize: 3,
                              dotSpacing: 1.6,
                              litColor: .primary.opacity(0.95),
                              unlitOpacity: reduceTransparency ? 0.10 : Theme.dotOff)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Legend("5-HOUR", size: 8, opacity: 0.34)
                    Text(snapshot.fiveHour.resetText(now: now()))
                        .font(Theme.numeral(11))
                        .tracking(Theme.numeralTracking)
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.9))
                }
            }
            SegmentGauge(value: snapshot.fiveHour.used, segments: 20, accent: accent(snapshot), height: 10)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Secondary: the 7-day window

    private func secondary(_ snapshot: UsageSnapshot) -> some View {
        GaugeRow(label: "7-DAY",
                 value: snapshot.sevenDay.used,
                 trailing: "\(Int((snapshot.sevenDay.used * 100).rounded()))%",
                 detail: snapshot.sevenDay.resetText(now: now()),
                 accent: Theme.accent(forLoad: snapshot.sevenDay.used))
            .padding(.bottom, 14)
    }

    // MARK: - Context

    private func context(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
            GaugeRow(label: "CONTEXT",
                     value: snapshot.contextUsed,
                     trailing: snapshot.contextText,
                     accent: Theme.accent(forLoad: snapshot.contextUsed))
        }
        .padding(.bottom, 14)
    }

    // MARK: - Session

    private func session(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
                .padding(.bottom, 4)
            DetailRow("MODEL", snapshot.modelName)
            DetailRow("PROJECT", snapshot.project)
            DetailRow("DIFF", "+\(snapshot.linesAdded)  −\(snapshot.linesRemoved)")
            DetailRow("VERSION", snapshot.version)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Flags

    private func flags(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 6) {
            Legend("\(snapshot.effort.uppercased()) · THINK \(snapshot.thinking ? "ON" : "OFF") · FAST \(snapshot.fastMode ? "ON" : "OFF")",
                   size: 8, opacity: 0.34)
            Spacer()
            Button(action: onQuit) {
                Legend("QUIT", size: 8, opacity: 0.34).modifier(HitTarget())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Quit ClaudeBar"))
        }
    }

    // MARK: - Empty

    /// Shown when the payload is missing entirely. States the cause and the fix rather than
    /// rendering zeroes, which would look like "you have used nothing".
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Color.primary.opacity(0.25)).frame(width: 5, height: 5)
                Legend("CLAUDE CODE", opacity: 0.9)
                Spacer()
                Legend("NO DATA", size: 8, opacity: 0.38)
            }
            Hairline()
            Legend(reader.lastError ?? "waiting for a claude code session", size: 8, opacity: 0.45)
            Legend("needs the claude-statusbar status line active", size: 8, opacity: 0.3)
            HStack {
                Spacer()
                Button(action: onQuit) {
                    Legend("QUIT", size: 8, opacity: 0.34).modifier(HitTarget())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
