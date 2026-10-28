import Foundation

// MARK: - Clock Telemetry Measurement Result

/// Outcome of attempting to read hardware clock frequencies or residency counters.
enum ClockTelemetryResult: Sendable, Equatable {
    /// Validated frequency telemetry was successfully collected.
    case measured(ClockTelemetry)
    /// Direct frequency telemetry is unavailable from unprivileged user space.
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .measured = self { return true }
        return false
    }

    var telemetry: ClockTelemetry? {
        if case .measured(let t) = self { return t }
        return nil
    }

    var reason: String {
        switch self {
        case .measured:
            return "Calibrated telemetry available"
        case .unavailable(let msg):
            return msg
        }
    }
}

/// Validated frequency and residency measurements.
struct ClockTelemetry: Sendable, Equatable {
    /// P-core cluster average clock frequency in MHz, or nil if uncalibrated.
    let pCoreFrequencyMHz: Double?
    /// E-core cluster average clock frequency in MHz, or nil if uncalibrated.
    let eCoreFrequencyMHz: Double?
    /// GPU clock frequency in MHz, or nil if uncalibrated.
    let gpuFrequencyMHz: Double?
    /// Percentage of time spent in active (non-idle) states (0–100%).
    let pCoreActiveResidencyPercent: Double?
    let eCoreActiveResidencyPercent: Double?
    /// Timestamp of the observation.
    let sampledAt: Date

    init(
        pCoreFrequencyMHz: Double? = nil,
        eCoreFrequencyMHz: Double? = nil,
        gpuFrequencyMHz: Double? = nil,
        pCoreActiveResidencyPercent: Double? = nil,
        eCoreActiveResidencyPercent: Double? = nil,
        sampledAt: Date = Date()
    ) {
        self.pCoreFrequencyMHz = pCoreFrequencyMHz
        self.eCoreFrequencyMHz = eCoreFrequencyMHz
        self.gpuFrequencyMHz = gpuFrequencyMHz
        self.pCoreActiveResidencyPercent = pCoreActiveResidencyPercent
        self.eCoreActiveResidencyPercent = eCoreActiveResidencyPercent
        self.sampledAt = sampledAt
    }
}

// MARK: - Inferred Performance Reduction State

/// Cautious, rule-based inference separating thermal pressure from confirmed throttling.
enum PerformanceReductionInference: String, CaseIterable, Identifiable, Sendable {
    /// Thermal pressure is Nominal ("macOS reports nominal thermal pressure.").
    case normalOperation = "Normal Operation"
    /// Thermal pressure is Fair ("macOS reports elevated thermal pressure."). Scheduler is load-balancing, but no hardware throttling is proven.
    case thermalPressureElevated = "Thermal Pressure Elevated"
    /// Thermal pressure is Serious/Critical. Thermal pacing or power limits likely active.
    case possibleThermalReduction = "Possible Thermal Reduction"
    /// Validated clock reduction confirmed under sustained load while in elevated thermal state.
    case confirmedThermalThrottling = "Confirmed Thermal Throttling"
    /// Telemetry is insufficient to confirm or refute clock frequency reduction.
    case insufficientTelemetry = "Insufficient Telemetry"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .normalOperation:
            return "macOS reports nominal thermal pressure."
        case .thermalPressureElevated:
            return "macOS reports elevated thermal pressure."
        case .possibleThermalReduction:
            return "macOS reports serious or critical thermal pressure; performance may be affected."
        case .confirmedThermalThrottling:
            return "Validated telemetry confirms clock frequency reduction relative to a verified baseline under sustained load and elevated thermal pressure."
        case .insufficientTelemetry:
            return "Thermal state unavailable or clock telemetry uncalibrated."
        }
    }
}

// MARK: - Hardware Clock Reference

/// Defensible hardware reference parameters for evaluating whether an observed frequency reduction
/// constitutes confirmed thermal throttling rather than normal DVFS, Low Power Mode, or idle states.
struct HardwareClockReference: Sendable, Equatable {
    /// Nominal maximum active frequency for the target cluster (MHz) under full sustained workload.
    let nominalActiveFrequencyMHz: Double
    /// Threshold ratio below nominal active frequency (e.g. 0.65 = 35% reduction) required to indicate thermal limitation.
    let throttlingRatioThreshold: Double

    init(nominalActiveFrequencyMHz: Double, throttlingRatioThreshold: Double = 0.65) {
        self.nominalActiveFrequencyMHz = nominalActiveFrequencyMHz
        self.throttlingRatioThreshold = throttlingRatioThreshold
    }
}

// MARK: - Throttling Assessment

/// Complete thermal status assessment clearly separating the three core concepts:
/// 1. Thermal Pressure (macOS kernel thermal state)
/// 2. Measured Clock Telemetry (from IOReport, when available)
/// 3. Inferred Performance Reduction (rule-based assessment)
struct ThrottlingAssessment: Sendable, Equatable {
    let thermalPressure: ThermalPressureState
    let clockTelemetry: ClockTelemetryResult
    let inference: PerformanceReductionInference
    let assessmentSummary: String

    init(
        thermalPressure: ThermalPressureState,
        clockTelemetry: ClockTelemetryResult,
        inference: PerformanceReductionInference,
        assessmentSummary: String
    ) {
        self.thermalPressure = thermalPressure
        self.clockTelemetry = clockTelemetry
        self.inference = inference
        self.assessmentSummary = assessmentSummary
    }

