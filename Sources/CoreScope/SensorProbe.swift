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

    /// Sensor registry with verified cluster mappings and descriptor metadata.
    let sensorRegistry: SensorRegistry
    /// Typed thermal pressure state.
    let thermalPressure: ThermalPressureState
    /// Direct clock frequency and residency telemetry probe result.
    let clockTelemetry: ClockTelemetryResult
    /// Evaluated thermal throttling assessment separating pressure from clock reduction.
    let throttlingAssessment: ThrottlingAssessment

    init(
        temperatureReadings: [TemperatureReading],
        temperatureStatus: TemperatureStatus,
        powerMode: PowerMode,
        batteryPercent: Int?,
        isCharging: Bool?,
        isAdapterConnected: Bool?,
        thermalState: String,
        sampledAt: Date,
        sensorRegistry: SensorRegistry? = nil,
        thermalPressure: ThermalPressureState? = nil,
        clockTelemetry: ClockTelemetryResult? = nil,
        throttlingAssessment: ThrottlingAssessment? = nil
    ) {
        self.temperatureReadings = temperatureReadings
        self.temperatureStatus = temperatureStatus
        self.powerMode = powerMode
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.isAdapterConnected = isAdapterConnected
        self.thermalState = thermalState
        self.sampledAt = sampledAt

        let reg = sensorRegistry ?? SensorRegistry.build(from: temperatureReadings)
        self.sensorRegistry = reg

        let tp = thermalPressure ?? (ThermalPressureState(rawValue: thermalState) ?? .nominal)
        self.thermalPressure = tp

        let clock = clockTelemetry ?? .unavailable(reason: "Clock telemetry not probed for snapshot")
        self.clockTelemetry = clock

        self.throttlingAssessment = throttlingAssessment ?? ThrottlingAssessment.evaluate(thermalPressure: tp, clockTelemetry: clock)
    }

    /// Operating temperature summary isolating die sensors and excluding calibration channels.
    var temperatureSummary: TemperatureSummary {
        TemperatureSummary(readings: temperatureReadings)
    }
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
        let nativeThermal = ProcessInfo.processInfo.thermalState
        let thermalPressureState = ThermalPressureState.from(nativeState: nativeThermal)
        let thermal = thermalPressureState.rawValue

        // 4. Sensor Registry
        let registry = SensorRegistry.build(from: readings)

        // 5. Clock Telemetry
        let clockResult = ClockTelemetryProbe.probe()

        // 6. Throttling Assessment
        let assessment = ThrottlingAssessment.evaluate(thermalPressure: thermalPressureState, clockTelemetry: clockResult)

        return SensorSnapshot(
            temperatureReadings: readings,
            temperatureStatus: tempStatus,
            powerMode: power.mode,
            batteryPercent: power.batteryPercent,
            isCharging: power.isCharging,
            isAdapterConnected: power.isAdapterConnected,
            thermalState: thermal,
            sampledAt: Date(),
            sensorRegistry: registry,
            thermalPressure: thermalPressureState,
            clockTelemetry: clockResult,
            throttlingAssessment: assessment
        )
    }

    private static func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        ThermalPressureState.from(nativeState: state).rawValue
    }
}

// MARK: - Power Source Reader

struct PowerSnapshot: Sendable, Equatable {
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

        let sources = IOPSCopyPowerSourcesList(info)
            .takeRetainedValue() as [CFTypeRef]

        var descriptions: [[String: Any]] = []
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] {
                descriptions.append(desc)
            }
        }

        return parse(sourceType: sourceType, descriptions: descriptions)
    }

    /// Pure parsing logic decoupled from IOKit handles for testing.
    /// Distinguishes between adapter connection and active charging.
    static func parse(sourceType: String?, descriptions: [[String: Any]]) -> PowerSnapshot {
        let mode: PowerMode
        switch sourceType {
        case "AC Power":      mode = .external
        case "Battery Power": mode = .battery
        default:              mode = .unknown
        }

        var batteryPercent: Int?
        var isCharging: Bool?
        var isAdapterConnected: Bool?

        for description in descriptions {
            // Battery percentage
            if let current = description["Current Capacity"] as? NSNumber,
               let maximum = description["Max Capacity"] as? NSNumber,
               maximum.doubleValue > 0 {
                let pct = (current.doubleValue / maximum.doubleValue * 100).rounded()
                batteryPercent = max(0, min(100, Int(pct)))
            }

            // Charging state
            if let charging = description["Is Charging"] as? NSNumber {
                isCharging = charging.boolValue
            }

            // Adapter presence — distinct from charging state
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
