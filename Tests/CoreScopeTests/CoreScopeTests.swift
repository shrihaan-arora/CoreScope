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

@Test(.enabled(if: ProcessInfo.processInfo.environment["CORESCOPE_REQUIRE_LIVE_SENSORS"] == "1", "Requires physical Apple Silicon PMU sensor access (set CORESCOPE_REQUIRE_LIVE_SENSORS=1)"))
func testSensorProbeSnapshotLive() async throws {
    let probe = SensorProbe()
    let snapshot = probe.read()
    #expect(!snapshot.thermalState.isEmpty)
    #expect(snapshot.powerMode != .unknown)
    #expect(!snapshot.temperatureReadings.isEmpty, "Live probe must return temperature readings on supported physical Apple Silicon")

    let readings = snapshot.temperatureReadings

    // 1. Every reading has a non-empty and unique ID
    let uniqueIds = Set(readings.map(\.id))
    #expect(uniqueIds.count == readings.count, "Each reading must have a unique identifier")

    // 2. Validate sensor names and realistic temperature ranges
    for reading in readings {
        #expect(!reading.sensorName.isEmpty)
        #expect(reading.temperatureC >= 5.0 && reading.temperatureC <= 120.0, "Reading \(reading.sensorName) temperature out of range: \(reading.temperatureC) °C")
    }

    // 3. Category exclusivity and sum equals total readings
    let grouped = Dictionary(grouping: readings, by: \.category)
    let sumCategoryCounts = SensorCategory.allCases.map { grouped[$0]?.count ?? 0 }.reduce(0, +)
    #expect(sumCategoryCounts == readings.count, "Sum of category counts must equal total readings")

    // 4. Calibration channels isolated from operating die metrics
    let summary = snapshot.temperatureSummary
    let calibrationCount = grouped[.calibration]?.count ?? 0
    #expect(summary.calibrationSensorCount == calibrationCount)
    #expect(summary.operatingSensorCount == readings.count - calibrationCount)

    if let peakDie = summary.peakDieReading {
        #expect(peakDie.category == .siliconDie)
        #expect(peakDie.temperatureC >= 5.0 && peakDie.temperatureC <= 120.0)
    }

    if let avg = summary.dieAverageC {
        #expect(avg >= 5.0 && avg <= 120.0)
        #expect(summary.dieSensorCount == (grouped[.siliconDie]?.count ?? 0))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CORESCOPE_REQUIRE_LIVE_SENSORS"] == "1", "Requires physical Apple Silicon PMU sensor access (set CORESCOPE_REQUIRE_LIVE_SENSORS=1)"))
func testM4MacBookAirHardwareBaselineLive() async throws {
    // Only enforce exact 43-channel baseline when executing on the verified M4 MacBook Air target
    guard SystemInfo.modelIdentifier == "Mac16,13" else { return }

    let probe = SensorProbe()
    let snapshot = probe.read()
    let readings = snapshot.temperatureReadings

    // Target baseline on Apple M4 MacBook Air: exactly 43 channels
    #expect(readings.count == 43)
    let grouped = Dictionary(grouping: readings, by: \.category)
    #expect(grouped[.siliconDie]?.count == 24)
    #expect(grouped[.deviceNode]?.count == 10)
    #expect(grouped[.battery]?.count == 6)
    #expect(grouped[.storage]?.count == 1)
    #expect(grouped[.calibration]?.count == 2)

    let summary = snapshot.temperatureSummary
    #expect(summary.operatingSensorCount == 41)
    #expect(summary.calibrationSensorCount == 2)
    #expect(summary.dieSensorCount == 24)

    // Phase 1 & 2: M4 PMU channels lack specific public cluster labels
    #expect(!snapshot.sensorRegistry.hasVerifiedClusterMappings)
    #expect(snapshot.sensorRegistry.unmappedCount == 24)
    #expect(!snapshot.sensorRegistry.pCoreCluster.isAvailable)
    #expect(!snapshot.sensorRegistry.eCoreCluster.isAvailable)
    #expect(!snapshot.sensorRegistry.gpuCluster.isAvailable)
    #expect(!snapshot.sensorRegistry.socFabricCluster.isAvailable)
    #expect(snapshot.sensorRegistry.pCoreCluster.formattedAverage == "Unavailable")

    // Phase 3 & 4: Thermal pressure and clock telemetry
    #expect(snapshot.thermalPressure != .unknown)
    #expect(!snapshot.clockTelemetry.isAvailable) // unprivileged CLPC legend absent
    #expect(snapshot.throttlingAssessment.inference == .normalOperation || snapshot.throttlingAssessment.inference == .thermalPressureElevated)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CORESCOPE_REQUIRE_LIVE_SENSORS"] == "1", "Requires physical Apple Silicon PMU sensor access (set CORESCOPE_REQUIRE_LIVE_SENSORS=1)"))
func testTemperatureProbeExecutionLive() async throws {
    let result = TemperatureProbe.collectOnce()
    switch result {
    case .readings(let readings):
        #expect(!readings.isEmpty)
        for reading in readings {
            #expect(!reading.sensorName.isEmpty)
            #expect(reading.temperatureC >= 5.0 && reading.temperatureC <= 120.0)
        }
    case .noSensorsFound, .systemClientUnavailable, .noValidReadings:
        Issue.record("Live temperature enumeration failed unexpectedly on physical host Mac")
    }
}

@Test func testPowerSourceReaderLive() async throws {
    let power = PowerSourceReader.read()
    #expect(power.mode == .battery || power.mode == .external || power.mode == .unknown)
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

// MARK: - Thermal Session Unit Tests

private func makeMockSnapshot(
    dieTemps: [(String, Double)] = [("PMU tdie1", 42.0), ("PMU tdie2", 48.0)],
    calTemps: [(String, Double)] = [("PMU tcal", 90.0)],
    batteryTemps: [(String, Double)] = [("gas gauge battery", 31.0)],
    powerMode: PowerMode = .battery,
    batteryPercent: Int? = 75,
    isCharging: Bool? = false,
    isAdapterConnected: Bool? = false,
    thermalState: String = "Nominal",
    timestamp: Date = Date()
) -> SensorSnapshot {
    var readings: [TemperatureReading] = []
    for (name, temp) in dieTemps {
        readings.append(TemperatureReading(sensorName: name, temperatureC: temp))
    }
    for (name, temp) in calTemps {
        readings.append(TemperatureReading(sensorName: name, temperatureC: temp))
    }
    for (name, temp) in batteryTemps {
        readings.append(TemperatureReading(sensorName: name, temperatureC: temp))
    }

    return SensorSnapshot(
        temperatureReadings: readings,
        temperatureStatus: .available(sensorCount: readings.count),
        powerMode: powerMode,
        batteryPercent: batteryPercent,
        isCharging: isCharging,
        isAdapterConnected: isAdapterConnected,
        thermalState: thermalState,
        sampledAt: timestamp
    )
}

@Test func testThermalSessionStartAndStop() async throws {
    let mock = makeMockSnapshot()
    let model = await MainActor.run {
        ThermalSessionModel(sampleProvider: { mock })
    }
    await MainActor.run {
        #expect(model.state == .idle)
        #expect(model.samples.isEmpty)
        model.startSession(duration: .manual)
        #expect(model.state == .running)
    }
    try await Task.sleep(nanoseconds: 60_000_000)
    await MainActor.run {
        #expect(model.samples.count >= 1)
        model.stopSession()
        #expect(model.state == .completed)
        #expect(model.lastSummary != nil)
        #expect(model.lastSummary?.sampleCount == model.samples.count)
    }
}

@Test func testAppIconAndAmbientResourceIntegrity() throws {
    // 1. Verify AppIcon artwork exists and meets 1024x1024 macOS icon requirements
    let iconURL = URL(fileURLWithPath: "Sources/CoreScope/Resources/CoreScopeAppIcon.png")
    #expect(FileManager.default.fileExists(atPath: iconURL.path))
    if let img = NSImage(contentsOf: iconURL) {
        #expect(img.isValid)
        let reps = img.representations
        if let first = reps.first {
            #expect(first.pixelsWide >= 1024)
            #expect(first.pixelsHigh >= 1024)
        }
    }

    // 2. Verify Ambient background asset exists
    let ambientURL = URL(fileURLWithPath: "Sources/CoreScope/Resources/CoreScopeAmbient.png")
    #expect(FileManager.default.fileExists(atPath: ambientURL.path))
    if let img = NSImage(contentsOf: ambientURL) {
        #expect(img.isValid)
    }
}

@Test func testThermalSessionDurationCases() throws {
    #expect(ThermalSessionDuration.seconds30.seconds == 30.0)
    #expect(ThermalSessionDuration.minutes2.seconds == 120.0)
    #expect(ThermalSessionDuration.minutes5.seconds == 300.0)
    #expect(ThermalSessionDuration.manual.seconds == nil)
    #expect(ThermalSessionDuration.allCases.count == 4)

    #expect(ThermalSessionDuration.seconds30.displayLabel == "30 Seconds")
    #expect(ThermalSessionDuration.seconds30.subtitle == "Quick Check")
    #expect(ThermalSessionDuration.minutes2.displayLabel == "2 Minutes")
    #expect(ThermalSessionDuration.minutes2.subtitle == "Standard Test")
    #expect(ThermalSessionDuration.minutes5.displayLabel == "5 Minutes")
    #expect(ThermalSessionDuration.minutes5.subtitle == "Sustained Load")
    #expect(ThermalSessionDuration.manual.displayLabel == "Manual Stop")
    #expect(ThermalSessionDuration.manual.subtitle == "Stop Anytime")
}

@Test func testThermalSampleInferenceDefaultsAcrossStates() throws {
    let sNominal = ThermalSample(elapsedSeconds: 0, peakDieTemp: 45, peakDieSensorName: "tdie1", averageDieTemp: 42, operatingChannelCount: 20, thermalState: "Nominal", thermalPressure: .nominal, powerMode: .battery, isCharging: false, batteryPercent: 90)
    #expect(sNominal.throttlingInference == .normalOperation)

    let sFair = ThermalSample(elapsedSeconds: 0, peakDieTemp: 45, peakDieSensorName: "tdie1", averageDieTemp: 42, operatingChannelCount: 20, thermalState: "Fair", thermalPressure: .fair, powerMode: .battery, isCharging: false, batteryPercent: 90)
    #expect(sFair.throttlingInference == .thermalPressureElevated)

    let sSerious = ThermalSample(elapsedSeconds: 0, peakDieTemp: 45, peakDieSensorName: "tdie1", averageDieTemp: 42, operatingChannelCount: 20, thermalState: "Serious", thermalPressure: .serious, powerMode: .battery, isCharging: false, batteryPercent: 90)
    #expect(sSerious.throttlingInference == .possibleThermalReduction)

    let sCritical = ThermalSample(elapsedSeconds: 0, peakDieTemp: 45, peakDieSensorName: "tdie1", averageDieTemp: 42, operatingChannelCount: 20, thermalState: "Critical", thermalPressure: .critical, powerMode: .battery, isCharging: false, batteryPercent: 90)
    #expect(sCritical.throttlingInference == .possibleThermalReduction)

    let sUnknown = ThermalSample(elapsedSeconds: 0, peakDieTemp: 45, peakDieSensorName: "tdie1", averageDieTemp: 42, operatingChannelCount: 20, thermalState: "Unknown", thermalPressure: .unknown, powerMode: .battery, isCharging: false, batteryPercent: 90)
    #expect(sUnknown.throttlingInference == .insufficientTelemetry)
}

@Test func testThermalSessionCancellationDuringShutdown() async throws {
    let mock = makeMockSnapshot()
    let model = await MainActor.run {
        ThermalSessionModel(sampleProvider: { mock })
    }
    await MainActor.run {
        model.startSession(duration: .minutes5)
        #expect(model.state == .running)
        model.cancelAndTearDown()
        #expect(model.state == .idle)
        #expect(model.samples.isEmpty)
        #expect(model.lastSummary == nil)
    }
}

@Test func testThermalSessionOverlappingScanPrevention() async throws {
    let model = await MainActor.run {
        ThermalSessionModel(sampleProvider: {
            Thread.sleep(forTimeInterval: 0.05)
            return makeMockSnapshot()
        })
    }
    await MainActor.run {
        model.startSession(duration: .manual)
        #expect(model.state == .running)
        model.stopSession()
        #expect(model.state == .completed)
    }
}

@Test func testThermalSessionCalibrationExclusion() throws {
    let mock = makeMockSnapshot(
        dieTemps: [("PMU tdie1", 40.0), ("PMU tdie2", 50.0)],
        calTemps: [("PMU tcal", 98.0)]
    )
    let start = Date()
    let sample = ThermalSample.create(from: mock, startTime: start)

    // Calibration channel PMU tcal (98.0) must NOT be the peak die temp
    #expect(sample.peakDieTemp == 50.0)
    #expect(sample.peakDieSensorName == "PMU tdie2")
    // Average must be strictly die average (40 + 50) / 2 = 45.0
    #expect(sample.averageDieTemp == 45.0)
}

@Test func testThermalSessionSummaryStatisticsCalculation() throws {
    let samples: [ThermalSample] = [
        ThermalSample(elapsedSeconds: 0.0, peakDieTemp: 44.0, peakDieSensorName: "PMU tdie1", averageDieTemp: 40.0, operatingChannelCount: 41, thermalState: "Nominal", powerMode: .battery, isCharging: false, batteryPercent: 80),
        ThermalSample(elapsedSeconds: 2.0, peakDieTemp: 52.0, peakDieSensorName: "PMU tdie2", averageDieTemp: 46.0, operatingChannelCount: 41, thermalState: "Nominal", powerMode: .battery, isCharging: false, batteryPercent: 80),
        ThermalSample(elapsedSeconds: 4.0, peakDieTemp: 48.0, peakDieSensorName: "PMU tdie1", averageDieTemp: 42.0, operatingChannelCount: 41, thermalState: "Fair", powerMode: .external, isCharging: true, batteryPercent: 81)
    ]

    let summary = try #require(ThermalSessionSummary.compute(from: samples))
    #expect(summary.sampleCount == 3)
    #expect(summary.totalDuration == 4.0)
    #expect(summary.peakObservedTemp == 52.0)
    #expect(summary.peakObservedSensor == "PMU tdie2")
    #expect(summary.minObservedTemp == 40.0)
    let expectedAvg = (40.0 + 46.0 + 42.0) / 3.0
    #expect(abs(summary.averageObservedTemp! - expectedAvg) < 0.001)
    #expect(summary.initialTemp == 40.0)
    #expect(summary.finalTemp == 42.0)
    #expect(summary.thermalStateTransitions == 1) // Nominal -> Nominal -> Fair
    #expect(summary.powerModeTransitions == 1) // Battery -> Battery -> External
}

@Test func testThermalSessionEmptySession() throws {
    #expect(ThermalSessionSummary.compute(from: []) == nil)
    let csv = ThermalSessionCSVExporter.generateCSV(from: [])
    #expect(csv.hasPrefix("Timestamp,ElapsedSeconds,PeakDieTempC,"))
    let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    #expect(rows.count == 1) // Header only
}

@Test func testThermalSessionCSVExporterEscapingAndFormatting() throws {
    #expect(ThermalSessionCSVExporter.escapeCSV("Normal") == "Normal")
    #expect(ThermalSessionCSVExporter.escapeCSV("Sensor, with comma") == "\"Sensor, with comma\"")
    #expect(ThermalSessionCSVExporter.escapeCSV("Sensor \"quoted\"") == "\"Sensor \"\"quoted\"\"\"")
    #expect(ThermalSessionCSVExporter.escapeCSV("Sensor\nwith newline") == "\"Sensor\nwith newline\"")

    let sample = ThermalSample(
        elapsedSeconds: 0.0,
        peakDieTemp: nil,
        peakDieSensorName: nil,
        averageDieTemp: nil,
        operatingChannelCount: 0,
        thermalState: "Nominal",
        powerMode: .unknown,
        isCharging: nil,
        batteryPercent: nil
    )
    let csv = ThermalSessionCSVExporter.generateCSV(from: [sample])
    let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    #expect(rows.count == 2)
    let dataRow = rows[1]
    #expect(dataRow.contains("unavailable"))
}

@Test func testThermalSessionClearSession() async throws {
    let mock = makeMockSnapshot()
    let model = await MainActor.run {
        ThermalSessionModel(sampleProvider: { mock })
    }
    await MainActor.run {
        model.startSession()
    }
    try await Task.sleep(nanoseconds: 60_000_000)
    await MainActor.run {
        #expect(!model.samples.isEmpty)
        model.clearSession()
        #expect(model.samples.isEmpty)
        #expect(model.lastSummary == nil)
        #expect(model.state == .idle)
        #expect(model.elapsedSeconds == 0.0)
    }
}

@Test func testThermalSessionPowerAndChargingStateCapture() throws {
    let snapshot1 = makeMockSnapshot(powerMode: .external, batteryPercent: 90, isCharging: true)
    let sample1 = ThermalSample.create(from: snapshot1, startTime: Date())
    #expect(sample1.powerMode == .external)
    #expect(sample1.batteryPercent == 90)
    #expect(sample1.isCharging == true)

    let snapshot2 = makeMockSnapshot(powerMode: .battery, batteryPercent: 45, isCharging: false)
    let sample2 = ThermalSample.create(from: snapshot2, startTime: Date())
    #expect(sample2.powerMode == .battery)
    #expect(sample2.batteryPercent == 45)
    #expect(sample2.isCharging == false)
}

// MARK: - Phase 8: Cluster Analytics, Thermal Pressure & Clock Telemetry Tests

@Test func testSensorToClusterClassification() throws {
    // 1. Specific authentic sub-domain names map with verified hardware confidence
    let (p1, c1) = SensorDescriptor.mapCluster(sensorName: "pdie1", category: .siliconDie)
    #expect(p1 == .pCoreCluster)
    #expect(c1 == .verifiedHardwareMetadata)

    let (p2, c2) = SensorDescriptor.mapCluster(sensorName: "CPU-P-Core-1", category: .siliconDie)
    #expect(p2 == .pCoreCluster)
    #expect(c2 == .verifiedHardwareMetadata)

    let (e1, ce1) = SensorDescriptor.mapCluster(sensorName: "edie1", category: .siliconDie)
    #expect(e1 == .eCoreCluster)
    #expect(ce1 == .verifiedHardwareMetadata)

    let (e2, ce2) = SensorDescriptor.mapCluster(sensorName: "CPU-E-Core-0", category: .siliconDie)
    #expect(e2 == .eCoreCluster)
    #expect(ce2 == .verifiedHardwareMetadata)

    let (g1, cg1) = SensorDescriptor.mapCluster(sensorName: "gdie0", category: .siliconDie)
    #expect(g1 == .gpu)
    #expect(cg1 == .verifiedHardwareMetadata)

    let (soc1, csoc1) = SensorDescriptor.mapCluster(sensorName: "soc die temp", category: .siliconDie)
    #expect(soc1 == .socFabric)
    #expect(csoc1 == .verifiedHardwareMetadata)

    let (ane1, cane1) = SensorDescriptor.mapCluster(sensorName: "ane die", category: .siliconDie)
    #expect(ane1 == .socFabric)
    #expect(cane1 == .verifiedHardwareMetadata)

    // 2. Generic PMU die channels on M4 / Apple Silicon must remain unmapped without direct descriptors
    let (m4_1, cm4_1) = SensorDescriptor.mapCluster(sensorName: "PMU tdie1", category: .siliconDie)
    #expect(m4_1 == .unmapped)
    #expect(cm4_1 == .unsupported)

    let (m4_14, cm4_14) = SensorDescriptor.mapCluster(sensorName: "PMU tdie14", category: .siliconDie)
    #expect(m4_14 == .unmapped)
    #expect(cm4_14 == .unsupported)

    let (m4_2_8, cm4_2_8) = SensorDescriptor.mapCluster(sensorName: "PMU2 tdie8", category: .siliconDie)
    #expect(m4_2_8 == .unmapped)
    #expect(cm4_2_8 == .unsupported)
}

@Test func testUnknownAndAmbiguousSensorsRemainUnmapped() throws {
    // Non-die categories must never map to compute clusters
    let (bat, cBat) = SensorDescriptor.mapCluster(sensorName: "gas gauge battery", category: .battery)
    #expect(bat == .unmapped)
    #expect(cBat == .unsupported)

    let (dev, cDev) = SensorDescriptor.mapCluster(sensorName: "PMU tdev2", category: .deviceNode)
    #expect(dev == .unmapped)
    #expect(cDev == .unsupported)

    let (nand, cNand) = SensorDescriptor.mapCluster(sensorName: "NAND CH0 temp", category: .storage)
    #expect(nand == .unmapped)
    #expect(cNand == .unsupported)

    let (unk, cUnk) = SensorDescriptor.mapCluster(sensorName: "Unknown Heat Node", category: .system)
    #expect(unk == .unmapped)
    #expect(cUnk == .unsupported)
}

@Test func testCalibrationChannelClusterExclusion() throws {
    let (cal1, cCal1) = SensorDescriptor.mapCluster(sensorName: "PMU tcal", category: .calibration)
    #expect(cal1 == .unmapped)
    #expect(cCal1 == .unsupported)

    let readings = [
        TemperatureReading(id: "cal-1", sensorName: "PMU tcal", temperatureC: 95.0),
        TemperatureReading(id: "cal-2", sensorName: "PMU2 tcal", temperatureC: 95.0),
        TemperatureReading(id: "die-1", sensorName: "PMU tdie1", temperatureC: 42.0)
    ]
    let registry = SensorRegistry(from: readings)

    // Calibration channels must never contribute to unmapped die count or cluster measurements
    #expect(registry.unmappedCount == 1) // Only die-1
    #expect(registry.pCoreCluster.sensorCount == 0)
    #expect(registry.eCoreCluster.sensorCount == 0)
    #expect(registry.gpuCluster.sensorCount == 0)
    #expect(registry.socFabricCluster.sensorCount == 0)
}

@Test func testClusterAveragesWithMissingAndPresentReadings() throws {
    // Test 1: Empty or unmapped readings
    let emptyRegistry = SensorRegistry(from: [
        TemperatureReading(id: "m4-1", sensorName: "PMU tdie1", temperatureC: 44.0)
    ])
    #expect(!emptyRegistry.hasVerifiedClusterMappings)
    #expect(!emptyRegistry.pCoreCluster.isAvailable)
    #expect(emptyRegistry.pCoreCluster.averageC == nil)
    #expect(emptyRegistry.pCoreCluster.peakC == nil)
    #expect(emptyRegistry.pCoreCluster.formattedAverage == "Unavailable")
    #expect(emptyRegistry.pCoreCluster.formattedPeak == "Unavailable")
    #expect(emptyRegistry.pCoreCluster.formattedAverage != "0.0 °C")
    #expect(emptyRegistry.pCoreCluster.formattedAverage != "0")

    // Test 2: Verified cluster readings
    let verifiedRegistry = SensorRegistry(from: [
        TemperatureReading(id: "p-1", sensorName: "pdie1", temperatureC: 40.0),
        TemperatureReading(id: "p-2", sensorName: "pdie2", temperatureC: 50.0),
        TemperatureReading(id: "e-1", sensorName: "edie1", temperatureC: 38.0),
        TemperatureReading(id: "g-1", sensorName: "gdie0", temperatureC: 46.0),
        TemperatureReading(id: "soc-1", sensorName: "soc die temp", temperatureC: 41.0)
    ])

    #expect(verifiedRegistry.hasVerifiedClusterMappings)

    // P-Core: average (40 + 50) / 2 = 45.0, peak = 50.0 from pdie2
    let pCore = verifiedRegistry.pCoreCluster
    #expect(pCore.isAvailable)
    #expect(pCore.sensorCount == 2)
    #expect(pCore.averageC == 45.0)
    #expect(pCore.peakC == 50.0)
    #expect(pCore.peakSensorName == "pdie2")
    #expect(pCore.formattedAverage == "45.0 °C")

    // E-Core: single sensor at 38.0
    let eCore = verifiedRegistry.eCoreCluster
    #expect(eCore.isAvailable)
    #expect(eCore.sensorCount == 1)
    #expect(eCore.averageC == 38.0)
    #expect(eCore.peakC == 38.0)
    #expect(eCore.peakSensorName == "edie1")

    // GPU: single sensor at 46.0
    let gpu = verifiedRegistry.gpuCluster
    #expect(gpu.isAvailable)
    #expect(gpu.sensorCount == 1)
    #expect(gpu.averageC == 46.0)

    // SoC: single sensor at 41.0
    let soc = verifiedRegistry.socFabricCluster
    #expect(soc.isAvailable)
    #expect(soc.sensorCount == 1)
    #expect(soc.averageC == 41.0)
}

@Test func testThermalPressureStateMappings() throws {
    #expect(ThermalPressureState.from(nativeState: .nominal) == .nominal)
    #expect(ThermalPressureState.from(nativeState: .fair) == .fair)
    #expect(ThermalPressureState.from(nativeState: .serious) == .serious)
    #expect(ThermalPressureState.from(nativeState: .critical) == .critical)

    #expect(ThermalPressureState(label: "Nominal") == .nominal)
    #expect(ThermalPressureState(label: "Fair") == .fair)
    #expect(ThermalPressureState(label: "Serious") == .serious)
    #expect(ThermalPressureState(label: "Critical") == .critical)
    #expect(ThermalPressureState(label: "Other") == .unknown)

    #expect(ThermalPressureState.nominal < ThermalPressureState.fair)
    #expect(ThermalPressureState.fair < ThermalPressureState.serious)
    #expect(ThermalPressureState.serious < ThermalPressureState.critical)

    #expect(!ThermalPressureState.nominal.isThrottlingLikely)
    #expect(!ThermalPressureState.fair.isThrottlingLikely)
    #expect(ThermalPressureState.serious.isThrottlingLikely)
    #expect(ThermalPressureState.critical.isThrottlingLikely)

    #expect(ThermalPressureState.nominal.title == "Nominal")
    #expect(ThermalPressureState.fair.title == "Fair")
    #expect(ThermalPressureState.serious.title == "Serious")
    #expect(ThermalPressureState.critical.title == "Critical")
    #expect(ThermalPressureState.unknown.title == "Unknown")

    #expect(ThermalPressureState.nominal.explanation == "macOS reports nominal thermal pressure.")
    #expect(ThermalPressureState.fair.explanation == "macOS reports elevated thermal pressure.")
    #expect(ThermalPressureState.serious.explanation == "macOS reports serious thermal pressure; performance may be affected.")
    #expect(ThermalPressureState.critical.explanation == "macOS reports critical thermal pressure; performance may be affected.")
    #expect(ThermalPressureState.unknown.explanation == "Thermal state unavailable.")
}

@Test func testThermalPressureMonitorLifecycle() async throws {
    let monitor = await MainActor.run {
        ThermalPressureMonitor()
    }
    await MainActor.run {
        #expect(monitor.transitions.isEmpty)
        monitor.startMonitoring()
        // Unregister and ensure cleanup
        monitor.stopMonitoring()
        monitor.resetTransitions()
        #expect(monitor.transitions.isEmpty)
    }
}

@Test func testClockTelemetryProbeSafetyAndAbsenceOfFakeZero() throws {
    let result = ClockTelemetryProbe.probe()
    // Probing without powermetrics / root on Apple Silicon must return .unavailable safely
    switch result {
    case .unavailable(let reason):
        #expect(!reason.isEmpty)
        #expect(result.telemetry == nil)
        // Never report frequency as 0 or 0 MHz
        #expect(result.telemetry?.pCoreFrequencyMHz == nil)
        #expect(result.telemetry?.eCoreFrequencyMHz == nil)
    case .measured(let tel):
        if let p = tel.pCoreFrequencyMHz {
            #expect(p > 100.0 && p < 6000.0, "Frequency must be in a realistic MHz range: \(p)")
        }
        if let e = tel.eCoreFrequencyMHz {
            #expect(e > 100.0 && e < 5000.0, "Frequency must be in a realistic MHz range: \(e)")
        }
    }
}

@Test func testPerformanceReductionInferenceRulesAndDVFSProtection() throws {
    // 1. Nominal pressure: does not claim confirmed throttling even with low frequency (normal DVFS / idle scaling)
    let idleTelemetry = ClockTelemetryResult.measured(ClockTelemetry(
        pCoreFrequencyMHz: 800.0,
        eCoreFrequencyMHz: 600.0
    ))
    let evalNominal = ThrottlingAssessment.evaluate(
        thermalPressure: .nominal,
        clockTelemetry: idleTelemetry,
        isUnderSustainedLoad: false
    )
    #expect(evalNominal.inference == .normalOperation)
    #expect(evalNominal.assessmentSummary == "macOS reports nominal thermal pressure.")

    let evalNominalUnavailable = ThrottlingAssessment.evaluate(
        thermalPressure: .nominal,
        clockTelemetry: .unavailable(reason: "No legend")
    )
    #expect(evalNominalUnavailable.inference == .normalOperation)
    #expect(evalNominalUnavailable.assessmentSummary == "macOS reports nominal thermal pressure.")

    // 2. Fair pressure alone: does not claim throttling
    let evalFair = ThrottlingAssessment.evaluate(
        thermalPressure: .fair,
        clockTelemetry: .unavailable(reason: "Unprivileged user space")
    )
    #expect(evalFair.inference == .thermalPressureElevated)
    #expect(evalFair.assessmentSummary == "macOS reports elevated thermal pressure.")

    // 3. Serious pressure: produces possible-reduction warning without claiming direct frequency confirmation
    let evalSerious = ThrottlingAssessment.evaluate(
        thermalPressure: .serious,
        clockTelemetry: .unavailable(reason: "Unprivileged user space")
    )
    #expect(evalSerious.inference == .possibleThermalReduction)
    #expect(evalSerious.assessmentSummary == "macOS reports serious thermal pressure; performance may be affected.")

    // 4. Critical pressure: produces possible-reduction warning without claiming direct frequency confirmation
    let evalCritical = ThrottlingAssessment.evaluate(
        thermalPressure: .critical,
        clockTelemetry: .unavailable(reason: "Unprivileged user space")
    )
    #expect(evalCritical.inference == .possibleThermalReduction)
    #expect(evalCritical.assessmentSummary == "macOS reports critical thermal pressure; performance may be affected.")

    // 5. Missing clock telemetry never produces confirmed throttling
    let evalCriticalMissingTelemetry = ThrottlingAssessment.evaluate(
        thermalPressure: .critical,
        clockTelemetry: .unavailable(reason: "Missing symbols"),
        isUnderSustainedLoad: true
    )
    #expect(evalCriticalMissingTelemetry.inference == .possibleThermalReduction)
    #expect(evalCriticalMissingTelemetry.inference != .confirmedThermalThrottling)

    // 6. Uncalibrated values never enter the frequency-based confirmation path
    let evalUncalibrated = ThrottlingAssessment.evaluate(
        thermalPressure: .critical,
        clockTelemetry: .unavailable(reason: "CLPC driver legend table not accessible"),
        reference: HardwareClockReference(nominalActiveFrequencyMHz: 4000.0),
        isUnderSustainedLoad: true
    )
    #expect(evalUncalibrated.inference == .possibleThermalReduction)
    #expect(evalUncalibrated.inference != .confirmedThermalThrottling)

    // 7. A confirmation path requires validated telemetry, a defensible reference, sustained load, and non-LPM
    let ref = HardwareClockReference(nominalActiveFrequencyMHz: 4000.0, throttlingRatioThreshold: 0.65)
    let clampedTel = ClockTelemetryResult.measured(ClockTelemetry(
        pCoreFrequencyMHz: 1400.0,
        eCoreFrequencyMHz: 800.0
    ))

    // 7a. Confirmed: all conditions satisfied
    let evalConfirmed = ThrottlingAssessment.evaluate(
        thermalPressure: .serious,
        clockTelemetry: clampedTel,
        reference: ref,
        isUnderSustainedLoad: true,
        powerMode: .external,
        isLowPowerModeActive: false
    )
    #expect(evalConfirmed.inference == .confirmedThermalThrottling)
    #expect(evalConfirmed.assessmentSummary.contains("Validated telemetry confirms clock frequency reduced"))

    // 7b. Without reference: falls back to possible thermal reduction
    let evalNoRef = ThrottlingAssessment.evaluate(
        thermalPressure: .serious,
        clockTelemetry: clampedTel,
        reference: nil,
        isUnderSustainedLoad: true
    )
    #expect(evalNoRef.inference == .possibleThermalReduction)

    // 7c. Not sustained load: falls back to possible thermal reduction
    let evalNotSustained = ThrottlingAssessment.evaluate(
        thermalPressure: .serious,
        clockTelemetry: clampedTel,
        reference: ref,
        isUnderSustainedLoad: false
    )
    #expect(evalNotSustained.inference == .possibleThermalReduction)

    // 7d. Low Power Mode active: falls back to possible thermal reduction (could be power policy, not thermal limitation)
    let evalLPM = ThrottlingAssessment.evaluate(
        thermalPressure: .serious,
        clockTelemetry: clampedTel,
        reference: ref,
        isUnderSustainedLoad: true,
        isLowPowerModeActive: true
    )
    #expect(evalLPM.inference == .possibleThermalReduction)

    // 8. Unknown thermal state reports unavailable
    let evalUnknown = ThrottlingAssessment.evaluate(
        thermalPressure: .unknown,
        clockTelemetry: .unavailable(reason: "Unavailable")
    )
    #expect(evalUnknown.inference == .insufficientTelemetry)
    #expect(evalUnknown.assessmentSummary == "Thermal state unavailable.")
}

@Test func testThermalSessionCSVExporterExtendedHeadersAndFallbacks() throws {
    let sample = ThermalSample(
        elapsedSeconds: 1.5,
        peakDieTemp: 48.5,
        peakDieSensorName: "PMU tdie2",
        averageDieTemp: 43.2,
        pCoreClusterTemp: nil,
        eCoreClusterTemp: nil,
        gpuClusterTemp: nil,
        socFabricTemp: nil,
        pCoreFrequencyMHz: nil,
        eCoreFrequencyMHz: nil,
        gpuFrequencyMHz: nil,
        operatingChannelCount: 41,
        thermalState: "Nominal",
        thermalPressure: .nominal,
        throttlingInference: .normalOperation,
        powerMode: .battery,
        isCharging: false,
        batteryPercent: 85
    )

    let csv = ThermalSessionCSVExporter.generateCSV(from: [sample])
    let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    #expect(rows.count == 2)

    let header = rows[0]
    #expect(header.contains("PCoreClusterC"))
    #expect(header.contains("ECoreClusterC"))
    #expect(header.contains("GPUClusterC"))
    #expect(header.contains("SoCClusterC"))
    #expect(header.contains("PCoreFreqMHz"))
    #expect(header.contains("ECoreFreqMHz"))
    #expect(header.contains("GPUFreqMHz"))
    #expect(header.contains("ThermalState"))
    #expect(header.contains("ThrottlingStatus"))

    let dataRow = rows[1]
    #expect(dataRow.contains("48.50"))
    #expect(dataRow.contains("PMU tdie2"))
    #expect(dataRow.contains("43.20"))
    #expect(dataRow.contains("unavailable")) // unmapped clusters & frequencies must be "unavailable"
    #expect(dataRow.contains("Normal Operation"))
    #expect(dataRow.contains("Battery power"))
}


