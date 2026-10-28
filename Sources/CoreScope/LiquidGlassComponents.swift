import AppKit
import SwiftUI

// MARK: - Liquid Glass Design System

enum LiquidGlassStyle {
    // Atmosphere palette: Midnight blue-violet atmosphere
    static let midnight = Color(red: 0.035, green: 0.045, blue: 0.075) // #090B13 near-black midnight base
    static let indigoGlow = Color(red: 0.14, green: 0.20, blue: 0.52) // #243385 soft static indigo-blue pool
    static let violetGlow = Color(red: 0.32, green: 0.20, blue: 0.58) // #523394 restrained violet ambient light
    static let violetTint = Color(red: 0.52, green: 0.44, blue: 0.88) // #8570E0 panel tint & specular edge

    // Typography tokens
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.68, green: 0.71, blue: 0.84) // muted lavender
    static let textTertiary = Color(red: 0.48, green: 0.51, blue: 0.64)

    // Hardware telemetry semantic palette
    static let teal = Color(red: 0.18, green: 0.74, blue: 0.70)
    static let emerald = Color(red: 0.20, green: 0.78, blue: 0.56)
    static let amber = Color(red: 0.95, green: 0.65, blue: 0.24)
    static let coral = Color(red: 0.94, green: 0.38, blue: 0.38)
    static let violet = Color(red: 0.64, green: 0.50, blue: 0.95)
    static let slate = Color(red: 0.56, green: 0.62, blue: 0.70)
    static let obsidian = Color(red: 0.05, green: 0.06, blue: 0.08)

    /// Temperature color coding adhering to restrained hardware observability palette.
    static func tempColor(for tempC: Double, isCalibration: Bool = false) -> Color {
        if isCalibration {
            return violet
        }
        if tempC < 45.0 {
            return teal
        } else if tempC < 65.0 {
            return emerald
        } else if tempC < 80.0 {
            return amber
        } else {
            return coral
        }
    }
}

// MARK: - Asset Loader

enum AmbientAssetLoader {
    /// Loads and decodes the static ambient image once using safe multi-location resolution.
    /// Never invokes SPM's fatalError-prone Bundle.module accessor.
    static let image: NSImage? = {
        loadSafeAmbientImage()
    }()

    private static func loadSafeAmbientImage() -> NSImage? {
        // 1. Packaged macOS app bundle: Contents/Resources/CoreScopeAmbient.png
        if let mainURL = Bundle.main.url(forResource: "CoreScopeAmbient", withExtension: "png"),
           let img = loadImageIfValid(at: mainURL) {
            return img
        }

        if let directResourcePath = Bundle.main.resourceURL?.appendingPathComponent("CoreScopeAmbient.png"),
           let img = loadImageIfValid(at: directResourcePath) {
            return img
        }

        // 2. Sibling to executable binary (for swift run or standalone binary execution)
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let directSibling = execDir.appendingPathComponent("CoreScopeAmbient.png")
            if let img = loadImageIfValid(at: directSibling) {
                return img
            }

            // Safe inspection of SwiftPM-generated resource bundle next to executable (explicit check, zero Bundle.module)
            let spmBundleURL = execDir.appendingPathComponent("CoreScope_CoreScope.bundle")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: spmBundleURL.path, isDirectory: &isDir), isDir.boolValue,
               let spmBundle = Bundle(url: spmBundleURL),
               let bundledURL = spmBundle.url(forResource: "CoreScopeAmbient", withExtension: "png"),
               let img = loadImageIfValid(at: bundledURL) {
                return img
            }
        }

        // 3. Development workspace source tree path
        let relativePaths = [
            "Sources/CoreScope/Resources/CoreScopeAmbient.png",
            "Resources/CoreScopeAmbient.png"
        ]
        for relPath in relativePaths {
            let fileURL = URL(fileURLWithPath: relPath)
            if let img = loadImageIfValid(at: fileURL) {
                return img
            }
        }

        // Graceful fallback: return nil to render dark liquid-glass gradient without crashing
        return nil
    }

    private static func loadImageIfValid(at url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let img = NSImage(contentsOf: url), img.isValid else {
            return nil
        }
        return img
    }
}

// MARK: - Safe System Telemetry

enum SystemInfo {
    static let chipName: String = {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "Apple Silicon" }
            return String(validatingCString: base) ?? "Apple Silicon"
        }
    }()

    static let modelIdentifier: String = {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "Mac" }
            return String(validatingCString: base) ?? "Mac"
        }
    }()

    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    static let activeCores: Int = {
        ProcessInfo.processInfo.processorCount
    }()
}

// MARK: - Ambient Background View

