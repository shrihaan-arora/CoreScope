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
    /// Thermal pressure is Nominal. System operating without thermal constraints.
    case normalOperation = "Normal Operation"
    /// Thermal pressure is Fair (elevated). Scheduler is load-balancing, but no hardware throttling is proven.
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
            return "Normal thermal and power conditions. Processor operating without thermal performance constraints."
        case .thermalPressureElevated:
            return "Thermal pressure is elevated (Fair). The macOS kernel may adjust power targets, but ordinary DVFS scaling must not be confused with hardware throttling."
        case .possibleThermalReduction:
            return "Thermal pressure is high or critical. macOS power pacing is active to protect hardware limits; compute throughput reduction is likely."
        case .confirmedThermalThrottling:
            return "Validated hardware telemetry confirms clock frequency clamped below nominal operating levels under thermal stress."
        case .insufficientTelemetry:
            return "Direct processor clock telemetry is uncalibrated or unavailable in unprivileged user space; throttling cannot be conclusively proven."
        }
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
    /// - Nominal thermal pressure -> Normal Operation
    /// - Fair thermal pressure without frequency proof -> Thermal Pressure Elevated (NOT throttling)
    /// - Serious or Critical thermal pressure -> Possible Thermal Reduction
    /// - Only if verified frequency drops below baseline under high load -> Confirmed Throttling
    /// - Uncalibrated frequency -> Insufficient Telemetry when not Serious/Critical
    static func evaluate(
        thermalPressure: ThermalPressureState,
        clockTelemetry: ClockTelemetryResult,
        isUnderSustainedLoad: Bool = false
    ) -> ThrottlingAssessment {
        let inference: PerformanceReductionInference
        let summary: String

        switch thermalPressure {
        case .nominal:
            inference = .normalOperation
            summary = "Thermal state nominal. All clusters operating within designed thermal envelope."

        case .fair:
            // Crucial rule: Never label "CPU throttling detected" merely because thermal state is Fair
            inference = .thermalPressureElevated
            summary = "Thermal pressure elevated (Fair). macOS scheduler is balancing power. Workload changes or normal DVFS scaling should not be treated as throttling."

        case .serious:
            if case .measured(let tel) = clockTelemetry,
               let pFreq = tel.pCoreFrequencyMHz, pFreq < 1200.0, isUnderSustainedLoad {
                inference = .confirmedThermalThrottling
                summary = "Validated clock frequency clamped to \(Int(pFreq)) MHz under sustained load with Serious thermal pressure."
            } else {
                inference = .possibleThermalReduction
                summary = "Thermal pressure is Serious. The operating system is pacing workload execution to constrain package temperature."
            }

        case .critical:
            if case .measured(let tel) = clockTelemetry,
               let pFreq = tel.pCoreFrequencyMHz, pFreq < 1000.0, isUnderSustainedLoad {
                inference = .confirmedThermalThrottling
                summary = "Validated clock frequency clamped to \(Int(pFreq)) MHz under Critical thermal pressure."
            } else {
                inference = .possibleThermalReduction
                summary = "Thermal pressure is Critical. Immediate thermal mitigation and power clamping engaged by system firmware."
            }

        case .unknown:
            inference = .insufficientTelemetry
            summary = "Thermal state and clock telemetry unavailable from host system."
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
