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
            print("Thermal Pressure: \(snapshot.thermalPressure.title) (\(snapshot.thermalPressure.explanation))")
            print("Throttling Assessment: \(snapshot.throttlingAssessment.inference.rawValue)")
            print("  - Summary: \(snapshot.throttlingAssessment.assessmentSummary)")
            print("Clock Frequency Telemetry: \(snapshot.clockTelemetry.reason)")
            if case .measured(let tel) = snapshot.clockTelemetry {
                if let p = tel.pCoreFrequencyMHz { print("  - P-Core Frequency: \(Int(p)) MHz") }
                if let e = tel.eCoreFrequencyMHz { print("  - E-Core Frequency: \(Int(e)) MHz") }
            }
            print("Cluster Domain Registry: \(snapshot.sensorRegistry.hasVerifiedClusterMappings ? "Verified Mappings" : "Generic PMU Descriptors (M4)")")
            print("  - Unmapped Die Channels: \(snapshot.sensorRegistry.unmappedCount)")
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
        if CommandLine.arguments.contains("--session") || CommandLine.arguments.contains("--session-idle") || CommandLine.arguments.contains("--session-completed") || CommandLine.arguments.contains("--session-run-30s") {
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
                    if CommandLine.arguments.contains("--capture") || CommandLine.arguments.contains("--session-run-30s") {
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

    @MainActor
    private func captureSelfToScreenshots() {
        if CommandLine.arguments.contains("--session-run-30s") {
            print("==> Starting 30-second live Thermal Session on physical M4 hardware...")
            model.session.startSession(duration: .seconds30)

            Task { @MainActor in
                var lastReportedCount = 0
                while self.model.session.state == .running && self.model.session.elapsedSeconds < 31.0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let samples = self.model.session.samples
                    if samples.count > lastReportedCount {
                        for i in lastReportedCount..<samples.count {
                            let s = samples[i]
                            let peakStr = s.peakDieTemp.map { String(format: "%.1f°C", $0) } ?? "n/a"
                            let avgStr = s.averageDieTemp.map { String(format: "%.1f°C", $0) } ?? "n/a"
                            let freqStr = s.pCoreFrequencyMHz.map { "\(Int($0)) MHz" } ?? "unavailable"
                            print(String(format: "  Sample #%2d [+%4.1fs]: Peak=%@ (%@), Avg=%@, Channels=%d, Pressure=%@, P-Freq=%@, Battery=%d%%",
                                         i + 1, s.elapsedSeconds, peakStr, s.peakDieSensorName ?? "n/a", avgStr, s.operatingChannelCount, s.thermalPressure.title, freqStr, s.batteryPercent ?? 0))
                        }
                        lastReportedCount = samples.count
                    }
                }

                if self.model.session.state == .running {
                    self.model.session.stopSession()
                }

                print("\n==> Thermal Session successfully completed!")
                if let summary = self.model.session.lastSummary {
                    let peakStr = summary.peakObservedTemp.map { String(format: "%.1f °C", $0) } ?? "n/a"
                    let peakSensor = summary.peakObservedSensor ?? "n/a"
                    let avgStr = summary.averageObservedTemp.map { String(format: "%.1f °C", $0) } ?? "n/a"
                    let minStr = summary.minObservedTemp.map { String(format: "%.1f °C", $0) } ?? "n/a"
                    let initStr = summary.initialTemp.map { String(format: "%.1f °C", $0) } ?? "n/a"
                    let finalStr = summary.finalTemp.map { String(format: "%.1f °C", $0) } ?? "n/a"
                    let netChange: String
                    if let initT = summary.initialTemp, let finT = summary.finalTemp {
                        let diff = finT - initT
                        netChange = String(format: "%+.1f °C", diff)
                    } else {
                        netChange = "n/a"
                    }

                    print("Session Summary:")
                    print("  - Samples Collected: \(summary.sampleCount)")
                    print("  - Total Duration: \(String(format: "%.1f", summary.totalDuration)) seconds")
                    print("  - Peak Observed: \(peakStr) (\(peakSensor))")
                    print("  - Average Observed: \(avgStr)")
                    print("  - Minimum Observed: \(minStr)")
                    print("  - Initial -> Final Temp: \(initStr) -> \(finalStr) (\(netChange))")
                    print("  - Thermal State Transitions: \(summary.thermalStateTransitions)")
                } else {
                    print("ERROR: Summary was nil upon completion!")
                    exit(1)
                }

                // Check that sampling has stopped (verify sample count does not increase)
                let finalSampleCount = self.model.session.samples.count
                print("\n==> Verifying sampling stops after session completion...")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let postCount = self.model.session.samples.count
                if postCount == finalSampleCount {
                    print("==> Confirmed: zero additional samples collected after stop (\(postCount) == \(finalSampleCount)).")
                } else {
                    print("ERROR: Samples continued to be collected after session stopped! (\(postCount) > \(finalSampleCount))")
                    exit(1)
                }

                // Close window to verify applicationShouldTerminateAfterLastWindowClosed
                print("==> Closing final window to verify CoreScope termination...")
                guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                    print("No visible window found")
                    exit(1)
                }
                window.performClose(nil)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                print("==> Window closed successfully. Terminating process.")
                exit(0)
            }
            return
        }

        let isSessionIdleMode = CommandLine.arguments.contains("--session-idle")
        let isSessionCompletedMode = CommandLine.arguments.contains("--session-completed")
        let isSessionMode = CommandLine.arguments.contains("--session")
        let isSensorsMode = CommandLine.arguments.contains("--sensors")

        if isSessionIdleMode {
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
                    try? png.write(to: URL(fileURLWithPath: "\(outDir)/thermal_session_idle.png"))
                    print("Self-captured thermal session idle to \(outDir)/thermal_session_idle.png (\(png.count) bytes)")
                }
                exit(0)
            }
            return
        }

        if isSessionCompletedMode {
            model.session.startSession(duration: .seconds30)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                model.session.stopSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
                        try? png.write(to: URL(fileURLWithPath: "\(outDir)/thermal_session_completed.png"))
                        print("Self-captured thermal session completed to \(outDir)/thermal_session_completed.png (\(png.count) bytes)")
                    }
                    exit(0)
                }
            }
            return
        }

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
