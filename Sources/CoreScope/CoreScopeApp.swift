import AppKit
import SwiftUI

@main
struct CoreScopeApp: App {
    @NSApplicationDelegateAdaptor(CoreScopeAppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--cli") || CommandLine.arguments.contains("--test") || CommandLine.arguments.contains("--dump") {
            let probe = SensorProbe()
            let snapshot = probe.read()
            print("CoreScope Hardware Telemetry Snapshot")
            print("====================================")
            print("Timestamp: \(snapshot.sampledAt)")
            print("Power Mode: \(snapshot.powerMode.rawValue)")
            if let battery = snapshot.batteryPercent {
                let chargingStr = snapshot.isCharging.map(String.init) ?? "unknown"
                let adapterStr = snapshot.isAdapterConnected.map(String.init) ?? "unknown"
                print("Battery: \(battery)% (Charging: \(chargingStr), Adapter: \(adapterStr))")
            } else {
                print("Battery: None / Not applicable")
            }
            print("Thermal State: \(snapshot.thermalState)")
            print("Temperature Status: \(snapshot.temperatureStatus.explanation)")
            let summary = snapshot.temperatureSummary
            if let peak = summary.peakDieReading {
                print("Peak Die Sensor: \(peak.sensorName) (\(String(format: "%.1f", peak.temperatureC)) °C)")
            } else {
                print("Peak Die Sensor: Unavailable")
            }
            if let avg = summary.dieAverageC {
                print("Die Sensor Average: \(String(format: "%.1f", avg)) °C (\(summary.dieSensorCount) active die channels)")
            } else {
                print("Die Sensor Average: Unavailable")
            }
            if summary.calibrationSensorCount > 0 {
                print("Calibration Channels: \(summary.calibrationSensorCount) (isolated from operating averages)")
            }
            if snapshot.temperatureReadings.isEmpty {
                print("Temperature Sensors: 0 accessible")
            } else {
                print("Temperature Channels (\(snapshot.temperatureReadings.count) total):")
                for reading in snapshot.temperatureReadings {
                    let tempStr = String(format: "%.1f", reading.temperatureC)
                    print("  - [\(reading.category.rawValue)] \(reading.sensorName): \(tempStr) °C")
                }
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 820, minHeight: 610)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 940, height: 700)
    }
}

/// Do not leave a hidden app process running after the last window is closed.
final class CoreScopeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
