import Combine
import Foundation
import SwiftUI

// MARK: - Thermal Pressure State

/// Distinct macOS thermal pressure state derived directly from ProcessInfo.thermalState.
enum ThermalPressureState: String, CaseIterable, Identifiable, Sendable, Comparable {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"
    case unknown = "Unknown"

    var id: String { rawValue }

    init(label: String) {
        switch label.lowercased() {
        case "nominal": self = .nominal
        case "fair": self = .fair
        case "serious": self = .serious
        case "critical": self = .critical
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        case .unknown:  return "Unknown"
        }
    }

    /// Descriptive explanation distinguishing thermal pressure from clock throttling.
    var explanation: String {
        switch self {
        case .nominal:
            return "macOS reports nominal thermal pressure."
        case .fair:
            return "macOS reports elevated thermal pressure."
        case .serious:
            return "macOS reports serious thermal pressure; performance may be affected."
        case .critical:
            return "macOS reports critical thermal pressure; performance may be affected."
        case .unknown:
            return "Thermal state unavailable."
        }
    }

    /// Status badge accent color.
    var badgeColor: Color {
        switch self {
        case .nominal:  return LiquidGlassStyle.emerald
        case .fair:     return LiquidGlassStyle.amber
        case .serious:  return Color(red: 1.0, green: 0.45, blue: 0.15) // Deep Orange
        case .critical: return LiquidGlassStyle.coral
        case .unknown:  return LiquidGlassStyle.textSecondary
        }
    }

    /// System SF Symbol icon.
    var iconName: String {
        switch self {
        case .nominal:  return "checkmark.shield.fill"
        case .fair:     return "thermometer.medium"
        case .serious:  return "exclamationmark.triangle.fill"
        case .critical: return "flame.fill"
        case .unknown:  return "questionmark.circle"
        }
    }

    /// Whether thermal pressure is elevated to Serious or Critical where performance may be affected.
    var isPerformanceLikelyAffected: Bool {
        self == .serious || self == .critical
    }

    /// Whether thermal pressure is elevated beyond nominal (Fair, Serious, or Critical).
    var isWarningActive: Bool {
        self == .fair || self == .serious || self == .critical
    }

    /// Preserved for backwards compatibility with session statistics.
    var isThrottlingLikely: Bool {
        isPerformanceLikelyAffected
    }

    static func < (lhs: ThermalPressureState, rhs: ThermalPressureState) -> Bool {
        let order: [ThermalPressureState] = [.nominal, .fair, .serious, .critical, .unknown]
        let lIdx = order.firstIndex(of: lhs) ?? 99
        let rIdx = order.firstIndex(of: rhs) ?? 99
        return lIdx < rIdx
    }

    /// Converts native ProcessInfo.ThermalState into ThermalPressureState.
    static func from(nativeState: ProcessInfo.ThermalState) -> ThermalPressureState {
        switch nativeState {
        case .nominal:  return .nominal
        case .fair:     return .fair
        case .serious:  return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}

// MARK: - Thermal State Change Event

/// Recorded timestamped transition in thermal pressure state during active monitoring.
struct ThermalStateEvent: Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let elapsedSeconds: TimeInterval
    let previousState: ThermalPressureState
    let newState: ThermalPressureState

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        elapsedSeconds: TimeInterval = 0.0,
        previousState: ThermalPressureState,
        newState: ThermalPressureState
    ) {
        self.id = id
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.previousState = previousState
        self.newState = newState
    }
}

// MARK: - Thermal Pressure Monitor

/// Lifecycle-managed observer for macOS thermal state notifications.
///
/// Uses native NotificationCenter observation without polling loops or timers.
/// Explicitly registers when views/sessions activate, and cancels observation upon dismissal.
@MainActor
final class ThermalPressureMonitor: ObservableObject {
    @Published private(set) var currentState: ThermalPressureState
    @Published private(set) var transitions: [ThermalStateEvent] = []

    private struct TokenHolder: @unchecked Sendable {
        var token: (any NSObjectProtocol)?
    }
    private var tokenHolder = TokenHolder()
    private var sessionStartTime: Date?

    init() {
        self.currentState = ThermalPressureState.from(nativeState: ProcessInfo.processInfo.thermalState)
    }

    /// Starts observing thermal state change notifications.
    func startMonitoring(sessionStartTime: Date? = nil) {
        stopMonitoring()
        self.sessionStartTime = sessionStartTime
        self.currentState = ThermalPressureState.from(nativeState: ProcessInfo.processInfo.thermalState)

        let token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let newState = ThermalPressureState.from(nativeState: ProcessInfo.processInfo.thermalState)
                if newState != self.currentState {
                    let previous = self.currentState
                    self.currentState = newState
                    let elapsed: TimeInterval
                    if let start = self.sessionStartTime {
                        elapsed = max(0.0, Date().timeIntervalSince(start))
                    } else {
                        elapsed = 0.0
                    }
                    let event = ThermalStateEvent(
                        timestamp: Date(),
                        elapsedSeconds: elapsed,
                        previousState: previous,
                        newState: newState
                    )
                    self.transitions.append(event)
                }
            }
        }
        tokenHolder.token = token
    }

    /// Cleanly unregisters the NotificationCenter observer.
    func stopMonitoring() {
        if let token = tokenHolder.token {
            NotificationCenter.default.removeObserver(token)
            tokenHolder.token = nil
        }
    }

    /// Clears recorded state transitions.
    func resetTransitions() {
        transitions.removeAll()
    }

    deinit {
        if let token = tokenHolder.token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
