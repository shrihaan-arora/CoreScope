import Foundation
import Testing
@testable import CoreScope

// MARK: - Sensor Classification & Summary Tests

@Test func testSensorCategoryClassification() throws {
    #expect(TemperatureReading.classify(sensorName: "PMU tdie1") == .siliconDie)
    #expect(TemperatureReading.classify(sensorName: "PMU2 tdie8") == .siliconDie)
    #expect(TemperatureReading.classify(sensorName: "PMU tcal") == .calibration)
    #expect(TemperatureReading.classify(sensorName: "PMU2 tcal") == .calibration)
    #expect(TemperatureReading.classify(sensorName: "PMU tdev6") == .deviceNode)
    #expect(TemperatureReading.classify(sensorName: "PMU2 tdev4") == .deviceNode)
    #expect(TemperatureReading.classify(sensorName: "gas gauge battery") == .battery)
    #expect(TemperatureReading.classify(sensorName: "Battery Cell 1") == .battery)
    #expect(TemperatureReading.classify(sensorName: "NAND CH0 temp") == .storage)
    #expect(TemperatureReading.classify(sensorName: "Storage Controller") == .storage)
    #expect(TemperatureReading.classify(sensorName: "Unknown Heat Node") == .system)
}

@Test func testTemperatureSummaryCalculation() throws {
    let readings: [TemperatureReading] = [
        TemperatureReading(sensorName: "PMU tdie1", temperatureC: 40.0),
        TemperatureReading(sensorName: "PMU tdie2", temperatureC: 50.0),
        // Calibration channel (high reference setpoint; MUST be excluded from die average and peak die)
        TemperatureReading(sensorName: "PMU tcal", temperatureC: 95.0),
        // Peripheral channels; MUST be excluded from die average
        TemperatureReading(sensorName: "gas gauge battery", temperatureC: 30.0),
        TemperatureReading(sensorName: "NAND CH0 temp", temperatureC: 35.0),
        TemperatureReading(sensorName: "PMU tdev2", temperatureC: 38.0)
    ]

    let summary = TemperatureSummary(readings: readings)

    // Verify die average is computed strictly across die channels (40 + 50) / 2 = 45.0
    #expect(summary.dieAverageC == 45.0)
    #expect(summary.dieSensorCount == 2)

    // Verify peak die sensor is PMU tdie2 at 50.0 °C (tcal at 95.0 °C must NOT be chosen)
    #expect(summary.peakDieReading?.sensorName == "PMU tdie2")
    #expect(summary.peakDieReading?.temperatureC == 50.0)

    // Verify calibration separation
    #expect(summary.calibrationSensorCount == 1)
    #expect(summary.operatingSensorCount == 5)

    // Verify operating peak across non-calibration subsystems
    #expect(summary.peakOperatingReading?.sensorName == "PMU tdie2")
    #expect(summary.peakOperatingReading?.temperatureC == 50.0)
}

@Test func testTemperatureSummaryEmptyDieChannels() throws {
    let readings: [TemperatureReading] = [
        TemperatureReading(sensorName: "gas gauge battery", temperatureC: 32.0),
        TemperatureReading(sensorName: "PMU tcal", temperatureC: 51.8)
    ]

    let summary = TemperatureSummary(readings: readings)

    // If no Silicon Die channels exist, dieAverageC and peakDieReading must be nil (unavailable, NOT zero)
    #expect(summary.dieAverageC == nil)
    #expect(summary.dieSensorCount == 0)
    #expect(summary.peakDieReading == nil)
    #expect(summary.calibrationSensorCount == 1)
    #expect(summary.operatingSensorCount == 1)
    #expect(summary.peakOperatingReading?.sensorName == "gas gauge battery")
}

// MARK: - Power Source Parsing & State Transition Tests

@Test func testPowerSourceParsingBatteryOperation() throws {
    let descriptions: [[String: Any]] = [
        [
            "Current Capacity": NSNumber(value: 58),
            "Max Capacity": NSNumber(value: 100),
            "Is Charging": NSNumber(value: false),
            "Power Source State": "Battery Power"
        ]
    ]

    let result = PowerSourceReader.parse(sourceType: "Battery Power", descriptions: descriptions)
    #expect(result.mode == .battery)
    #expect(result.batteryPercent == 58)
    #expect(result.isCharging == false)
    #expect(result.isAdapterConnected == false)
}

