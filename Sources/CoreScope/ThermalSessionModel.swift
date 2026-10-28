import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ThermalSessionModel: ObservableObject {
    /// Documented sampling interval: 2 seconds between scheduled readings during active sessions.
    static let samplingInterval: TimeInterval = 2.0

    @Published private(set) var state: ThermalSessionState = .idle
    @Published var selectedDuration: ThermalSessionDuration = .seconds30
    @Published private(set) var samples: [ThermalSample] = []
    @Published private(set) var lastSummary: ThermalSessionSummary? = nil
    @Published private(set) var elapsedSeconds: TimeInterval = 0.0
    @Published private(set) var remainingSeconds: TimeInterval? = nil
    @Published private(set) var isSamplingInProgress: Bool = false
    @Published var exportMessage: String? = nil

    /// Lifecycle-managed thermal pressure monitor observing NotificationCenter events.
    let thermalPressureMonitor: ThermalPressureMonitor

    private var sessionStartTime: Date?
    private var sessionTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?

    // Probe provider (defaults to SensorProbe().read for production)
    private let sampleProvider: @Sendable () -> SensorSnapshot

    init(sampleProvider: (@Sendable () -> SensorSnapshot)? = nil, thermalPressureMonitor: ThermalPressureMonitor? = nil) {
        self.thermalPressureMonitor = thermalPressureMonitor ?? ThermalPressureMonitor()
        if let provider = sampleProvider {
            self.sampleProvider = provider
        } else {
            let defaultProbe = SensorProbe()
            self.sampleProvider = { defaultProbe.read() }
        }
    }

    // MARK: - Session Controls

    /// Starts a new thermal recording session.
    func startSession(duration: ThermalSessionDuration? = nil) {
        guard state != .running else { return }

        if let d = duration {
            self.selectedDuration = d
        }

        // 1. Reset previous run in-memory state
        self.samples.removeAll(keepingCapacity: true)
        self.lastSummary = nil
        self.elapsedSeconds = 0.0
        self.remainingSeconds = selectedDuration.seconds
        self.exportMessage = nil

        let startTime = Date()
        self.sessionStartTime = startTime
        self.state = .running

        // 2. Start thermal pressure event tracking
        thermalPressureMonitor.startMonitoring(sessionStartTime: startTime)

        // 3. Start ticker for smooth UI progress
        startTicker(startTime: startTime)

        // 4. Collect sample 0 immediately, then schedule every 2.0 seconds
        let targetDuration = selectedDuration.seconds
        let interval = Self.samplingInterval

        sessionTask = Task { [weak self] in
            // Initial immediate sample
            await self?.collectSingleSample(startTime: startTime)

            while !Task.isCancelled {
                // Sleep for the defined sampling interval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }

                guard let self = self, self.state == .running else { break }

                // Check duration expiration
                let currentElapsed = Date().timeIntervalSince(startTime)
                if let maxDuration = targetDuration, currentElapsed >= maxDuration {
                    self.stopSession()
                    break
                }

                // Collect next sample if not already scanning
                await self.collectSingleSample(startTime: startTime)

                // Check again post-sample
                let postElapsed = Date().timeIntervalSince(startTime)
                if let maxDuration = targetDuration, postElapsed >= maxDuration {
                    self.stopSession()
                    break
                }
            }
        }
    }

    /// Stops the active session, finalizes summary statistics, and returns to completed state.
    func stopSession() {
        guard state == .running else { return }

        // Cancel running loops
        sessionTask?.cancel()
        sessionTask = nil
        tickerTask?.cancel()
        tickerTask = nil

        thermalPressureMonitor.stopMonitoring()

        state = .completed
        isSamplingInProgress = false
        remainingSeconds = 0.0

        // Compute summary statistics from collected samples
        lastSummary = ThermalSessionSummary.compute(from: samples)
    }

    /// Resets all in-memory samples and returns to idle state.
    func clearSession() {
        stopSession()
        samples.removeAll()
        lastSummary = nil
        elapsedSeconds = 0.0
        remainingSeconds = nil
        exportMessage = nil
        thermalPressureMonitor.resetTransitions()
        state = .idle
    }

    /// Clean teardown on window close or application exit.
    func cancelAndTearDown() {
        sessionTask?.cancel()
        sessionTask = nil
        tickerTask?.cancel()
        tickerTask = nil
        thermalPressureMonitor.stopMonitoring()
        thermalPressureMonitor.resetTransitions()
        state = .idle
        samples.removeAll()
        lastSummary = nil
    }

    // MARK: - Private Sampling Engine

    private func collectSingleSample(startTime: Date) async {
        // Enforce non-overlapping scan guarantee
        guard !isSamplingInProgress else { return }
        isSamplingInProgress = true

        let provider = self.sampleProvider
        // Run hardware IOKit read in detached background priority off main thread
        let snapshot = await Task.detached(priority: .userInitiated) {
            provider()
        }.value

        guard state == .running, !Task.isCancelled else {
            isSamplingInProgress = false
            return
        }

        let sample = ThermalSample.create(from: snapshot, startTime: startTime)
        self.samples.append(sample)
        self.isSamplingInProgress = false
    }

    private func startTicker(startTime: Date) {
        tickerTask?.cancel()
        let targetDuration = selectedDuration.seconds

        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 5Hz UI clock update
                if Task.isCancelled { break }
                guard let self = self, self.state == .running else { break }

                let elapsed = Date().timeIntervalSince(startTime)
                self.elapsedSeconds = elapsed

                if let total = targetDuration {
                    self.remainingSeconds = max(0.0, total - elapsed)
                } else {
                    self.remainingSeconds = nil
                }
            }
        }
    }

    // MARK: - Native CSV Export

    /// Prompts user with native NSSavePanel and exports in-memory session samples to RFC 4180 CSV.
    func exportCSV(window: NSWindow? = nil) {
        guard !samples.isEmpty else {
            exportMessage = "No session samples to export."
            return
        }

        let csvContent = ThermalSessionCSVExporter.generateCSV(from: samples)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestampStr = dateFormatter.string(from: sessionStartTime ?? Date())
        let defaultFileName = "CoreScope_ThermalSession_\(timestampStr).csv"

        let panel = NSSavePanel()
        panel.title = "Export Thermal Session CSV"
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.commaSeparatedText]

        let targetWindow = window ?? NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
                self?.exportMessage = "Exported \(self?.samples.count ?? 0) samples to \(url.lastPathComponent)"
            } catch {
                self?.exportMessage = "Failed to export: \(error.localizedDescription)"
            }
        }

        if let targetWindow = targetWindow {
            panel.beginSheetModal(for: targetWindow, completionHandler: handler)
        } else {
            let response = panel.runModal()
            handler(response)
        }
    }
}
