import Foundation
import CIOHIDSensors

// MARK: - Public Data Types

/// High-level hardware subsystem category derived from Apple PMU naming conventions.
enum SensorCategory: String, CaseIterable, Identifiable, Sendable, Comparable {
    case siliconDie = "Silicon Die"
    case deviceNode = "Device Node"
    case battery = "Battery"
    case storage = "Storage"
    case calibration = "Calibration / Reference"
    case system = "System"

    var id: String { rawValue }

    static func < (lhs: SensorCategory, rhs: SensorCategory) -> Bool {
        let order: [SensorCategory] = [.siliconDie, .deviceNode, .battery, .storage, .calibration, .system]
        let lIdx = order.firstIndex(of: lhs) ?? 99
        let rIdx = order.firstIndex(of: rhs) ?? 99
        return lIdx < rIdx
    }
}

/// A single validated temperature reading from an Apple Silicon PMU sensor.
struct TemperatureReading: Identifiable, Sendable, Equatable {
    /// Unique identifier for this sensor reading instance/channel.
    let id: String
    /// The raw HID service product name (e.g. "PMU tdie1", "PMU tdev3", "PMU tcal").
    let sensorName: String
    /// Temperature in degrees Celsius, validated to the range 5–120 °C.
    let temperatureC: Double

    init(id: String? = nil, sensorName: String, temperatureC: Double) {
        self.id = id ?? sensorName
        self.sensorName = sensorName
        self.temperatureC = temperatureC
    }

    /// Subsystem classification based purely on Apple PMU channel conventions.
    /// Does NOT fabricate CPU/GPU core mappings.
    var category: SensorCategory {
        Self.classify(sensorName: sensorName)
    }

    /// Classify raw PMU sensor descriptor into functional subsystem.
    static func classify(sensorName: String) -> SensorCategory {
        let lower = sensorName.lowercased()
        if lower.contains("tcal") {
            // Calibration/reference channels (e.g. tcal) are isolated from operating die sensors
            return .calibration
        } else if lower.contains("tdie") {
            return .siliconDie
        } else if lower.contains("tdev") {
            return .deviceNode
        } else if lower.contains("battery") || lower.contains("gas gauge") {
            return .battery
        } else if lower.contains("nand") || lower.contains("storage") {
            return .storage
        } else {
            return .system
        }
    }
}

/// Operating temperature summary calculated strictly from validated channels.
/// Calibration and reference channels are explicitly isolated from operating averages.
struct TemperatureSummary: Sendable, Equatable {
    /// Peak operating die sensor reading (excludes calibration channels)
    let peakDieReading: TemperatureReading?
    /// Mean temperature across validated Silicon Die channels only (excludes calibration, battery, device, storage)
    let dieAverageC: Double?
    /// Total active Silicon Die channels contributing to dieAverageC
    let dieSensorCount: Int
    /// Peak operating sensor across all subsystems (excludes calibration)
    let peakOperatingReading: TemperatureReading?
    /// Total operating channels (excludes calibration)
    let operatingSensorCount: Int
    /// Total calibration / reference channels
    let calibrationSensorCount: Int

    init(readings: [TemperatureReading]) {
        let calibrationReadings = readings.filter { $0.category == .calibration }
        self.calibrationSensorCount = calibrationReadings.count

        let operatingReadings = readings.filter { $0.category != .calibration }
        self.operatingSensorCount = operatingReadings.count
        self.peakOperatingReading = operatingReadings.max(by: { $0.temperatureC < $1.temperatureC })

        let dieReadings = readings.filter { $0.category == .siliconDie }
        self.dieSensorCount = dieReadings.count
        self.peakDieReading = dieReadings.max(by: { $0.temperatureC < $1.temperatureC })

        if !dieReadings.isEmpty {
            let sum = dieReadings.reduce(0.0) { $0 + $1.temperatureC }
            self.dieAverageC = sum / Double(dieReadings.count)
        } else {
            self.dieAverageC = nil
        }
    }

    /// Formatted die average string, explicitly displaying "Unavailable" rather than zero when no validated die channels exist.
    var formattedDieAverage: String {
        if let avg = dieAverageC {
            return String(format: "%.1f °C", avg)
        }
        return "Unavailable"
    }