@Test func testPowerSourceParsingExternalConnectedAndCharging() throws {
    let descriptions: [[String: Any]] = [
        [
            "Current Capacity": NSNumber(value: 65),
            "Max Capacity": NSNumber(value: 100),
            "Is Charging": NSNumber(value: true),
            "Power Source State": "AC Power"
        ]
    ]

    let result = PowerSourceReader.parse(sourceType: "AC Power", descriptions: descriptions)
    #expect(result.mode == .external)
    #expect(result.batteryPercent == 65)
    #expect(result.isCharging == true)
    #expect(result.isAdapterConnected == true)
}

@Test func testPowerSourceParsingExternalConnectedNotCharging() throws {
    // Adapter connected, but charge on hold or at 80%/100%
    let descriptions: [[String: Any]] = [
        [
            "Current Capacity": NSNumber(value: 80),
            "Max Capacity": NSNumber(value: 100),
            "Is Charging": NSNumber(value: false),
            "Power Source State": "AC Power"
        ]
    ]

    let result = PowerSourceReader.parse(sourceType: "AC Power", descriptions: descriptions)
    #expect(result.mode == .external)
    #expect(result.batteryPercent == 80)
    #expect(result.isCharging == false)
    #expect(result.isAdapterConnected == true)
}

@Test func testPowerSourceParsingAdapterPresentDrawingBattery() throws {
    // Physical adapter connected, but system drawing battery power
    let descriptions: [[String: Any]] = [
        [
            "Current Capacity": NSNumber(value: 45),
            "Max Capacity": NSNumber(value: 100),
            "Is Charging": NSNumber(value: false),
            "Power Source State": "AC Power"
        ]
    ]

    let result = PowerSourceReader.parse(sourceType: "Battery Power", descriptions: descriptions)
    #expect(result.mode == .battery)
    #expect(result.batteryPercent == 45)
    #expect(result.isCharging == false)
    #expect(result.isAdapterConnected == true)
}

@Test func testPowerSourceParsingDesktopMacNoBattery() throws {
    // Desktop Mac on AC power with no battery device
    let result = PowerSourceReader.parse(sourceType: "AC Power", descriptions: [])
    #expect(result.mode == .external)
    #expect(result.batteryPercent == nil)
    #expect(result.isCharging == nil)
    #expect(result.isAdapterConnected == nil)
}

@Test func testPowerSourceParsingUnknownAndUnavailable() throws {
    let result = PowerSourceReader.parse(sourceType: nil, descriptions: [])
    #expect(result.mode == .unknown)
    #expect(result.batteryPercent == nil)
    #expect(result.isCharging == nil)
    #expect(result.isAdapterConnected == nil)
}

// MARK: - Live Hardware Tests (Host Mac)

@Test func testSensorProbeSnapshotLive() async throws {
    let probe = SensorProbe()
    let snapshot = probe.read()
    #expect(!snapshot.thermalState.isEmpty)
    #expect(snapshot.powerMode != .unknown)
    #expect(!snapshot.temperatureReadings.isEmpty)

    let summary = snapshot.temperatureSummary
    #expect(summary.operatingSensorCount > 0)
    if let avg = summary.dieAverageC {
        #expect(avg >= 5.0 && avg <= 120.0)
    }
}

@Test func testTemperatureProbeExecutionLive() async throws {
    let result = TemperatureProbe.collectOnce()
    switch result {
    case .readings(let readings):
        #expect(!readings.isEmpty)
        for reading in readings {
            #expect(!reading.sensorName.isEmpty)
            #expect(reading.temperatureC >= 5.0 && reading.temperatureC <= 120.0)
        }
    case .noSensorsFound, .systemClientUnavailable, .noValidReadings:
        Issue.record("Live temperature enumeration failed unexpectedly on host Mac")
    }
}

@Test func testPowerSourceReaderLive() async throws {
    let power = PowerSourceReader.read()
    #expect(power.mode == .battery || power.mode == .external)
}
