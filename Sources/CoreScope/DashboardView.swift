import SwiftUI

private enum CoreScopeStyle {
    static let accent = Color(red: 0.39, green: 0.48, blue: 0.98)
    static let mint = Color(red: 0.25, green: 0.78, blue: 0.65)
    static let violet = Color(red: 0.63, green: 0.48, blue: 0.96)
    static let amber = Color(red: 0.97, green: 0.68, blue: 0.27)
    static let coral = Color(red: 0.95, green: 0.36, blue: 0.36)
    static let slate = Color(red: 0.55, green: 0.60, blue: 0.68)

    static func tempColor(for tempC: Double, isCalibration: Bool = false) -> Color {
        if isCalibration {
            return violet
        }
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
            // Adaptive background supporting both Light and Dark macOS modes
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
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
                .fill(CoreScopeStyle.accent.opacity(0.06))
                .frame(width: 480, height: 480)
                .blur(radius: 100)
                .position(x: proxy.size.width * 0.85, y: 30)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [CoreScopeStyle.accent, CoreScopeStyle.violet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("CoreScope")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("APPLE SILICON · NATIVE HARDWARE TELEMETRY")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 7) {
                Circle().fill(CoreScopeStyle.mint).frame(width: 7, height: 7)
                Text("ON-DEMAND")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))

