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
                .onAppear {
                    if CommandLine.arguments.contains("--capture") {
                        captureSelfToScreenshots()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 940, height: 700)
    }

    private func captureSelfToScreenshots() {
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

            if let scrollView = findScrollView(in: view) {
                let clipView = scrollView.contentView
                clipView.scroll(to: NSPoint(x: 0, y: 340))
                scrollView.reflectScrolledClipView(clipView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard let rep2 = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        exit(0)
                    }
                    view.cacheDisplay(in: view.bounds, to: rep2)
                    if let png2 = rep2.representation(using: .png, properties: [:]) {
                        try? png2.write(to: URL(fileURLWithPath: "\(outDir)/sensor_explorer.png"))
                        print("Self-captured sensor explorer to \(outDir)/sensor_explorer.png (\(png2.count) bytes)")
                    }
                    exit(0)
                }
            } else {
                exit(0)
            }
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }
}

/// Do not leave a hidden app process running after the last window is closed.
final class CoreScopeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
