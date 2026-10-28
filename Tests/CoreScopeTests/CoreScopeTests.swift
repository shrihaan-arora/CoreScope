import Testing
@testable import CoreScope

@Test func testSensorProbeSnapshot() async throws {
    let probe = SensorProbe()
    let snapshot = probe.read()
    #expect(!snapshot.thermalState.isEmpty)
    #expect(snapshot.powerMode != PowerMode.unknown)
}

@Test func testTemperatureProbeExecution() async throws {
    let result = TemperatureProbe.collectOnce()
    switch result {
    case .readings(let readings):
        #expect(!readings.isEmpty)
        for reading in readings {
            #expect(!reading.sensorName.isEmpty)
            #expect(reading.temperatureC >= 5.0 && reading.temperatureC <= 120.0)
        }
    case .noSensorsFound, .systemClientUnavailable, .noValidReadings:
        // Graceful failure allowed on hardware environments where HID sensors are restricted
        break
    }
}

@Test func testPowerSourceReader() async throws {
    let power = PowerSourceReader.read()
    let isValid = (power.mode == PowerMode.battery || power.mode == PowerMode.external || power.mode == PowerMode.unknown)
    #expect(isValid)
}
