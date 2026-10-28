import Foundation
import CIOHIDSensors

// MARK: - Public Data Types

/// A single validated temperature reading from an Apple Silicon PMU sensor.
struct TemperatureReading: Identifiable, Sendable {
    /// The raw HID service product name (e.g. "PMU tdie1", "PMU tdev3").
    let sensorName: String
    /// Temperature in degrees Celsius, validated to the range 5–120 °C.
    let temperatureC: Double

    var id: String { sensorName }

    /// High-level hardware subsystem category derived from Apple PMU naming conventions.
    var category: String {
        let lower = sensorName.lowercased()
        if lower.contains("battery") {
            return "Battery"
        } else if lower.contains("nand") || lower.contains("storage") {
            return "Storage"
        } else if lower.contains("tdev") {
            return "Device Node"
        } else if lower.contains("tdie") || lower.contains("tcal") {
            return "Silicon Die"
        } else {
            return "System"
        }
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

            readings.append(TemperatureReading(sensorName: name, temperatureC: value))
        }

        if readings.isEmpty {
            return .noValidReadings(sensorCount: count)
        }
        return .readings(readings)
    }
}