    /// Formatted peak die sensor string, explicitly displaying "Unavailable" rather than zero when no validated die channels exist.
    var formattedPeakDie: String {
        if let peak = peakDieReading {
            return "\(peak.sensorName) (\(String(format: "%.1f °C", peak.temperatureC)))"
        }
        return "Unavailable"
    }
}

/// Outcome of a temperature sensor enumeration attempt.
enum TemperatureProbeResult: Sendable {
    /// At least one valid reading was collected.
    case readings([TemperatureReading])
    /// The HID event system client could not be created.
    case systemClientUnavailable
    /// The client was created and matching was applied, but no services
    /// matching the Apple vendor temperature usage page were found.
    case noSensorsFound
    /// Services were found, but none produced a valid temperature event
    /// within the acceptable range (5–120 °C).
    case noValidReadings(sensorCount: Int)
}

// MARK: - Temperature Probe

/// Reads Apple Silicon PMU temperature sensors via the private
/// IOHIDEventSystemClient API.
///
/// ## Design constraints
/// - Read-only. No hardware state is modified.
/// - On-demand. No timer, daemon, or background thread is started.
/// - Self-cleaning. The HID system client is created, used, and released
///   within a single call to `collectOnce()`.
/// - No root or privileged helper required.
/// - Returns only validated, genuine readings; never fabricated data.
///
/// ## How it works
/// Apple Silicon exposes die and package temperature sensors as
/// IOHIDServices that match the vendor-defined usage page `0xFF00`
/// with usage `0x05`. Each matching service can be queried for a
/// temperature event (type 15). The float value in the event is the
/// temperature in degrees Celsius.
///
/// Because the service product names (e.g. "PMU tdie1") do not carry
/// a documented CPU/GPU mapping, readings are labeled with the raw
/// sensor name rather than a potentially wrong "CPU" or "GPU" label.
enum TemperatureProbe {

    // IOHIDEventTypeTemperature
    private static let hidEventTypeTemperature: Int64 = 15
    // IOHIDEventFieldTemperatureLevel = (15 << 16)
    private static let hidFieldTemperatureLevel: Int64 = 15 << 16
    // Apple vendor-defined HID usage page for SoC sensors
    private static let vendorUsagePage: Int = 0xFF00
    // Usage ID for temperature sensors
    private static let temperatureUsage: Int = 0x05
    // Acceptable temperature range (°C)
    private static let validRange: ClosedRange<Double> = 5.0...120.0

    /// Enumerate accessible temperature sensors, read each one once,
    /// validate, and return the result. The HID client is released
    /// before this function returns.
    static func collectOnce() -> TemperatureProbeResult {

        // 1. Create an event system client
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            return .systemClientUnavailable
        }
        defer { CIOHIDEventSystemClientRelease(client) }

        // 2. Build matching dictionary for temperature sensors
        let matching: [String: Any] = [
            "PrimaryUsagePage": vendorUsagePage,
            "PrimaryUsage":     temperatureUsage
        ]
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

        // 3. Copy matching services
        guard let servicesArray = IOHIDEventSystemClientCopyServices(client) else {
            return .noSensorsFound
        }
        let count = CFArrayGetCount(servicesArray)
        if count == 0 {
            return .noSensorsFound
        }

        // 4. Iterate services and collect temperature readings
        var readings: [TemperatureReading] = []

        for i in 0..<count {
            guard let rawPtr = CFArrayGetValueAtIndex(servicesArray, i) else {
                continue
            }
            let service = IOHIDServiceClientRef(rawPtr)

            // Get sensor product name
            let name: String
            if let productRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
               let str = productRef as? String {
                name = str
            } else {
                name = "Unknown sensor"
            }

            // Read the most recent temperature event
            guard let event = IOHIDServiceClientCopyEvent(
                service,
                hidEventTypeTemperature,
                0,   // options
                0    // timestamp (0 = most recent)
            ) else {
                continue
            }
            // event is +1, defer release
            defer { CIOHIDEventRelease(event) }

            let value = IOHIDEventGetFloatValue(event, hidFieldTemperatureLevel)

            // Validate: must be finite and within sane physical range
            guard value.isFinite, validRange.contains(value) else {
                continue
            }

            readings.append(TemperatureReading(id: "\(name)#\(i)", sensorName: name, temperatureC: value))
        }

        if readings.isEmpty {
            return .noValidReadings(sensorCount: count)
        }
        return .readings(readings)
    }
}