struct AmbientBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Base surface: deep midnight near-black
            if colorScheme == .dark {
                LiquidGlassStyle.midnight.ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            }

            // Bundled local image background with restrained opacity
            if !reduceTransparency, let nsImage = AmbientAssetLoader.image {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(colorScheme == .dark ? 0.30 : 0.12)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }

            // Static midnight blue-violet ambient illumination pools (zero animation overhead)
            if !reduceTransparency {
                GeometryReader { proxy in
                    // Broad static indigo-blue pool in upper-left
                    Circle()
                        .fill(LiquidGlassStyle.indigoGlow.opacity(colorScheme == .dark ? 0.16 : 0.08))
                        .frame(width: 620, height: 620)
                        .blur(radius: 150)
                        .position(x: proxy.size.width * 0.20, y: proxy.size.height * 0.18)
                        .allowsHitTesting(false)

                    // Restrained violet ambient pool in lower-right
                    Circle()
                        .fill(LiquidGlassStyle.violetGlow.opacity(colorScheme == .dark ? 0.13 : 0.06))
                        .frame(width: 580, height: 580)
                        .blur(radius: 160)
                        .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.72)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }

            // High-contrast dark veil for ultra-sharp typography
            if colorScheme == .dark {
                Color.black.opacity(reduceTransparency ? 0.92 : 0.32)
                    .ignoresSafeArea()
            } else {
                Color.white.opacity(reduceTransparency ? 0.90 : 0.38)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Glass Card Container

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        cornerRadius: CGFloat = 18,
        padding: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(backgroundSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(specularBorder)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08),
                radius: 18,
                x: 0,
                y: 8
            )
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        if reduceTransparency {
            if colorScheme == .dark {
                Color(red: 0.08, green: 0.09, blue: 0.14)
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(LiquidGlassStyle.violetTint.opacity(colorScheme == .dark ? 0.03 : 0.015))
            }
        }
    }

    private var specularBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.40),
                        LiquidGlassStyle.violetTint.opacity(colorScheme == .dark ? 0.08 : 0.12),
                        Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

// MARK: - Temperature Metric Card

struct TemperatureMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let subtitle: String
    let accent: Color
    let icon: String

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with icon and uppercase tracking label
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                    Spacer(minLength: 0)
                }

                // Numeric value display
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent.opacity(0.85))
                    }
                }

                // Subtitle description
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Power Status Card

