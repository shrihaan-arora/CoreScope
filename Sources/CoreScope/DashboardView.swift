import SwiftUI

struct DashboardView: View {
    @StateObject private var model: DashboardModel
    @State private var selectedCategory: String
    @State private var searchText: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DashboardModel = DashboardModel(), initialCategory: String = "All") {
        _model = StateObject(wrappedValue: model)
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    thermalOverview
                    powerAndBatteryPanel
                    sensorExplorer
                    diagnosticsSection
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 1140, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if model.snapshot == nil {
                model.refresh()
            }
        }
    }

    // MARK: - A. Compact Application Header

    private var header: some View {
        HStack(spacing: 14) {
            // Liquid-glass icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LiquidGlassStyle.teal, LiquidGlassStyle.emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 40, height: 40)
            .shadow(color: LiquidGlassStyle.teal.opacity(0.3), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("CoreScope")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    StatusIndicator(
                        title: "ON-DEMAND",
                        subtitle: nil,
                        icon: nil,
                        color: LiquidGlassStyle.emerald
                    )
                }

                Text("APPLE SILICON HARDWARE OBSERVABILITY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            // Last scan timestamp
            if let sampledAt = model.snapshot?.sampledAt {
                Text("Last scan: \(sampledAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }

            // Prominent native Refresh button
            Button {
                model.refresh()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(model.isRefreshing && !reduceMotion ? 180 : 0))
                        .animation(
                            model.isRefreshing && !reduceMotion
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: model.isRefreshing
                        )
                    Text(model.isRefreshing ? "Scanning…" : "Refresh")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("Execute one hardware scan. Zero continuous background polling.")
        }
        .padding(.vertical, 2)
    }

    // MARK: - B. Thermal Overview

    private var thermalOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "THERMAL OVERVIEW",
                subtitle: model.snapshot?.temperatureStatus.explanation ?? "Genuine die temperatures direct from Apple PMU nodes"
            )

            if let snapshot = model.snapshot {
                let summary = snapshot.temperatureSummary

                HStack(spacing: 12) {
                    TemperatureMetricCard(
                        title: "PEAK DIE SENSOR",
                        value: summary.peakDieReading.map { String(format: "%.1f", $0.temperatureC) } ?? "Unavailable",
                        unit: summary.peakDieReading != nil ? "°C" : "",
                        subtitle: summary.peakDieReading?.sensorName ?? "No active die sensors",
                        accent: summary.peakDieReading.map { LiquidGlassStyle.tempColor(for: $0.temperatureC) } ?? .secondary,
                        icon: "thermometer.sun.fill"
                    )

                    TemperatureMetricCard(
                        title: "DIE SENSOR AVERAGE",
                        value: summary.dieAverageC.map { String(format: "%.1f", $0) } ?? "Unavailable",
                        unit: summary.dieAverageC != nil ? "°C" : "",
                        subtitle: summary.dieSensorCount > 0
                            ? "\(summary.dieSensorCount) active die channels (excludes device/ref)"
                            : "No active die channels",
                        accent: summary.dieAverageC.map { LiquidGlassStyle.tempColor(for: $0) } ?? .secondary,
                        icon: "chart.bar.xaxis"
                    )

                    TemperatureMetricCard(
                        title: "OPERATING CHANNELS",
                        value: "\(summary.operatingSensorCount)",
                        unit: "",
                        subtitle: summary.calibrationSensorCount > 0
                            ? "Apple PMU · \(summary.calibrationSensorCount) reference isolated (tcal)"
                            : "Apple PMU (0xFF00:5)",
                        accent: LiquidGlassStyle.teal,
                        icon: "cpu.fill"
                    )
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Reading Apple Silicon PMU sensors…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    Spacer()
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    // MARK: - C. Power and Battery Panel

    private var powerAndBatteryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            PowerStatusCard(snapshot: model.snapshot)
        }
    }

    // MARK: - D. Sensor Explorer

    private var sensorExplorer: some View {
        VStack(alignment: .leading, spacing: 12) {
            let readings = model.snapshot?.temperatureReadings ?? []
            let filtered = filteredReadings(readings)

            HStack(alignment: .firstTextBaseline) {
                sectionHeader(
                    title: "SENSOR EXPLORER",
                    subtitle: "\(filtered.count) of \(readings.count) channels"
                )
                Spacer()
            }

            // Controls row: Category filter capsules & search bar
            HStack(spacing: 10) {
                categoryFilterTabs(readings: readings)
                Spacer(minLength: 8)
                searchField
            }

            // Informative notice when Calibration / Reference category is selected
            if selectedCategory == SensorCategory.calibration.rawValue {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(LiquidGlassStyle.violet)
                    Text("Channels labeled 'tcal' by Apple PMU firmware are classified as Calibration / Reference and are isolated from operating die averages.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiquidGlassStyle.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LiquidGlassStyle.violet.opacity(0.20), lineWidth: 1))
            }

            // Filtered sensor cards grid
            if filtered.isEmpty {
                GlassCard(cornerRadius: 16, padding: 28) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
                            Text("No sensors match \"\(searchText)\" in category \"\(selectedCategory)\"")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 230, maximum: 380), spacing: 10)
                ]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filtered) { reading in
                        SensorCard(reading: reading)
                    }
                }
            }
        }
    }

    private func categoryFilterTabs(readings: [TemperatureReading]) -> some View {
        let presentCategories = SensorCategory.allCases.filter { cat in
            readings.contains(where: { $0.category == cat })
        }
        let allOptions: [String] = ["All"] + presentCategories.map(\.rawValue)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allOptions, id: \.self) { catName in
                    let count = catName == "All"
                        ? readings.count
                        : readings.filter { $0.category.rawValue == catName }.count

                    Button {
                        selectedCategory = catName
                    } label: {
                        HStack(spacing: 5) {
                            Text(catName)
                                .fontWeight(selectedCategory == catName ? .semibold : .medium)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(selectedCategory == catName ? Color.black.opacity(0.18) : Color.primary.opacity(0.06))
                                )
                        }
                        .font(.system(size: 11, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                selectedCategory == catName
                                    ? AnyShapeStyle(LinearGradient(colors: [LiquidGlassStyle.teal, LiquidGlassStyle.emerald], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(.ultraThinMaterial)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                selectedCategory == catName
                                    ? Color.white.opacity(0.25)
                                    : Color.primary.opacity(0.06),
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(selectedCategory == catName ? Color.black : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter sensors…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 140)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func filteredReadings(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        readings.filter { reading in
            let matchesCategory = selectedCategory == "All" || reading.category.rawValue == selectedCategory
            let matchesSearch = searchText.isEmpty || reading.sensorName.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    // MARK: - E. Diagnostics

    private var diagnosticsSection: some View {
        DiagnosticsSection(snapshot: model.snapshot)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(LiquidGlassStyle.emerald)
            Text("LOCAL OBSERVABILITY · ZERO NETWORK CALLS · ON-DEMAND READS · TERMINATES ON CLOSE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Spacer()
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Diagnostics Section Component

struct DiagnosticsSection: View {
    let snapshot: SensorSnapshot?
    @State private var isExpanded: Bool = false

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 16) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().opacity(0.12).padding(.top, 6)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        diagRow(label: "Silicon Platform", value: SystemInfo.chipName)
                        diagRow(label: "Hardware Model", value: SystemInfo.modelIdentifier)
                        diagRow(label: "Compute Cores", value: "\(SystemInfo.activeCores) active cores")
                        diagRow(label: "Operating System", value: SystemInfo.osVersion)
                        diagRow(label: "Thermal Protocol", value: "IOHIDEventSystemClient (0xFF00:5)")
                        diagRow(label: "Power Protocol", value: "IOPowerSources (IOKit.ps)")
                        diagRow(label: "Sensor Outcome", value: snapshot?.temperatureStatus.explanation ?? "Awaiting scan")
                        diagRow(label: "Resource Policy", value: "Stateless on-demand scan; client released on exit")
                    }
                    .padding(.top, 4)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidGlassStyle.teal)
                    Text("SYSTEM & PROBE DIAGNOSTICS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(SystemInfo.chipName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.teal)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(LiquidGlassStyle.teal.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func diagRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
