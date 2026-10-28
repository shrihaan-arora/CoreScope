import AppKit
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

@Test func testSensorCategoryExclusivityAndCountConservation() throws {
    // Construct synthetic readings matching genuine Apple Silicon PMU naming patterns
    var readings: [TemperatureReading] = []

    // 24 Silicon Die channels
    for i in 1...14 {
        readings.append(TemperatureReading(id: "die-\(i)", sensorName: "PMU tdie\(i)", temperatureC: 38.0 + Double(i) * 0.2))
    }
    for i in 1...10 {
        readings.append(TemperatureReading(id: "die2-\(i)", sensorName: "PMU2 tdie\(i)", temperatureC: 35.0 + Double(i) * 0.2))
    }

    // 10 Device Node channels
    for i in 2...8 {
        readings.append(TemperatureReading(id: "dev-\(i)", sensorName: "PMU tdev\(i)", temperatureC: 34.0 + Double(i) * 0.1))
    }
    for i in [2, 4, 5] {
        readings.append(TemperatureReading(id: "dev2-\(i)", sensorName: "PMU2 tdev\(i)", temperatureC: 33.0 + Double(i) * 0.1))
    }

    // 6 Battery channels (same product descriptor, unique channel IDs)
    for i in 1...6 {
        readings.append(TemperatureReading(id: "battery-\(i)", sensorName: "gas gauge battery", temperatureC: 31.0 + Double(i) * 0.1))
    }

    // 1 Storage channel
    readings.append(TemperatureReading(id: "nand-0", sensorName: "NAND CH0 temp", temperatureC: 33.0))

    // 2 Calibration / Reference channels
    readings.append(TemperatureReading(id: "cal-1", sensorName: "PMU tcal", temperatureC: 51.8))
    readings.append(TemperatureReading(id: "cal-2", sensorName: "PMU2 tcal", temperatureC: 51.8))

    // Total count must be 24 + 10 + 6 + 1 + 2 = 43
    #expect(readings.count == 43)

    // 1. Every unique sensor reading appears in exactly one category
    let grouped = Dictionary(grouping: readings, by: \.category)
    var seenIds = Set<String>()
    for (_, catReadings) in grouped {
        for reading in catReadings {
            #expect(!seenIds.contains(reading.id), "Reading \(reading.id) appeared in multiple categories")
            seenIds.insert(reading.id)
        }
    }
    #expect(seenIds.count == readings.count)

    // 2. The sum of category counts equals the total number of unique readings
    let sumCategoryCounts = SensorCategory.allCases.map { grouped[$0]?.count ?? 0 }.reduce(0, +)
    #expect(sumCategoryCounts == readings.count)
    #expect(grouped[.siliconDie]?.count == 24)
    #expect(grouped[.deviceNode]?.count == 10)
    #expect(grouped[.battery]?.count == 6)
    #expect(grouped[.storage]?.count == 1)
    #expect(grouped[.calibration]?.count == 2)
    #expect(grouped[.system]?.count == nil || grouped[.system]?.count == 0)

    // 3. Calibration channels are excluded from operating-temperature summaries
    let summary = TemperatureSummary(readings: readings)
    #expect(summary.calibrationSensorCount == 2)
    #expect(summary.operatingSensorCount == 41)
    #expect(summary.peakOperatingReading?.category != .calibration)

    // 4. The die average includes only validated die channels
    #expect(summary.dieSensorCount == 24)
    let dieOnlySum = readings.filter { $0.category == .siliconDie }.reduce(0.0) { $0 + $1.temperatureC }
    let expectedDieAvg = dieOnlySum / 24.0
    #expect(summary.dieAverageC == expectedDieAvg)
    #expect(summary.peakDieReading?.category == .siliconDie)
}

@Test func testMissingCategoriesDisplayUnavailableRatherThanZero() throws {
    // Readings containing ONLY battery and calibration sensors (NO die sensors)
    let readings: [TemperatureReading] = [
        TemperatureReading(id: "bat-1", sensorName: "gas gauge battery", temperatureC: 32.0),
        TemperatureReading(id: "cal-1", sensorName: "PMU tcal", temperatureC: 51.8)
    ]

    let summary = TemperatureSummary(readings: readings)

    // 5. Missing categories display unavailable rather than zero
    #expect(summary.dieSensorCount == 0)
    #expect(summary.dieAverageC == nil)
    #expect(summary.peakDieReading == nil)

    // Check formatted text representation explicitly
    #expect(summary.formattedDieAverage == "Unavailable")
    #expect(summary.formattedDieAverage != "0.0 °C")
    #expect(summary.formattedDieAverage != "0 °C")
    #expect(summary.formattedDieAverage != "0")
    #expect(summary.formattedPeakDie == "Unavailable")
    #expect(summary.formattedPeakDie != "0.0 °C")

    // Empty reading set
    let emptySummary = TemperatureSummary(readings: [])
    #expect(emptySummary.dieAverageC == nil)
    #expect(emptySummary.formattedDieAverage == "Unavailable")
    #expect(emptySummary.formattedPeakDie == "Unavailable")
    #expect(emptySummary.peakOperatingReading == nil)
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

    let readings = snapshot.temperatureReadings

    // 1. Every reading has a non-empty and unique ID
    let uniqueIds = Set(readings.map(\.id))
    #expect(uniqueIds.count == readings.count, "Each reading must have a unique identifier")

    // 2. Category exclusivity and sum equals total readings
    let grouped = Dictionary(grouping: readings, by: \.category)
    let sumCategoryCounts = SensorCategory.allCases.map { grouped[$0]?.count ?? 0 }.reduce(0, +)
    #expect(sumCategoryCounts == readings.count, "Sum of category counts must equal total readings")

    // On Apple M4 MacBook Air: exactly 43 channels (24 die, 10 device, 6 battery, 1 storage, 2 calibration)
    #expect(readings.count == 43)
    #expect(grouped[.siliconDie]?.count == 24)
    #expect(grouped[.deviceNode]?.count == 10)
    #expect(grouped[.battery]?.count == 6)
    #expect(grouped[.storage]?.count == 1)
    #expect(grouped[.calibration]?.count == 2)

    let summary = snapshot.temperatureSummary
    #expect(summary.operatingSensorCount == 41)
    #expect(summary.calibrationSensorCount == 2)
    #expect(summary.dieSensorCount == 24)

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

@Test func testAmbientAssetLoaderSafeExecution() throws {
    // 1. Invoking AmbientAssetLoader.image must never trigger fatalError, crash, or throw
    let img = AmbientAssetLoader.image
    if let img = img {
        #expect(img.isValid)
        #expect(img.size.width > 0)
        #expect(img.size.height > 0)
    }

    // 2. Safe graceful fallback: nonexistent file path returns nil without fatalError
    let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_ambient_\(UUID().uuidString).png")
    #expect(!FileManager.default.fileExists(atPath: nonExistentURL.path))
    #expect(NSImage(contentsOf: nonExistentURL) == nil)
}
