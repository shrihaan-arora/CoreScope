import Foundation

// MARK: - Thermal Session Duration

enum ThermalSessionDuration: Equatable, CaseIterable, Identifiable, Sendable {
    case seconds30
    case minutes2
    case minutes5
    case manual

    var id: String { title }

    var title: String {
        switch self {
        case .seconds30: return "30s"
        case .minutes2:  return "2m"
        case .minutes5:  return "5m"
        case .manual:    return "Manual"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .seconds30: return 30.0
        case .minutes2:  return 120.0
        case .minutes5:  return 300.0
        case .manual:    return nil
        }
    }

    static var allCases: [ThermalSessionDuration] {
        [.seconds30, .minutes2, .minutes5, .manual]
    }
}

// MARK: - Thermal Session State

enum ThermalSessionState: Equatable, Sendable {
    case idle
    case running
    case completed
}

// MARK: - Thermal Sample

struct ThermalSample: Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let elapsedSeconds: TimeInterval
    let peakDieTemp: Double?
    let peakDieSensorName: String?
    let averageDieTemp: Double?
    let operatingChannelCount: Int
    let thermalState: String
    let powerMode: PowerMode
    let isCharging: Bool?
    let batteryPercent: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        elapsedSeconds: TimeInterval,
        peakDieTemp: Double?,
        peakDieSensorName: String?,
        averageDieTemp: Double?,
        operatingChannelCount: Int,
        thermalState: String,
        powerMode: PowerMode,
        isCharging: Bool?,
        batteryPercent: Int?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.peakDieTemp = peakDieTemp
        self.peakDieSensorName = peakDieSensorName
        self.averageDieTemp = averageDieTemp
        self.operatingChannelCount = operatingChannelCount
        self.thermalState = thermalState
        self.powerMode = powerMode
        self.isCharging = isCharging
        self.batteryPercent = batteryPercent
    }

    /// Creates a sample from an authentic SensorSnapshot and reference start time.
    static func create(from snapshot: SensorSnapshot, startTime: Date) -> ThermalSample {
        let elapsed = max(0.0, snapshot.sampledAt.timeIntervalSince(startTime))
        let summary = snapshot.temperatureSummary
        return ThermalSample(
            timestamp: snapshot.sampledAt,
            elapsedSeconds: elapsed,
            peakDieTemp: summary.peakDieReading?.temperatureC,
            peakDieSensorName: summary.peakDieReading?.sensorName,
            averageDieTemp: summary.dieAverageC,
            operatingChannelCount: summary.operatingSensorCount,
            thermalState: snapshot.thermalState,
            powerMode: snapshot.powerMode,
            isCharging: snapshot.isCharging,
            batteryPercent: snapshot.batteryPercent
        )
    }
}

// MARK: - Thermal Session Summary Statistics

struct ThermalSessionSummary: Sendable, Equatable {
    let sampleCount: Int
    let totalDuration: TimeInterval
    let peakObservedTemp: Double?
    let peakObservedSensor: String?
    let averageObservedTemp: Double?
    let minObservedTemp: Double?
    let initialTemp: Double?
    let finalTemp: Double?
    let thermalStateTransitions: Int
    let powerModeTransitions: Int

    static func compute(from samples: [ThermalSample]) -> ThermalSessionSummary? {
        guard !samples.isEmpty else { return nil }

        let count = samples.count
        let first = samples.first!
        let last = samples.last!
        let duration = max(0.0, last.elapsedSeconds - first.elapsedSeconds)

        // 1. Peak temperature and matching sensor channel
        var maxPeak: Double? = nil
        var maxSensor: String? = nil
        for s in samples {
            if let p = s.peakDieTemp {
                if maxPeak == nil || p > maxPeak! {
                    maxPeak = p
                    maxSensor = s.peakDieSensorName
                }
            }
        }

        // 2. Minimum observed die average or peak
        var minTemp: Double? = nil
        for s in samples {
            if let avg = s.averageDieTemp {
                if minTemp == nil || avg < minTemp! {
                    minTemp = avg
                }
            } else if let p = s.peakDieTemp {
                if minTemp == nil || p < minTemp! {
                    minTemp = p
                }
            }
        }

        // 3. Average observed die temperature across all samples
        let validAverages = samples.compactMap { $0.averageDieTemp }
        let overallAverage: Double?
        if !validAverages.isEmpty {
            overallAverage = validAverages.reduce(0.0, +) / Double(validAverages.count)
        } else {
            let validPeaks = samples.compactMap { $0.peakDieTemp }
            overallAverage = validPeaks.isEmpty ? nil : (validPeaks.reduce(0.0, +) / Double(validPeaks.count))
        }

        // 4. Transitions
        var thermalTransitions = 0
        var powerTransitions = 0
        for i in 1..<samples.count {
            if samples[i].thermalState != samples[i - 1].thermalState {
                thermalTransitions += 1
            }
            if samples[i].powerMode != samples[i - 1].powerMode {
                powerTransitions += 1
            }
        }

        return ThermalSessionSummary(
            sampleCount: count,
            totalDuration: duration,
            peakObservedTemp: maxPeak,
            peakObservedSensor: maxSensor,
            averageObservedTemp: overallAverage,
            minObservedTemp: minTemp,
            initialTemp: first.averageDieTemp ?? first.peakDieTemp,
            finalTemp: last.averageDieTemp ?? last.peakDieTemp,
            thermalStateTransitions: thermalTransitions,
            powerModeTransitions: powerTransitions
        )
    }
}

// MARK: - Safe RFC 4180 CSV Exporter

enum ThermalSessionCSVExporter {
    /// Generates clean RFC 4180 CSV text strictly from in-memory sample records.
    /// Excludes usernames, serial numbers, home directories, and machine identifiers.
    static func generateCSV(from samples: [ThermalSample]) -> String {
        var lines: [String] = []

        // Header
        lines.append("Timestamp,ElapsedSeconds,PeakDieTempC,PeakDieSensor,AverageDieTempC,OperatingChannels,ThermalState,PowerMode,IsCharging,BatteryPercent")

        for sample in samples {
            let ts = sample.timestamp.formatted(.iso8601)
            let elapsed = String(format: "%.1f", sample.elapsedSeconds)
            let peak = sample.peakDieTemp.map { String(format: "%.2f", $0) } ?? "unavailable"
            let sensor = escapeCSV(sample.peakDieSensorName ?? "unavailable")
            let avg = sample.averageDieTemp.map { String(format: "%.2f", $0) } ?? "unavailable"
            let channels = String(sample.operatingChannelCount)
            let thermal = escapeCSV(sample.thermalState)
            let power = escapeCSV(sample.powerMode.rawValue)
            let charging = sample.isCharging.map { String($0) } ?? "unavailable"
            let battery = sample.batteryPercent.map { String($0) } ?? "unavailable"

            lines.append("\(ts),\(elapsed),\(peak),\(sensor),\(avg),\(channels),\(thermal),\(power),\(charging),\(battery)")
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 string escaping: quotes fields containing commas, quotes, or newlines.
    static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