struct PowerStatusCard: View {
    let snapshot: SensorSnapshot?

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.batteryblock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LiquidGlassStyle.emerald)
                        Text("POWER & SYSTEM HEALTH")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                    }
                    Spacer()
                    // Thermal pressure status pill
                    thermalPressureBadge
                }

                Divider().opacity(0.12)

                // 4-Quadrant telemetry grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricItem(
                        icon: powerModeIcon,
                        title: "ACTIVE POWER SOURCE",
                        value: powerModeHeadline,
                        detail: powerModeDetail,
                        accent: powerModeAccent
                    )

                    metricItem(
                        icon: batteryIcon,
                        title: "BATTERY LEVEL",
                        value: batteryLevelHeadline,
                        detail: batteryLevelDetail,
                        accent: batteryLevelAccent
                    )

                    metricItem(
                        icon: "powerplug.fill",
                        title: "POWER ADAPTER",
                        value: adapterHeadline,
                        detail: adapterDetail,
                        accent: snapshot?.isAdapterConnected == true ? LiquidGlassStyle.emerald : LiquidGlassStyle.textSecondary
                    )

                    metricItem(
                        icon: "bolt.fill",
                        title: "CHARGING STATUS",
                        value: chargingHeadline,
                        detail: chargingDetail,
                        accent: snapshot?.isCharging == true ? LiquidGlassStyle.emerald : LiquidGlassStyle.textSecondary
                    )
                }
            }
        }
    }

    private func metricItem(
        icon: String,
        title: String,
        value: String,
        detail: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlassStyle.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thermalPressureBadge: some View {
        let state = snapshot?.thermalState ?? "Nominal"
        let color: Color
        switch state {
        case "Nominal": color = LiquidGlassStyle.teal
        case "Fair": color = LiquidGlassStyle.amber
        case "Serious", "Critical": color = LiquidGlassStyle.coral
        default: color = .secondary
        }

        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("Thermal: \(state)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var powerModeIcon: String {
        switch snapshot?.powerMode {
        case .external: return "powerplug.fill"
        case .battery: return "battery.100percent"
        case .unknown, .none: return "bolt.slash"
        }
    }

    private var powerModeHeadline: String {
        switch snapshot?.powerMode {
        case .external: return "AC Power"
        case .battery: return "Battery Power"
        case .unknown, .none: return "Unavailable"
        }
    }

    private var powerModeDetail: String {
        switch snapshot?.powerMode {
        case .external: return "Drawing from power line"
        case .battery: return "Running on internal battery"
        case .unknown, .none: return "Power source not reported"
        }
    }

    private var powerModeAccent: Color {
        switch snapshot?.powerMode {
        case .external: return LiquidGlassStyle.emerald
        case .battery: return LiquidGlassStyle.teal
        case .unknown, .none: return .secondary
        }
    }

    private var batteryIcon: String {
        guard let snapshot = snapshot else { return "battery.75percent" }
        if snapshot.isCharging == true { return "battery.100percent.bolt" }
        guard let pct = snapshot.batteryPercent else { return "battery.0percent" }
        if pct > 80 { return "battery.100percent" }
        if pct > 50 { return "battery.75percent" }
        if pct > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    private var batteryLevelHeadline: String {
        if let pct = snapshot?.batteryPercent {
            return "\(pct)%"
        }
        if snapshot?.powerMode == .external {
            return "No Battery (Desktop)"
        }
        return "Unavailable"
    }

    private var batteryLevelDetail: String {
        guard let snapshot = snapshot else { return "Waiting for initial scan" }
        if let pct = snapshot.batteryPercent {
            return pct > 20 ? "Charge level healthy" : "Low battery level"
        }
        return "Non-portable Apple Silicon host"
    }

    private var batteryLevelAccent: Color {
        guard let pct = snapshot?.batteryPercent else { return .secondary }
        return pct > 20 ? LiquidGlassStyle.emerald : LiquidGlassStyle.coral
    }

    private var adapterHeadline: String {
        switch snapshot?.isAdapterConnected {
        case true: return "Connected"
        case false: return "Disconnected"
        case .none: return "Not Reported"
        }
    }

    private var adapterDetail: String {
        switch snapshot?.isAdapterConnected {
        case true: return "Physical adapter detected"
        case false: return "No external adapter attached"
        case .none: return "IOPowerSources query unavailable"
        }
    }

    private var chargingHeadline: String {
        switch snapshot?.isCharging {
        case true: return "Charging"
        case false: return "Not Charging"
        case .none: return "Not Reported"
        }
    }

    private var chargingDetail: String {
        if snapshot?.isCharging == true {
            return "Battery actively receiving charge"
        }
        if snapshot?.isAdapterConnected == true {
            return "Charge limit or hold active"
        }
        return "Discharging under load"
    }
}

// MARK: - Sensor Explorer Card

struct SensorCard: View {
    let reading: TemperatureReading

    private var isCalibration: Bool {
        reading.category == .calibration
    }

    private var tempColor: Color {
        LiquidGlassStyle.tempColor(for: reading.temperatureC, isCalibration: isCalibration)
    }

    var body: some View {
        GlassCard(cornerRadius: 14, padding: 10) {
            HStack(spacing: 11) {
                // Temperature badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tempColor.opacity(0.13))
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f", reading.temperatureC))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(tempColor)
                        Text("°C")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(tempColor.opacity(0.85))
                    }
                }
                .frame(width: 50, height: 42)

                // Sensor descriptor and proportional scale bar
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.sensorName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(reading.category.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)

                        Circle()
                            .fill(LiquidGlassStyle.textSecondary.opacity(0.35))
                            .frame(width: 3, height: 3)

                        // Subtle temperature scale bar (0–100 °C bounds)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [tempColor.opacity(0.7), tempColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(3, min(geo.size.width, geo.size.width * CGFloat(reading.temperatureC / 100.0))))
                            }
                        }
                        .frame(width: 44, height: 3.5)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Status Indicator Pill

struct StatusIndicator: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(LiquidGlassStyle.textPrimary)

            if let subtitle = subtitle {
                Text("·")
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                Text(subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(LiquidGlassStyle.violetTint.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - Thermal Pressure & Throttling Card

struct ThermalPressurePerformanceCard: View {
    let snapshot: SensorSnapshot?

    var body: some View {
        let assessment = snapshot?.throttlingAssessment ?? ThrottlingAssessment(
            thermalPressure: .nominal,
            clockTelemetry: .unavailable(reason: "No active scan"),
            inference: .normalOperation,
            assessmentSummary: "macOS reports nominal thermal pressure."
        )

        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LiquidGlassStyle.indigoGlow)
                        Text("THERMAL PRESSURE & PERFORMANCE INTEGRITY")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                    }
                    Spacer()
                    // Thermal pressure badge
                    HStack(spacing: 6) {
                        Image(systemName: assessment.thermalPressure.iconName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(assessment.thermalPressure.badgeColor)
                        Text(assessment.thermalPressure.title.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(assessment.thermalPressure.badgeColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(assessment.thermalPressure.badgeColor.opacity(0.12), in: Capsule())
                }

                Divider().opacity(0.12)

                // 2-Column Assessment Grid
                HStack(alignment: .top, spacing: 16) {
                    // Left: Throttling / Performance Reduction Status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Circle().fill(inferenceColor(assessment.inference)).frame(width: 6, height: 6)
                            Text("PERFORMANCE STATUS")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }

                        Text(assessment.inference.rawValue)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(inferenceColor(assessment.inference))

                        Text(assessment.assessmentSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().opacity(0.12).frame(height: 70)

                    // Right: Clock Telemetry Status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Circle().fill(LiquidGlassStyle.teal).frame(width: 6, height: 6)
                            Text("CLOCK FREQUENCY TELEMETRY")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }

                        if case .measured(let tel) = assessment.clockTelemetry {
                            HStack(spacing: 12) {
                                if let p = tel.pCoreFrequencyMHz {
                                    Text("P-Core: \(Int(p)) MHz")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(LiquidGlassStyle.textPrimary)
                                }
                                if let e = tel.eCoreFrequencyMHz {
                                    Text("E-Core: \(Int(e)) MHz")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(LiquidGlassStyle.textPrimary)
                                }
                            }
                        } else {
                            Text("Direct Clock Telemetry: Unavailable")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlassStyle.textPrimary)
                        }

                        Text(assessment.clockTelemetry.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Clarification Callout
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(LiquidGlassStyle.violetTint)
                    Text("Thermal Pressure reports OS scheduler guidance. Clock frequency throttling is a hardware voltage/frequency power clamp. Direct clock reduction cannot be assumed without verified clock telemetry.")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                }
                .padding(.top, 2)
            }
        }
    }

    private func inferenceColor(_ inference: PerformanceReductionInference) -> Color {
        switch inference {
        case .normalOperation:
            return LiquidGlassStyle.emerald
        case .thermalPressureElevated:
            return LiquidGlassStyle.amber
        case .possibleThermalReduction:
            return Color(red: 1.0, green: 0.45, blue: 0.15)
        case .confirmedThermalThrottling:
            return LiquidGlassStyle.coral
        case .insufficientTelemetry:
            return LiquidGlassStyle.teal
        }
    }
}

// MARK: - Thermal Domains Section

struct ThermalDomainsSection: View {
    let snapshot: SensorSnapshot?
    @State private var isExpanded: Bool = true

    var body: some View {
        let registry = snapshot?.sensorRegistry ?? SensorRegistry()

        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header with expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LiquidGlassStyle.indigoGlow)
                        Text("THERMAL DOMAINS & CLUSTERS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(LiquidGlassStyle.textSecondary)

                        Spacer()

                        Text(registry.hasVerifiedClusterMappings ? "VERIFIED MAPPINGS" : "GENERIC PMU DESCRIPTORS (M4)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(registry.hasVerifiedClusterMappings ? LiquidGlassStyle.emerald : LiquidGlassStyle.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06), in: Capsule())

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LiquidGlassStyle.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().opacity(0.12)

                    // 4 Cluster Domain Tiles
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        clusterTile(
                            measurement: registry.pCoreCluster,
                            title: "PERFORMANCE CORES (P-CORE)",
                            icon: "bolt.fill",
                            accent: LiquidGlassStyle.coral
                        )

                        clusterTile(
                            measurement: registry.eCoreCluster,
                            title: "EFFICIENCY CORES (E-CORE)",
                            icon: "leaf.fill",
                            accent: LiquidGlassStyle.emerald
                        )

                        clusterTile(
                            measurement: registry.gpuCluster,
                            title: "GPU COMPUTE CORES",
                            icon: "sparkles",
                            accent: LiquidGlassStyle.amber
                        )

                        clusterTile(
                            measurement: registry.socFabricCluster,
                            title: "SOC / FABRIC / NEURAL ENGINE",
                            icon: "cpu",
                            accent: LiquidGlassStyle.indigoGlow
                        )
                    }

                    // Explanatory note when unmapped
                    if !registry.hasVerifiedClusterMappings {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 11))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                            Text("Apple PMU firmware exposes 24 discrete die sensors (tdie) without core/cluster attribution on this machine. To avoid fabricating data, cluster averages are shown as Unavailable while verified die aggregates (Peak & Mean) remain active above.")
                                .font(.system(size: 10))
                                .foregroundStyle(LiquidGlassStyle.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func clusterTile(
        measurement: ClusterMeasurement,
        title: String,
        icon: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
                Spacer()
                Text("\(measurement.sensorCount) sensors")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LiquidGlassStyle.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(measurement.formattedAverage)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(measurement.isAvailable ? accent : LiquidGlassStyle.textSecondary)

                if let peak = measurement.peakC {
                    Text("· Peak: \(String(format: "%.1f°C", peak))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(LiquidGlassStyle.textSecondary)
                }
            }

            Text(measurement.note)
                .font(.system(size: 10))
                .foregroundStyle(LiquidGlassStyle.textSecondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