            Button {
                model.refresh()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
                        .animation(model.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
                    Text(model.isRefreshing ? "Scanning…" : "Refresh")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("Execute one hardware scan. Zero continuous background polling.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("LOCAL HARDWARE MONITOR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(CoreScopeStyle.accent)

                Text("Genuine Silicon Telemetry\nDirect from PMU Nodes.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Independent Apple Silicon thermal and power probe. Zero external dependencies. Zero fake values.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text("ACTIVE POWER SOURCE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: powerIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(powerColor)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(powerHeadline)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(powerSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    let summary = snapshot.temperatureSummary

                    // Summary metric cards — with honest labels and calibrated die-only calculations
                    HStack(spacing: 14) {
                        SummaryMetricChip(
                            title: "PEAK DIE SENSOR",
                            value: summary.peakDieReading.map { String(format: "%.1f °C", $0.temperatureC) } ?? "Unavailable",
                            subtitle: summary.peakDieReading?.sensorName ?? "No active die sensors",
                            accent: summary.peakDieReading.map { CoreScopeStyle.tempColor(for: $0.temperatureC) } ?? .secondary
                        )

                        SummaryMetricChip(
                            title: "DIE SENSOR AVERAGE",
                            value: summary.formattedDieAverage,
                            subtitle: summary.dieSensorCount > 0
                                ? "\(summary.dieSensorCount) active die channels (excludes device/ref)"
                                : "No active die channels",
                            accent: summary.dieAverageC.map { CoreScopeStyle.tempColor(for: $0) } ?? .secondary
                        )

                        SummaryMetricChip(
                            title: "OPERATING CHANNELS",
                            value: "\(summary.operatingSensorCount)",
                            subtitle: summary.calibrationSensorCount > 0
                                ? "Apple PMU · \(summary.calibrationSensorCount) reference isolated"
                                : "Apple PMU (0xFF00:5)",
                            accent: CoreScopeStyle.mint
                        )
                    }

                    // Category filter tabs & Search
                    HStack(spacing: 10) {
                        categoryFilterTabs(readings: readings)
                        Spacer()
                        searchBar
                    }

                    // Special informative notice when viewing Calibration / Reference sensors
                    if selectedCategory == SensorCategory.calibration.rawValue {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(CoreScopeStyle.violet)
                            Text("Channels labeled 'tcal' by Apple PMU firmware are classified as Calibration / Reference and are isolated from operating die averages.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CoreScopeStyle.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Filtered readings grid
                    let filtered = filteredReadings(readings)

                    if filtered.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.tertiary)
                                Text("No sensors match \"\(searchText)\" in category \"\(selectedCategory)\"")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(32)
                            Spacer()
                        }
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
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

    private func categoryFilterTabs(readings: [TemperatureReading]) -> some View {
        let presentCategories = Array(Set(readings.map(\.category))).sorted()
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
                                .fontWeight(selectedCategory == catName ? .semibold : .regular)
                            Text("\(count)")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(selectedCategory == catName ? Color.white.opacity(0.25) : Color.primary.opacity(0.06))
                                )
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selectedCategory == catName ? CoreScopeStyle.accent : Color.primary.opacity(0.04))
                        )
                        .foregroundStyle(selectedCategory == catName ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
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
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func filteredReadings(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        readings.filter { reading in
            let matchesCategory = selectedCategory == "All" || reading.category.rawValue == selectedCategory
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
                    title: "BATTERY & POWER",
                    icon: batteryIcon,
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

    private var powerHeadline: String {
        guard let snapshot = model.snapshot else { return "Reading power state" }
        return snapshot.powerMode.rawValue
    }

    private var powerSubtitle: String {
        guard let snapshot = model.snapshot else { return "Waiting for first scan" }
        if snapshot.powerMode == .external {
            if snapshot.isCharging == true {
                return "Adapter connected · Battery charging"
            }
            if snapshot.isCharging == false {
                if snapshot.isAdapterConnected == true {
                    return "Adapter connected · Charge hold or complete"
                }
                return "External power · Battery not charging"
            }
            return "System is drawing external AC power"
        }
        if snapshot.powerMode == .battery {
            if snapshot.isAdapterConnected == true {
                return "Adapter attached · Drawing battery power"
            }
            return "System is discharging on battery power"
        }
        return "Power source could not be determined"
    }

    private var batteryHeadline: String {
        guard let snapshot = model.snapshot else {
            return model.isRefreshing ? "Reading…" : "Unavailable"
        }
        if let percent = snapshot.batteryPercent {
            if snapshot.isCharging == true {
                return "\(percent)% · Charging"
            } else if snapshot.powerMode == .external {
                return "\(percent)% · Connected"
            } else {
                return "\(percent)% · Discharging"
            }
        }
        return snapshot.powerMode == .external ? "AC Connected (No Battery)" : "Unavailable"
    }

    private var batteryIcon: String {
        guard let snapshot = model.snapshot else { return "battery.75percent" }
        if snapshot.isCharging == true {
            return "battery.100percent.bolt"
        }
        guard let pct = snapshot.batteryPercent else {
            return snapshot.powerMode == .external ? "powerplug.fill" : "battery.0percent"
        }
        if pct > 80 { return "battery.100percent" }
        if pct > 50 { return "battery.75percent" }
        if pct > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    private var batteryDetail: String {
        guard let snapshot = model.snapshot else { return "Battery details appear after the first scan" }
        if snapshot.isCharging == true {
            return "Battery is actively charging from external AC adapter"
        }
        if snapshot.isCharging == false && snapshot.powerMode == .external {
            return "Connected to AC power · Charge on hold or complete"
        }
        if snapshot.powerMode == .battery {
            return "Running on battery · Discharging"
        }
        if snapshot.batteryPercent == nil && snapshot.powerMode == .external {
            return "Desktop Mac or external power with no battery present"
        }
        return "Charging state not reported"
    }

    private var thermalDetail: String {
        switch model.snapshot?.thermalState {
        case "Nominal": "Operating normally with no elevated thermal pressure"
        case "Fair": "Moderate thermal pressure reported by macOS"
        case "Serious": "High thermal pressure reported by macOS"
        case "Critical": "Critical thermal pressure reported by macOS"
        case .none: "Read directly from ProcessInfo thermal state"
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

    private var isCalibration: Bool {
        reading.category == .calibration
    }

    private var tempColor: Color {
        CoreScopeStyle.tempColor(for: reading.temperatureC, isCalibration: isCalibration)
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
                        .foregroundStyle(tempColor.opacity(0.85))
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
                    Text(reading.category.rawValue)
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
                    .frame(width: 44, height: 4)
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
