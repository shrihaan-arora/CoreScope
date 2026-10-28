import AppKit
import SwiftUI

@main
struct CoreScopeApp: App {
    @NSApplicationDelegateAdaptor(CoreScopeAppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardModel()

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

    private var initialSectionForLaunch: DashboardSection {
        if CommandLine.arguments.contains("--session") {
            return .thermalSession
        } else if CommandLine.arguments.contains("--sensors") {
            return .sensors
        }
        return .overview
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model, initialSection: initialSectionForLaunch)
                .frame(minWidth: 840, minHeight: 620)
                .onAppear {
                    if CommandLine.arguments.contains("--capture") {
                        captureSelfToScreenshots()
                    }
                }
                .onDisappear {
                    model.session.cancelAndTearDown()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 720)
    }

    private func captureSelfToScreenshots() {
        let isSessionMode = CommandLine.arguments.contains("--session")
        let isSensorsMode = CommandLine.arguments.contains("--sensors")

        if isSessionMode {
            // Start recording session and capture chart after samples arrive
            model.session.startSession(duration: .seconds30)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
                      let view = window.contentView else {
                    exit(1)
                }
                let outDir = "docs/screenshots"
                try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    exit(1)
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(outDir)/thermal_session.png"))
                    print("Self-captured thermal session to \(outDir)/thermal_session.png (\(png.count) bytes)")
                }
                model.session.stopSession()
                exit(0)
            }
            return
        }

        if isSensorsMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
                      let view = window.contentView else {
                    exit(1)
                }
                let outDir = "docs/screenshots"
                try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    exit(1)
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(outDir)/sensor_explorer.png"))
                    print("Self-captured sensor explorer to \(outDir)/sensor_explorer.png (\(png.count) bytes)")
                }
                exit(0)
            }
            return
        }

        // Default: Overview mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
                  let view = window.contentView else {
                print("No visible window found for capture")
                exit(1)
            }
            let outDir = "docs/screenshots"
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                print("Failed to create bitmap rep")
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(outDir)/dashboard.png"))
                print("Self-captured dashboard to \(outDir)/dashboard.png (\(png.count) bytes)")
            }
            exit(0)
        }
    }
}

/// Do not leave a hidden app process running after the last window is closed.
final class CoreScopeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
