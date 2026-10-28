import AppKit
import Charts
import SwiftUI

struct ThermalSessionView: View {
    @ObservedObject var session: ThermalSessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch session.state {
            case .idle:
                inactiveSessionView
            case .running:
                runningSessionView
            case .completed:
                completedSessionView
            }
        }
    }

    // MARK: - 1. Inactive View (Simple, Inviting, Clear Sampling Explanation)

    private var inactiveSessionView: some View {
        GlassCard(cornerRadius: 22, padding: 32) {
            VStack(spacing: 22) {
                // Icon & Title
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [LiquidGlassStyle.indigoGlow.opacity(0.35), LiquidGlassStyle.violetTint.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    Image(systemName: "waveform.path.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LiquidGlassStyle.violetTint)
                }

                VStack(spacing: 8) {
                    Text("Thermal Recording Session")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.textPrimary)

                    Text("Record live hardware die temperatures over time at a disciplined 2.0-second interval to observe thermal curves, cooling dynamics, and OS scheduler pressure under sustained workloads.")
                        .font(.system(size: 13))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 580)
                }

                // Zero-Idle Sampling Explanation Callout
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LiquidGlassStyle.teal)

                    Text("Continuous hardware sampling occurs exclusively during an active session. When idle, CoreScope performs zero background polling and consumes zero idle CPU.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LiquidGlassStyle.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LiquidGlassStyle.teal.opacity(0.25), lineWidth: 1))
                .frame(maxWidth: 580)

                // Duration Selection Grid
                VStack(spacing: 10) {
                    Text("SELECT SESSION DURATION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(LiquidGlassStyle.textSecondary)

                    HStack(spacing: 12) {
                        ForEach(ThermalSessionDuration.allCases) { dur in
                            Button {
                                session.selectedDuration = dur
                            } label: {
                                VStack(spacing: 4) {
                                    Text(dur.displayLabel)
                                        .font(.system(size: 13, weight: session.selectedDuration == dur ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(session.selectedDuration == dur ? Color.white : LiquidGlassStyle.textPrimary)

                                    Text(dur.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(session.selectedDuration == dur ? LiquidGlassStyle.teal : LiquidGlassStyle.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .background(
                                    session.selectedDuration == dur
                                        ? LiquidGlassStyle.violetTint.opacity(0.28)
                                        : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            session.selectedDuration == dur
                                                ? LiquidGlassStyle.violetTint.opacity(0.70)
                                                : Color.white.opacity(0.08),
                                            lineWidth: session.selectedDuration == dur ? 1.5 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 580)
                }
                .padding(.top, 4)

                // Prominent Start Button
                Button {
                    session.startSession()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Start Recording Session")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [LiquidGlassStyle.teal, LiquidGlassStyle.emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: LiquidGlassStyle.emerald.opacity(0.35), radius: 12, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                // Capability Badges
                HStack(spacing: 24) {
                    featureBadge(icon: "flame.fill", title: "Validated Die Metrics", desc: "Peak & mean silicon compute channels")
                    featureBadge(icon: "shield.checkered", title: "Isolated Calibration", desc: "tcal references strictly excluded")
                    featureBadge(icon: "lock.shield", title: "Memory-Only Privacy", desc: "Zero telemetry or automatic disk writes")
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func featureBadge(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
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

    // MARK: - 2. Running View (Elapsed, Remaining, Stop Button, Live Metrics, Timeline)

    private var runningSessionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Running Control Bar
            runningControlBar

            // Key Live Metrics Grid
            runningLiveMetricsGrid

            // Live Swift Charts Timeline
            liveChartPanel
        }
    }

    private var runningControlBar: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            HStack(alignment: .center, spacing: 16) {
                // Status Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(LiquidGlassStyle.emerald)
                        .frame(width: 8, height: 8)
                    Text("RECORDING SESSION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(LiquidGlassStyle.emerald)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(LiquidGlassStyle.emerald.opacity(0.14), in: Capsule())

                // Counters
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ELAPSED TIME")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                        Text(formatTime(session.elapsedSeconds))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidGlassStyle.textPrimary)
                    }

                    if let remaining = session.remainingSeconds {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("REMAINING TIME")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                            Text(formatTime(remaining))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(LiquidGlassStyle.textPrimary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DURATION")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                            Text("Manual Stop")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("SAMPLES")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                        Text("\(session.samples.count)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidGlassStyle.teal)
                    }
                }

                Spacer()

                // Visible Prominent Stop Button
                Button {
                    session.stopSession()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Stop Session")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(LiquidGlassStyle.coral, in: Capsule())
                    .shadow(color: LiquidGlassStyle.coral.opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var runningLiveMetricsGrid: some View {
        let latest = session.samples.last

        return HStack(spacing: 12) {
            // 1. Peak Die Temperature
            metricCard(
                title: "PEAK DIE TEMPERATURE",
                value: latest?.peakDieTemp.map { String(format: "%.1f °C", $0) } ?? "Awaiting...",
                subtitle: latest?.peakDieSensorName ?? "Reading PMU sensors",
                icon: "flame.fill",
                accent: LiquidGlassStyle.amber
            )

            // 2. Validated Die Temperature Average
            metricCard(
                title: "DIE AVERAGE",
                value: latest?.averageDieTemp.map { String(format: "%.1f °C", $0) } ?? "Awaiting...",
                subtitle: "Across \(latest?.operatingChannelCount ?? 0) active die channels",
                icon: "waveform.path.ecg",
                accent: LiquidGlassStyle.teal
            )

            // 3. Current Thermal-Pressure State
            metricCard(
                title: "THERMAL PRESSURE",
                value: latest?.thermalPressure.title.uppercased() ?? "NOMINAL",
                subtitle: latest?.thermalPressure.explanation ?? "macOS reports nominal thermal pressure.",
                icon: latest?.thermalPressure.iconName ?? "gauge.with.needle",
                accent: latest?.thermalPressure.badgeColor ?? LiquidGlassStyle.emerald
            )

            // 4. Power Source & Battery
            metricCard(
                title: "POWER SOURCE",
                value: powerDisplayValue(for: latest),
                subtitle: powerSubtitleValue(for: latest),
                icon: powerIcon(for: latest),
                accent: LiquidGlassStyle.violetTint
            )
        }
    }

    // MARK: - 3. Completed View (Summary, Clear, Explicit CSV Export, Timeline)

    private var completedSessionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Completed Control Bar
            completedControlBar

            // Summary Statistics 4-Card Grid
            completedSummaryGrid

            // Detailed Diagnostics Strip
            completedDiagnosticsPanel

            // Full Timeline Chart
            liveChartPanel
        }
    }

    private var completedControlBar: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    // Status Badge
                    HStack(spacing: 7) {
                        Circle()
                            .fill(LiquidGlassStyle.violetTint)
                            .frame(width: 8, height: 8)
                        Text("SESSION COMPLETED")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(LiquidGlassStyle.violetTint)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(LiquidGlassStyle.violetTint.opacity(0.14), in: Capsule())

                    // Duration and Sample Counts
                    if let summary = session.lastSummary ?? ThermalSessionSummary.compute(from: session.samples) {
                        HStack(spacing: 16) {
                            Text("Duration: \(formatTime(summary.totalDuration))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LiquidGlassStyle.textPrimary)

                            Text("•")
                                .foregroundStyle(Color.white.opacity(0.25))

                            Text("\(summary.sampleCount) samples captured")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }
                    }

                    Spacer()

                    // Action Buttons: Clear, Start New, Export CSV
                    HStack(spacing: 10) {
                        Button {
                            session.clearSession()
                        } label: {
                            Text("Clear Session")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            session.clearSession()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .bold))
                                Text("New Session")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(LiquidGlassStyle.textPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(LiquidGlassStyle.violetTint.opacity(0.20), in: Capsule())
                            .overlay(Capsule().strokeBorder(LiquidGlassStyle.violetTint.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            session.exportCSV()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Export CSV")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [LiquidGlassStyle.teal, LiquidGlassStyle.emerald],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: LiquidGlassStyle.emerald.opacity(0.3), radius: 8, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let msg = session.exportMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(LiquidGlassStyle.emerald)
                        Text(msg)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlassStyle.emerald)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var completedSummaryGrid: some View {
        let summary = session.lastSummary ?? ThermalSessionSummary.compute(from: session.samples)

        return HStack(spacing: 12) {
            metricCard(
                title: "PEAK OBSERVED",
                value: summary?.peakObservedTemp.map { String(format: "%.1f °C", $0) } ?? "—",
                subtitle: summary?.peakObservedSensor ?? "No peak channel",
                icon: "flame.fill",
                accent: LiquidGlassStyle.amber
            )

            metricCard(
                title: "AVERAGE OBSERVED",
                value: summary?.averageObservedTemp.map { String(format: "%.1f °C", $0) } ?? "—",
                subtitle: "Across \(summary?.sampleCount ?? 0) samples",
                icon: "waveform.path.ecg",
                accent: LiquidGlassStyle.teal
            )

            metricCard(
                title: "MINIMUM OBSERVED",
                value: summary?.minObservedTemp.map { String(format: "%.1f °C", $0) } ?? "—",
                subtitle: "Die compute baseline",
                icon: "snowflake",
                accent: LiquidGlassStyle.emerald
            )

            metricCard(
                title: "RECORDED DURATION",
                value: summary != nil ? formatTime(summary!.totalDuration) : "00:00",
                subtitle: "\(summary?.sampleCount ?? 0) samples (2.0s cadence)",
                icon: "clock.arrow.circlepath",
                accent: LiquidGlassStyle.violetTint
            )
        }
    }

    private var completedDiagnosticsPanel: some View {
        let summary = session.lastSummary ?? ThermalSessionSummary.compute(from: session.samples)

        return GlassCard(cornerRadius: 16, padding: 14) {
            HStack(spacing: 20) {
                diagnosticItem(
                    label: "INITIAL → FINAL DIE TEMP",
                    value: tempDeltaText(initial: summary?.initialTemp, final: summary?.finalTemp),
                    icon: "arrow.right"
                )

                Divider().opacity(0.15).frame(height: 28)

                diagnosticItem(
                    label: "THERMAL STATE TRANSITIONS",
                    value: "\(summary?.thermalStateTransitions ?? 0) changes observed",
                    icon: "arrow.triangle.swap"
                )

                Divider().opacity(0.15).frame(height: 28)

                diagnosticItem(
                    label: "ELEVATED PRESSURE SAMPLES",
                    value: "\(summary?.highThermalPressureCount ?? 0) samples",
                    icon: "exclamationmark.triangle"
                )

                Divider().opacity(0.15).frame(height: 28)

                diagnosticItem(
                    label: "DATA STORAGE",
                    value: "Kept in memory only",
                    icon: "memorychip"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnosticItem(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlassStyle.textPrimary)
        }
    }

    private func tempDeltaText(initial: Double?, final: Double?) -> String {
        guard let i = initial, let f = final else { return "—" }
        let diff = f - i
        let sign = diff >= 0 ? "+" : ""
        return String(format: "%.1f°C → %.1f°C (%@%.1f°C)", i, f, sign, diff)
    }

    // MARK: - 4. Swift Charts Live & Completed Timeline Panel

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

                // Compact timeline footer
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)

                    if let latest = session.samples.last {
                        Text("Current Thermal State: \(latest.thermalPressure.title)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)

                        Text("•")
                            .foregroundStyle(Color.white.opacity(0.2))

                        Text("Power: \(latest.powerMode.rawValue)")
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

    // MARK: - Reusable UI Components

    private func metricCard(title: String, value: String, subtitle: String, icon: String, accent: Color) -> some View {
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
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlassStyle.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func powerDisplayValue(for sample: ThermalSample?) -> String {
        guard let s = sample else { return "Unknown" }
        if let pct = s.batteryPercent {
            return "\(s.powerMode == .battery ? "Battery" : "AC") (\(pct)%)"
        }
        return s.powerMode.rawValue
    }

    private func powerSubtitleValue(for sample: ThermalSample?) -> String {
        guard let s = sample else { return "Hardware status unavailable" }
        if s.powerMode == .battery {
            return "Operating on battery power"
        } else if s.isCharging == true {
            return "Connected and charging"
        } else if s.isCharging == false {
            return "Connected, not charging"
        }
        return "External power connected"
    }

    private func powerIcon(for sample: ThermalSample?) -> String {
        guard let s = sample else { return "bolt.fill" }
        if s.powerMode == .battery {
            guard let pct = s.batteryPercent else { return "battery.75" }
            if pct > 75 { return "battery.100" }
            if pct > 45 { return "battery.75" }
            if pct > 20 { return "battery.50" }
            return "battery.25"
        }
        return "bolt.fill"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
