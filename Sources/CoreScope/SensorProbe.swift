import Foundation
import IOKit.ps

// MARK: - Snapshot Data Types

/// An immutable, thread-safe snapshot of all hardware readings taken
/// during a single on-demand scan. Published to the UI layer through
/// `DashboardModel`.
struct SensorSnapshot: Sendable {
    /// Individual PMU temperature sensor readings, labeled with their
    /// raw service product name. Empty if sensors are inaccessible.
    let temperatureReadings: [TemperatureReading]
    /// Human-readable explanation of the temperature probe outcome.
    let temperatureStatus: TemperatureStatus
    /// Active power source as reported by IOPowerSources.
    let powerMode: PowerMode
    /// Battery charge level 0–100, or nil if unavailable.
    let batteryPercent: Int?
    /// Whether the battery is actively charging, or nil if unknown.
    let isCharging: Bool?
    /// Whether an external power adapter is physically connected,
    /// independent of charging status.
    let isAdapterConnected: Bool?
    /// macOS thermal pressure label from ProcessInfo.
    let thermalState: String
    /// When this snapshot was collected.
    let sampledAt: Date
}

/// Describes the outcome of the temperature probe.
enum TemperatureStatus: Sendable {
    case available(sensorCount: Int)
    case systemClientUnavailable
    case noSensorsFound
    case noValidReadings(sensorCount: Int)

    var explanation: String {
        switch self {
        case .available(let count):
            return "Read \(count) temperature sensor\(count == 1 ? "" : "s") directly from the local HID event system."
        case .systemClientUnavailable:
            return "IOHIDEventSystemClient could not be created. The HID subsystem may be unavailable on this macOS version."
        case .noSensorsFound:
            return "No HID services matching the Apple vendor temperature usage page (0xFF00, usage 5) were found."
        case .noValidReadings(let count):
            return "Found \(count) temperature sensor service\(count == 1 ? "" : "s"), but none produced a valid reading in the 5–120 °C range."
        }
    }
}

enum PowerMode: String, Sendable, Equatable {
    case external = "External power"
    case battery  = "Battery power"
    case unknown  = "Power source unavailable"

    var shortLabel: String {
        switch self {
        case .external: "AC"
        case .battery:  "DC"
        case .unknown:  "—"
        }
    }
}

// MARK: - SensorProbe

/// On-demand hardware sensor reader. All operations are stateless and
/// synchronous. The probe does not install timers, daemons, launch
/// agents, or privileged helpers. System resources (HID client,
/// IOPowerSources info objects) are created and released within a
/// single read cycle.
struct SensorProbe: Sendable {

    /// Perform one complete hardware scan and return a snapshot.
    func read() -> SensorSnapshot {
        // 1. Temperature
        let tempResult = TemperatureProbe.collectOnce()
        let readings: [TemperatureReading]
        let tempStatus: TemperatureStatus
        switch tempResult {
        case .readings(let r):
            readings  = r
            tempStatus = .available(sensorCount: r.count)
        case .systemClientUnavailable:
            readings  = []
            tempStatus = .systemClientUnavailable
        case .noSensorsFound:
            readings  = []
            tempStatus = .noSensorsFound
        case .noValidReadings(let count):
            readings  = []
            tempStatus = .noValidReadings(sensorCount: count)
        }

        // 2. Power source and battery
        let power = PowerSourceReader.read()

        // 3. Thermal pressure
        let thermal = Self.thermalStateLabel(ProcessInfo.processInfo.thermalState)

        return SensorSnapshot(
            temperatureReadings: readings,
            temperatureStatus: tempStatus,
            powerMode: power.mode,
            batteryPercent: power.batteryPercent,
            isCharging: power.isCharging,
            isAdapterConnected: power.isAdapterConnected,
            thermalState: thermal,
            sampledAt: Date()
        )
    }

    private static func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  "Nominal"
        case .fair:     "Fair"
        case .serious:  "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

// MARK: - Power Source Reader

struct PowerSnapshot: Sendable {
    let mode: PowerMode
    let batteryPercent: Int?
    let isCharging: Bool?
    let isAdapterConnected: Bool?
}

/// Reads the active power source, battery charge level, and charging
/// state from Apple's public IOPowerSources API. No external dependency
/// or privileged access is required.
enum PowerSourceReader {

    static func read() -> PowerSnapshot {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sourceType = IOPSGetProvidingPowerSourceType(info)?
            .takeUnretainedValue() as String?

        let mode: PowerMode
        switch sourceType {
        case "AC Power":      mode = .external
        case "Battery Power": mode = .battery
        default:              mode = .unknown
        }

        var batteryPercent: Int?
        var isCharging: Bool?
        var isAdapterConnected: Bool?

        let sources = IOPSCopyPowerSourcesList(info)
            .takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            // Battery percentage
            if let current = description["Current Capacity"] as? NSNumber,
               let maximum = description["Max Capacity"] as? NSNumber,
               maximum.doubleValue > 0 {
                let pct = (current.doubleValue / maximum.doubleValue * 100).rounded()
                batteryPercent = max(0, min(100, Int(pct)))
            }

            // Charging state — explicitly distinguish "connected but not
            // charging" from "drawing battery power".
            if let charging = description["Is Charging"] as? NSNumber {
                isCharging = charging.boolValue
            }

            // Adapter presence — reported separately from charging state.
            // "Power Source State" == "AC Power" indicates a connected
            // adapter even when the battery is not actively charging
            // (e.g., charge hold at 80 %).
            if let psState = description["Power Source State"] as? String {
                isAdapterConnected = (psState == "AC Power")
            }
        }

        return PowerSnapshot(
            mode: mode,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            isAdapterConnected: isAdapterConnected
        )
    }
}
