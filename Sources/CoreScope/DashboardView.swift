import SwiftUI

private enum CoreScopeStyle {
    static let accent = Color(red: 0.39, green: 0.48, blue: 0.98)
    static let mint = Color(red: 0.25, green: 0.78, blue: 0.65)
    static let violet = Color(red: 0.63, green: 0.48, blue: 0.96)
    static let amber = Color(red: 0.97, green: 0.68, blue: 0.27)
    static let coral = Color(red: 0.95, green: 0.36, blue: 0.36)

    static func tempColor(for tempC: Double) -> Color {
        if tempC < 45.0 {
            return mint
        } else if tempC < 65.0 {
            return accent
        } else if tempC < 80.0 {
            return amber
        } else {
            return coral
        }
    }
}

struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @State private var selectedCategory: String = "All"
    @State private var searchText: String = ""

    var body: some View {
        ZStack {
            Color.primary.opacity(0.025).ignoresSafeArea()
            ambientGlow

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    hero
                    temperatureSection
                    systemStatusGrid
                    privacyFooter
                }
                .padding(28)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task { model.refresh() }
    }

    private var ambientGlow: some View {
        GeometryReader { proxy in
            Circle()
                .fill(CoreScopeStyle.accent.opacity(0.08))
                .frame(width: 460, height: 460)
                .blur(radius: 90)
                .position(x: proxy.size.width * 0.84, y: 24)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(
                        colors: [CoreScopeStyle.accent, CoreScopeStyle.violet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("CoreScope")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("APPLE SILICON · NATIVE HARDWARE TELEMETRY")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            HStack(spacing: 7) {
                Circle().fill(CoreScopeStyle.mint).frame(width: 7, height: 7)
                Text("ON-DEMAND")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))

            Button {
                model.refresh()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
                    Text(model.isRefreshing ? "Scanning…" : "Refresh")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("Take one new reading. No background daemon or continuous polling.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 11) {
                Text("LOCAL HARDWARE MONITOR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(CoreScopeStyle.accent)

                Text("Genuine Silicon Telemetry\nDirect from PMU Nodes.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Independent Apple Silicon temperature probe. Zero external dependencies. Zero fake data.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text("POWER TELEMETRY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: powerIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(powerColor)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(model.snapshot?.powerMode.rawValue ?? "Reading power state")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(powerSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07)))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Temperature Section

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("THERMAL SENSORS", subtitle: temperatureSectionSubtitle)

            if let snapshot = model.snapshot {
                if snapshot.temperatureReadings.isEmpty {
                    TemperatureUnavailableCard(explanation: snapshot.temperatureStatus.explanation)
                } else {
                    let readings = snapshot.temperatureReadings
                    let maxTemp = readings.map(\.temperatureC).max() ?? 0
                    let avgTemp = readings.reduce(0.0) { $0 + $1.temperatureC } / Double(max(1, readings.count))

                    // Summary metric cards
                    HStack(spacing: 14) {
                        SummaryMetricChip(
                            title: "PEAK SENSOR TEMP",
                            value: String(format: "%.1f °C", maxTemp),
                            subtitle: peakSensorName(in: readings, peak: maxTemp),
                            accent: CoreScopeStyle.tempColor(for: maxTemp)
                        )

                        SummaryMetricChip(
                            title: "DIE AVERAGE",
                            value: String(format: "%.1f °C", avgTemp),
                            subtitle: "\(readings.count) active PMU channels",
                            accent: CoreScopeStyle.tempColor(for: avgTemp)
                        )

                        SummaryMetricChip(
                            title: "TELEMETRY SOURCE",
                            value: "Apple PMU",
                            subtitle: "IOHIDEventServices (0xFF00:5)",
                            accent: CoreScopeStyle.mint
                        )
                    }

                    // Category filter bar & Search
                    HStack(spacing: 10) {
                        categoryFilterTabs(readings: readings)
                        Spacer()
                        searchBar
                    }

                    // Filtered readings grid
                    let filtered = filteredReadings(readings)

                    if filtered.isEmpty {
                        HStack {
                            Spacer()
                            Text("No sensors match \"\(searchText)\" in category \"\(selectedCategory)\"")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(24)
                            Spacer()
                        }
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        let columns = [
                            GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12)
                        ]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered) { reading in
                                SensorPillCard(reading: reading)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Querying Apple Silicon HID thermal subsystem…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    Spacer()
                }
            }
        }
    }

    private func peakSensorName(in readings: [TemperatureReading], peak: Double) -> String {
        if let match = readings.first(where: { abs($0.temperatureC - peak) < 0.01 }) {
            return match.sensorName
        }
        return "Peak channel"
    }

    private func categoryFilterTabs(readings: [TemperatureReading]) -> some View {
        let categories = ["All"] + Array(Set(readings.map(\.category))).sorted()

        return HStack(spacing: 6) {
            ForEach(categories, id: \.self) { cat in
                let count = cat == "All" ? readings.count : readings.filter { $0.category == cat }.count
                Button {
                    selectedCategory = cat
                } label: {
                    HStack(spacing: 5) {
                        Text(cat)
                            .fontWeight(selectedCategory == cat ? .semibold : .regular)
                        Text("\(count)")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(selectedCategory == cat ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                            )
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(selectedCategory == cat ? CoreScopeStyle.accent : Color.primary.opacity(0.04))
                    )
                    .foregroundStyle(selectedCategory == cat ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchBar: some View {
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func filteredReadings(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        readings.filter { reading in
            let matchesCategory = selectedCategory == "All" || reading.category == selectedCategory
            let matchesSearch = searchText.isEmpty || reading.sensorName.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    private var temperatureSectionSubtitle: String {
        guard let snapshot = model.snapshot else {
            return model.isRefreshing
                ? "Querying IOHIDEventSystemClient…"
                : "Genuine die temperature · no estimates"
        }
        return snapshot.temperatureStatus.explanation
    }

    // MARK: - System Status

    private var systemStatusGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("SYSTEM STATUS", subtitle: "Collected only when you open or refresh")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                StatusCard(
                    title: "THERMAL PRESSURE",
                    icon: "thermometer.medium",
                    value: model.snapshot?.thermalState ?? (model.isRefreshing ? "Checking…" : "Not read yet"),
                    detail: thermalDetail,
                    accent: thermalColor
                )

                StatusCard(
                    title: "BATTERY",
                    icon: "battery.75percent",
                    value: batteryHeadline,
                    detail: batteryDetail,
                    accent: CoreScopeStyle.mint
                )
            }
        }
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color.primary.opacity(0.07))
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(CoreScopeStyle.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOCAL BY DESIGN")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.0)
                    Text("No analytics · No network access · No daemons · No background polling · Direct read-only IOKit calls")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(sensorStatusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sampledAt = model.snapshot?.sampledAt {
                        Text("Last scan: \(sampledAt.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
        }
    }

    // MARK: - Helpers

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
            Spacer()
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var sensorStatusText: String {
        guard let snapshot = model.snapshot else {
            return model.isRefreshing
                ? "Reading hardware sensors in the background thread…"
                : "Open the dashboard to take a reading."
        }
        return snapshot.temperatureStatus.explanation
    }

    private var powerIcon: String {
        switch model.snapshot?.powerMode {
        case .external: "powerplug.fill"
        case .battery: "battery.100percent"
        case .unknown, .none: "bolt.slash"
        }
    }

    private var powerColor: Color {
        switch model.snapshot?.powerMode {
        case .external: CoreScopeStyle.mint
        case .battery: CoreScopeStyle.accent
        case .unknown, .none: .secondary
        }
    }

    private var powerSubtitle: String {
        guard let snapshot = model.snapshot else { return "Waiting for first scan" }
        if snapshot.powerMode == .external {
            if snapshot.isCharging == true { return "Adapter connected · battery charging" }
            if snapshot.isCharging == false {
                if snapshot.isAdapterConnected == true {
                    return "Adapter connected · not charging (charge hold or full)"
                }
                return "Adapter connected · not charging"
            }
            return "System is drawing external power"
        }
        if snapshot.powerMode == .battery {
            if snapshot.isAdapterConnected == true {
                return "Adapter present · drawing battery power"
            }
            return "System is drawing battery power"
        }
        return "Could not determine the active source"
    }

    private var batteryHeadline: String {
        guard let percent = model.snapshot?.batteryPercent else {
            return model.isRefreshing ? "Reading…" : "Unavailable"
        }
        return "\(percent)%"
    }

    private var batteryDetail: String {
        guard let snapshot = model.snapshot else { return "Battery details appear after the first scan" }
        if snapshot.isCharging == true { return "Charging from external power" }
        if snapshot.isCharging == false && snapshot.powerMode == .external {
            return "Connected to power · charge on hold or complete"
        }
        if snapshot.powerMode == .battery { return "Running on battery" }
        return "Charging state not reported"
    }

    private var thermalDetail: String {
        switch model.snapshot?.thermalState {
        case "Nominal": "No elevated thermal pressure reported"
        case "Fair": "Some thermal pressure reported by macOS"
        case "Serious": "High thermal pressure reported by macOS"
        case "Critical": "Critical thermal pressure reported by macOS"
        case .none: "Read from ProcessInfo thermal state"
        default: "Thermal state reported by macOS"
        }
    }

    private var thermalColor: Color {
        switch model.snapshot?.thermalState {
        case "Nominal": CoreScopeStyle.mint
        case "Fair": CoreScopeStyle.amber
        case "Serious", "Critical": CoreScopeStyle.coral
        default: CoreScopeStyle.accent
        }
    }
}

// MARK: - Summary Metric Chip

private struct SummaryMetricChip: View {
    let title: String
    let value: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// MARK: - Sensor Pill Card

private struct SensorPillCard: View {
    let reading: TemperatureReading

    private var tempColor: Color {
        CoreScopeStyle.tempColor(for: reading.temperatureC)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Temperature badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tempColor.opacity(0.12))
                VStack(spacing: 1) {
                    Text(String(format: "%.1f", reading.temperatureC))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(tempColor)
                    Text("°C")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(tempColor.opacity(0.8))
                }
            }
            .frame(width: 54, height: 44)

            // Sensor information
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.sensorName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(reading.category)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3, height: 3)

                    // Temperature level bar (0 to 100°C)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(tempColor)
                                .frame(width: max(4, min(geo.size.width, geo.size.width * CGFloat(reading.temperatureC / 100.0))))
                        }
                    }
                    .frame(width: 48, height: 4)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }
}

// MARK: - Temperature Unavailable Card

private struct TemperatureUnavailableCard: View {
    let explanation: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(CoreScopeStyle.amber.opacity(0.13))
                Image(systemName: "thermometer.medium.slash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CoreScopeStyle.amber)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text("TEMPERATURE SENSORS UNAVAILABLE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("CoreScope does not estimate or fabricate temperature values.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(CoreScopeStyle.amber.opacity(0.25)))
    }
}

// MARK: - Status Card

private struct StatusCard: View {
    let title: String
    let icon: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accent.opacity(0.13))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.07)))
    }
}
