import SwiftUI
import HeadroomCore

struct CardView: View {
    @ObservedObject var monitor: Monitor
    var isFloating = false
    var toggleFloating: () -> Void
    var quit: () -> Void

    private let accent = Color.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack {
                    Text("Headroom").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                .floatingDragSurface(isFloating)
                if isFloating {
                    Button(action: toggleFloating) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Hide floating panel").accessibilityLabel("Hide floating panel")
                } else {
                    Button { monitor.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain).disabled(monitor.refreshing)
                    .help("Refresh readings").accessibilityLabel("Refresh readings")
                }
            }
            .padding(.bottom, 22)

            HStack(alignment: .top, spacing: 22) {
                metric(title: "Disk", symbol: "internaldrive",
                       value: monitor.disk?.formatted ?? "—", caption: "available",
                       fraction: monitor.disk?.fraction,
                       stale: monitor.diskError != nil)
                Rectangle().fill(.primary.opacity(0.09)).frame(width: 1, height: 82)
                metric(title: "Codex", symbol: "circle.hexagongrid",
                       value: monitor.codexValue,
                       caption: monitor.codexCaption,
                       fraction: monitor.showCredits ? nil : monitor.weekly.map { $0.remaining / 100 }, stale: monitor.stale)
            }
            .floatingDragSurface(isFloating)

            if let error = monitor.diskError ?? monitor.readingError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            }

            if monitor.showPacing && !monitor.showCredits {
                VStack(spacing: 9) {
                    pacingRow("Daily pace", value: monitor.pacing?.dailyPace, unit: "percentage points of weekly allowance per day")
                    pacingRow("Today remaining", value: monitor.pacing?.todayRemainingPercent, unit: "percent of today’s budget")
                }
                .padding(.top, 18)
                .floatingDragSurface(isFloating)
            }

            if !monitor.showCredits, let reset = monitor.weekly?.resetDate {
                HStack {
                    Text("Next reset")
                    Spacer()
                    Text(reset, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 20)
                .floatingDragSurface(isFloating)
            }

            if !isFloating {
                Divider().padding(.vertical, 16)
                Toggle("Show credits", isOn: $monitor.showCredits)
                    .toggleStyle(.switch).controlSize(.mini).padding(.bottom, 12)
                if !monitor.showCredits {
                    Toggle("Show pacing", isOn: $monitor.showPacing)
                        .toggleStyle(.switch).controlSize(.mini).padding(.bottom, 12)
                    if monitor.showPacing {
                        Stepper(value: $monitor.reservePercent, in: 0...100) {
                            Text("Reserve \(monitor.reservePercent)%")
                        }
                        .controlSize(.mini).font(.system(size: 11)).padding(.bottom, 12)
                        .help("Weekly allowance to leave unused at reset")
                    }
                }
                Toggle("Floating panel", isOn: Binding(get: { monitor.floating }, set: { _ in toggleFloating() }))
                    .toggleStyle(.switch).controlSize(.mini)
                Toggle("Numbers in menu bar", isOn: $monitor.showNumbers)
                    .toggleStyle(.switch).controlSize(.mini).padding(.top, 12)
                HStack {
                    if monitor.refreshing && monitor.updatedAt == nil {
                        Text("Connecting to Codex…")
                    } else if monitor.stale {
                        Text("Last reading may be out of date")
                    }
                    Spacer()
                    Button("Quit", action: quit).buttonStyle(.plain).keyboardShortcut("q")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 18)
            }
        }
        .padding(22)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private func pacingRow(_ title: String, value: Double?, unit: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—")
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ": " + (value.map {
            $0.formatted(.number.precision(.fractionLength(1))) + " " + unit
        } ?? "unavailable"))
        .help(title == "Daily pace" ? "Percentage points of weekly allowance per day until reset" : "Percent of today’s budget left. Resets at local midnight.")
    }

    private func metric(title: String, symbol: String, value: String, caption: String,
                        fraction: Double?, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .medium, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(stale ? .secondary : .primary)
            Text(stale ? "last reading" : caption).font(.system(size: 10)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(stale ? Color.secondary.opacity(0.35) : accent.opacity(0.8))
                        .frame(width: geometry.size.width * (fraction ?? 0))
                }
            }
            .frame(height: 4).padding(.top, 5)
            .opacity(fraction == nil ? 0 : 1)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