    /// Evaluates current hardware telemetry and applies conservative inference rules.
    ///
    /// Rules:
    /// - Nominal thermal pressure -> Normal Operation ("macOS reports nominal thermal pressure.")
    /// - Fair thermal pressure alone -> Thermal Pressure Elevated ("macOS reports elevated thermal pressure.")
    /// - Serious or Critical thermal pressure -> Possible Thermal Reduction ("macOS reports serious/critical thermal pressure; performance may be affected.")
    /// - Confirmed Throttling ONLY when validated telemetry confirms frequency reduction relative to a defensible hardware baseline under sustained load while not in Low Power Mode.
    /// - Unknown thermal pressure -> Insufficient Telemetry ("Thermal state unavailable.")
    static func evaluate(
        thermalPressure: ThermalPressureState,
        clockTelemetry: ClockTelemetryResult,
        reference: HardwareClockReference? = nil,
        isUnderSustainedLoad: Bool = false,
        powerMode: PowerMode = .unknown,
        isLowPowerModeActive: Bool = false
    ) -> ThrottlingAssessment {
        let inference: PerformanceReductionInference
        let summary: String

        switch thermalPressure {
        case .nominal:
            inference = .normalOperation
            summary = "macOS reports nominal thermal pressure."

        case .fair:
            // Fair thermal pressure alone does not establish confirmed throttling
            inference = .thermalPressureElevated
            summary = "macOS reports elevated thermal pressure."

        case .serious:
            if let ref = reference,
               isUnderSustainedLoad,
               !isLowPowerModeActive,
               case .measured(let tel) = clockTelemetry,
               let pFreq = tel.pCoreFrequencyMHz,
               pFreq < (ref.nominalActiveFrequencyMHz * ref.throttlingRatioThreshold) {
                inference = .confirmedThermalThrottling
                summary = "Validated telemetry confirms clock frequency reduced to \(Int(pFreq)) MHz from \(Int(ref.nominalActiveFrequencyMHz)) MHz baseline under sustained load."
            } else {
                inference = .possibleThermalReduction
                summary = "macOS reports serious thermal pressure; performance may be affected."
            }

        case .critical:
            if let ref = reference,
               isUnderSustainedLoad,
               !isLowPowerModeActive,
               case .measured(let tel) = clockTelemetry,
               let pFreq = tel.pCoreFrequencyMHz,
               pFreq < (ref.nominalActiveFrequencyMHz * ref.throttlingRatioThreshold) {
                inference = .confirmedThermalThrottling
                summary = "Validated telemetry confirms clock frequency reduced to \(Int(pFreq)) MHz from \(Int(ref.nominalActiveFrequencyMHz)) MHz baseline under sustained load."
            } else {
                inference = .possibleThermalReduction
                summary = "macOS reports critical thermal pressure; performance may be affected."
            }

        case .unknown:
            inference = .insufficientTelemetry
            summary = "Thermal state unavailable."
        }

        return ThrottlingAssessment(
            thermalPressure: thermalPressure,
            clockTelemetry: clockTelemetry,
            inference: inference,
            assessmentSummary: summary
        )
    }
}

// MARK: - Safe IOReport Dynamic Probe

/// Safely probes native IOReport interfaces via dlopen/dlsym with zero external dependencies,
/// zero shell execution, and zero root helper requirements.
enum ClockTelemetryProbe {

    /// Probes unprivileged clock and residency telemetry.
    ///
    /// If symbols are absent, frameworks missing, or the kernel driver reports
    /// "no legend" for clock tables, this function safely returns .unavailable without crashing.
    static func probe() -> ClockTelemetryResult {
        // 1. Safely resolve libIOReport.dylib
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else {
            return .unavailable(reason: "libIOReport.dylib unavailable on this macOS environment")
        }
        defer { dlclose(handle) }

        // 2. Resolve required C function symbols
        typealias CopyChannelsFunc = @convention(c) (CFString?, CFString?) -> Unmanaged<CFDictionary>?
        guard let symCopy = dlsym(handle, "IOReportCopyChannelsInGroup") else {
            return .unavailable(reason: "IOReportCopyChannelsInGroup symbol unresolved")
        }
        let copyChannels = unsafeBitCast(symCopy, to: CopyChannelsFunc.self)

        // 3. Query CPU Stats channels
        guard let channelsUnmanaged = copyChannels("CPU Stats" as CFString, "CPU Complex Performance States" as CFString) else {
            return .unavailable(reason: "CPU Complex Performance States channel group inaccessible")
        }
        let channels = channelsUnmanaged.takeRetainedValue() as NSDictionary

        guard let channelList = channels["IOReportChannels"] as? [NSDictionary], !channelList.isEmpty else {
            return .unavailable(reason: "No CPU performance state channels returned by driver")
        }

        // 4. Inspect channel configuration
        // On Apple Silicon without root/powermetrics privileges, CLPC driver does not export
        // calibrated frequency legend tables (e.g. "AppleCLPC: no legend").
        // We strictly refuse to invent MHz values when units or semantics are uncalibrated.
        return .unavailable(reason: "CLPC driver legend table not accessible to unprivileged processes on Apple Silicon; direct MHz uncalibrated without powermetrics")
    }
}
