import SwiftUI

// MARK: - Dashboard Navigation Section

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case thermalSession = "Thermal Session"
    case sensors = "Sensors"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.medium"
        case .thermalSession: return "waveform.path.ecg"
        case .sensors: return "cpu"
        }
    }
}

// MARK: - Main Dashboard View

struct DashboardView: View {
    @StateObject private var model: DashboardModel
    @State private var selectedSection: DashboardSection
    @State private var selectedCategory: String
    @State private var searchText: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: DashboardModel = DashboardModel(),
        initialSection: DashboardSection = .overview,
        initialCategory: String = "All"
    ) {
        _model = StateObject(wrappedValue: model)
        _selectedSection = State(initialValue: initialSection)
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    navigationBar

                    switch selectedSection {
                    case .overview:
                        overviewSection
                    case .thermalSession:
                        thermalSessionSection
                    case .sensors:
                        sensorsSection
                    }

                    footer
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 1160, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if model.snapshot == nil {
                model.refresh()
            }
        }
    }

    // MARK: - A. Persistent Header

    private var header: some View {
        HStack(spacing: 14) {
            // App Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LiquidGlassStyle.teal, LiquidGlassStyle.indigoGlow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: LiquidGlassStyle.indigoGlow.opacity(0.4), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("CoreScope")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.textPrimary)

                    if model.session.state == .running {
                        StatusIndicator(
                            title: "SESSION ACTIVE",
                            subtitle: "\(String(format: "%.0f", model.session.elapsedSeconds))s",
                            icon: "record.circle",
                            color: LiquidGlassStyle.emerald
                        )
                    } else {
                        StatusIndicator(
                            title: "ON-DEMAND",
                            subtitle: nil,
                            icon: nil,
                            color: LiquidGlassStyle.teal
                        )
                    }
                }

                Text("APPLE SILICON HARDWARE OBSERVABILITY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
            }

            Spacer(minLength: 16)

            // Last scan timestamp
            if let sampledAt = model.snapshot?.sampledAt {
                Text("Last scan: \(sampledAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                    .padding(.horizontal, 8)
            }

            // Native Refresh button
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
                .foregroundStyle(LiquidGlassStyle.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), LiquidGlassStyle.violetTint.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing || model.session.isSamplingInProgress)
            .help("Execute one hardware scan. Zero continuous background polling.")
        }
        .padding(.vertical, 2)
    }

    // MARK: - B. Navigation Bar (Segmented Control)

    private var navigationBar: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(DashboardSection.allCases) { section in
                    let isSelected = selectedSection == section
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.icon)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            Text(section.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                        }
                        .foregroundStyle(isSelected ? LiquidGlassStyle.textPrimary : LiquidGlassStyle.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            isSelected
                                ? AnyShapeStyle(LiquidGlassStyle.violetTint.opacity(0.35))
                                : AnyShapeStyle(Color.clear)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            isSelected
                                ? Capsule().strokeBorder(LiquidGlassStyle.violetTint.opacity(0.6), lineWidth: 1)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

            Spacer()

            // Contextual quick summary
            if selectedSection == .overview, let summary = model.snapshot?.temperatureSummary {
                HStack(spacing: 12) {
                    if let peak = summary.peakDieReading {
                        HStack(spacing: 4) {
                            Circle().fill(LiquidGlassStyle.tempColor(for: peak.temperatureC)).frame(width: 6, height: 6)
                            Text("Peak: \(String(format: "%.1f°C", peak.temperatureC))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textPrimary)
                        }
                    }
                    if let avg = summary.dieAverageC {
                        HStack(spacing: 4) {
                            Circle().fill(LiquidGlassStyle.teal).frame(width: 6, height: 6)
                            Text("Die Avg: \(String(format: "%.1f°C", avg))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textPrimary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    // MARK: - C. Section 1: Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            thermalOverview
            powerAndBatteryPanel
            diagnosticsSection
        }
    }

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
                        accent: summary.peakDieReading.map { LiquidGlassStyle.tempColor(for: $0.temperatureC) } ?? LiquidGlassStyle.textSecondary,
                        icon: "thermometer.sun.fill"
                    )

                    TemperatureMetricCard(
                        title: "DIE SENSOR AVERAGE",
                        value: summary.dieAverageC.map { String(format: "%.1f", $0) } ?? "Unavailable",
                        unit: summary.dieAverageC != nil ? "°C" : "",
                        subtitle: summary.dieSensorCount > 0
                            ? "\(summary.dieSensorCount) active die channels (excludes device/ref)"
                            : "No active die channels",
                        accent: summary.dieAverageC.map { LiquidGlassStyle.tempColor(for: $0) } ?? LiquidGlassStyle.textSecondary,
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
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                    }
                    .padding(32)
                    Spacer()
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var powerAndBatteryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            PowerStatusCard(snapshot: model.snapshot)
        }
    }

    private var diagnosticsSection: some View {
        DiagnosticsSection(snapshot: model.snapshot)
    }

    // MARK: - D. Section 2: Thermal Session

    private var thermalSessionSection: some View {
        ThermalSessionView(session: model.session)
    }

    // MARK: - E. Section 3: Sensor Explorer

    private var sensorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            let readings = model.snapshot?.temperatureReadings ?? []
            let filtered = filteredReadings(readings)

            HStack(alignment: .firstTextBaseline) {
                sectionHeader(
                    title: "SENSOR EXPLORER",
                    subtitle: "\(filtered.count) of \(readings.count) channels"
                )
                Spacer()
            }

            // Filter Tabs & Search Field
            HStack(spacing: 10) {
                categoryFilterTabs(readings: readings)
                Spacer(minLength: 8)
                searchField
            }

            // Notice for Calibration / Reference
            if selectedCategory == SensorCategory.calibration.rawValue {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(LiquidGlassStyle.violetTint)
                    Text("Channels labeled 'tcal' by Apple PMU firmware are classified as Calibration / Reference and are isolated from operating die averages.")
                        .font(.system(size: 11))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiquidGlassStyle.violetTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LiquidGlassStyle.violetTint.opacity(0.25), lineWidth: 1))
            }

            // Sensor Cards Grid
            if filtered.isEmpty {
                GlassCard(cornerRadius: 16, padding: 28) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                            Text("No sensors match \"\(searchText)\" in category \"\(selectedCategory)\"")
                                .font(.system(size: 12))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
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
                                    Capsule().fill(selectedCategory == catName ? Color.black.opacity(0.25) : Color.white.opacity(0.06))
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
                                    ? Color.white.opacity(0.3)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(selectedCategory == catName ? Color.black : LiquidGlassStyle.textPrimary)
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
                .foregroundStyle(LiquidGlassStyle.textSecondary)
            TextField("Filter sensors…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(LiquidGlassStyle.textPrimary)
                .frame(width: 140)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LiquidGlassStyle.violetTint.opacity(0.2), lineWidth: 1))
    }

    private func filteredReadings(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        readings.filter { reading in
            let matchesCategory = selectedCategory == "All" || reading.category.rawValue == selectedCategory
            let matchesSearch = searchText.isEmpty || reading.sensorName.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
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
                .foregroundStyle(LiquidGlassStyle.textSecondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(LiquidGlassStyle.textSecondary)
            Spacer()
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(LiquidGlassStyle.textSecondary)
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
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
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
                .foregroundStyle(LiquidGlassStyle.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlassStyle.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
