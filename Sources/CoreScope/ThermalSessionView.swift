import AppKit
import Charts
import SwiftUI

struct ThermalSessionView: View {
    @ObservedObject var session: ThermalSessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Session Control Panel
            sessionControlHeader

            // 2. Main Visualisation & Live Metrics
            if session.samples.isEmpty {
                emptySessionCard
            } else {
                liveChartPanel
                sessionStatisticsPanel
            }
        }
    }

    // MARK: - A. Session Control Header

    private var sessionControlHeader: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    // Status Badge
                    HStack(spacing: 7) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusTitle.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(statusColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12), in: Capsule())

                    // Duration Selector
                    if session.state != .running {
                        HStack(spacing: 6) {
                            Text("DURATION:")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(LiquidGlassStyle.textSecondary)

                            ForEach(ThermalSessionDuration.allCases) { dur in
                                Button {
                                    session.selectedDuration = dur
                                } label: {
                                    Text(dur.title)
                                        .font(.system(size: 11, weight: session.selectedDuration == dur ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(session.selectedDuration == dur ? Color.white : LiquidGlassStyle.textSecondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(
                                            session.selectedDuration == dur
                                                ? LiquidGlassStyle.violetTint.opacity(0.40)
                                                : Color.white.opacity(0.06),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()

                    // Time Counters
                    if session.state == .running || session.state == .completed {
                        HStack(spacing: 14) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("ELAPSED")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                                Text(formatTime(session.elapsedSeconds))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(LiquidGlassStyle.textPrimary)
                            }

                            if let remaining = session.remainingSeconds {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("REMAINING")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                                    Text(formatTime(remaining))
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(LiquidGlassStyle.textPrimary)
                                }
                            }
                        }
                    }

                    // Action Buttons
                    HStack(spacing: 10) {
                        if session.state == .running {
                            Button {
                                session.stopSession()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Stop Session")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(LiquidGlassStyle.coral, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                session.startSession()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(session.state == .completed ? "Start New Session" : "Start Session")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    LinearGradient(
                                        colors: [LiquidGlassStyle.teal, LiquidGlassStyle.emerald],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if !session.samples.isEmpty {
                            Button {
                                session.clearSession()
                            } label: {
                                Text("Clear")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                session.exportCSV()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Export CSV")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(LiquidGlassStyle.textPrimary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(LiquidGlassStyle.violetTint.opacity(0.28), in: Capsule())
                                .overlay(Capsule().strokeBorder(LiquidGlassStyle.violetTint.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let msg = session.exportMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.emerald)
                }
            }
        }
    }

    // MARK: - B. Empty State Card

    private var emptySessionCard: some View {
        GlassCard(cornerRadius: 18, padding: 36) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LiquidGlassStyle.violetTint.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Image(systemName: "waveform.path.badge.plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(LiquidGlassStyle.violetTint)
                }

                VStack(spacing: 6) {
                    Text("Thermal Recording Session")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.textPrimary)

                    Text("Record live hardware die temperatures over time at a disciplined 2.0-second sampling rate. Normal overview monitoring remains purely on-demand.")
                        .font(.system(size: 12))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                HStack(spacing: 20) {
                    metricHint(icon: "flame", title: "Peak & Average", desc: "Live die compute temperatures")
                    metricHint(icon: "shield.checkered", title: "Isolated Calibration", desc: "tcal reference strictly excluded")
                    metricHint(icon: "externaldrive", title: "Memory Only", desc: "Private until optional CSV export")
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    private func metricHint(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LiquidGlassStyle.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlassStyle.textPrimary)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
            }
        }
    }

    // MARK: - C. Swift Charts Live Visualisation

    private var liveChartPanel: some View {
        GlassCard(cornerRadius: 18, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DIE TEMPERATURE TIMELINE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(LiquidGlassStyle.textSecondary)

                        if let lastSample = session.samples.last {
                            HStack(spacing: 12) {
                                if let peak = lastSample.peakDieTemp {
                                    HStack(spacing: 5) {
                                        Circle().fill(LiquidGlassStyle.amber).frame(width: 6, height: 6)
                                        Text("Peak: \(String(format: "%.1f", peak)) °C")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(LiquidGlassStyle.amber)
                                        if let name = lastSample.peakDieSensorName {
                                            Text("(\(name))")
                                                .font(.system(size: 10))
                                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                                        }
                                    }
                                }

                                if let avg = lastSample.averageDieTemp {
                                    HStack(spacing: 5) {
                                        Circle().fill(LiquidGlassStyle.teal).frame(width: 6, height: 6)
                                        Text("Avg: \(String(format: "%.1f", avg)) °C")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(LiquidGlassStyle.teal)
                                    }
                                }
                            }
                        }
                    }

                    Spacer()

                    // Legend
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Capsule().fill(LiquidGlassStyle.amber).frame(width: 14, height: 3)
                            Text("Peak Die")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }

                        HStack(spacing: 5) {
                            Capsule().fill(LiquidGlassStyle.teal).frame(width: 14, height: 3)
                            Text("Average Die")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }
                    }
                }

                // Chart Rendering
                Chart {
                    ForEach(session.samples) { sample in
                        if let avg = sample.averageDieTemp {
                            LineMark(
                                x: .value("Elapsed Time", sample.elapsedSeconds),
                                y: .value("Temperature", avg),
                                series: .value("Series", "Average")
                            )
                            .foregroundStyle(LiquidGlassStyle.teal)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))

                            AreaMark(
                                x: .value("Elapsed Time", sample.elapsedSeconds),
                                yStart: .value("Baseline", yAxisMin),
                                yEnd: .value("Temperature", avg),
                                series: .value("Series", "Average")
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [LiquidGlassStyle.teal.opacity(0.18), LiquidGlassStyle.teal.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)
                        }

                        if let peak = sample.peakDieTemp {
                            LineMark(
                                x: .value("Elapsed Time", sample.elapsedSeconds),
                                y: .value("Temperature", peak),
                                series: .value("Series", "Peak")
                            )
                            .foregroundStyle(LiquidGlassStyle.amber)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }
                    }
                }
                .chartYScale(domain: yAxisMin...yAxisMax)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.12))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel {
                            if let sec = value.as(Double.self) {
                                Text("+\(formatTime(sec))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.12))
                        AxisValueLabel {
                            if let temp = value.as(Double.self) {
                                Text("\(Int(temp))°C")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 220)

                // Compact timeline strip
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)

                    if let latest = session.samples.last {
                        Text("Current Thermal State: \(latest.thermalState)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)

                        Text("•")
                            .foregroundStyle(Color.white.opacity(0.2))

                        Text("Power Mode: \(latest.powerMode.rawValue)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)

                        if let pct = latest.batteryPercent {
                            Text("•")
                                .foregroundStyle(Color.white.opacity(0.2))
                            Text("Battery: \(pct)%")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }
                    }
                    Spacer()
                    Text("\(session.samples.count) samples (2.0s cadence)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiquidGlassStyle.textSecondary.opacity(0.7))
                }
                .padding(.top, 4)
            }
        }
    }

    private var yAxisMin: Double {
        let allVals = session.samples.compactMap { $0.averageDieTemp } + session.samples.compactMap { $0.peakDieTemp }
        guard let m = allVals.min() else { return 30.0 }
        return max(20.0, floor(m / 5.0) * 5.0 - 5.0)
    }

    private var yAxisMax: Double {
        let allVals = session.samples.compactMap { $0.averageDieTemp } + session.samples.compactMap { $0.peakDieTemp }
        guard let m = allVals.max() else { return 85.0 }
        return max(yAxisMin + 15.0, ceil(m / 5.0) * 5.0 + 5.0)
    }

    // MARK: - D. Session Summary Statistics Cards

    private var sessionStatisticsPanel: some View {
        Group {
            if let summary = session.lastSummary ?? ThermalSessionSummary.compute(from: session.samples) {
                HStack(spacing: 12) {
                    statCard(
                        title: "PEAK OBSERVED",
                        value: summary.peakObservedTemp.map { String(format: "%.1f°C", $0) } ?? "—",
                        subtitle: summary.peakObservedSensor ?? "No peak",
                        icon: "flame.fill",
                        accent: LiquidGlassStyle.amber
                    )

                    statCard(
                        title: "AVERAGE OBSERVED",
                        value: summary.averageObservedTemp.map { String(format: "%.1f°C", $0) } ?? "—",
                        subtitle: "Across \(summary.sampleCount) samples",
                        icon: "waveform.path.ecg",
                        accent: LiquidGlassStyle.teal
                    )

                    statCard(
                        title: "MINIMUM OBSERVED",
                        value: summary.minObservedTemp.map { String(format: "%.1f°C", $0) } ?? "—",
                        subtitle: "Die compute baseline",
                        icon: "snowflake",
                        accent: LiquidGlassStyle.emerald
                    )

                    statCard(
                        title: "TOTAL DURATION",
                        value: formatTime(summary.totalDuration),
                        subtitle: "\(summary.sampleCount) samples recorded",
                        icon: "clock.arrow.circlepath",
                        accent: LiquidGlassStyle.violetTint
                    )
                }
            }
        }
    }

    private func statCard(title: String, value: String, subtitle: String, icon: String, accent: Color) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                }
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlassStyle.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private var statusTitle: String {
        switch session.state {
        case .idle:      return "Idle"
        case .running:   return "Recording"
        case .completed: return "Completed"
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .idle:      return LiquidGlassStyle.textSecondary
        case .running:   return LiquidGlassStyle.emerald
        case .completed: return LiquidGlassStyle.violetTint
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
