import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: SensorSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    let session: ThermalSessionModel
    private let probe: SensorProbe

    init(snapshot: SensorSnapshot? = nil, session: ThermalSessionModel? = nil, probe: SensorProbe = SensorProbe()) {
        self.snapshot = snapshot
        self.session = session ?? ThermalSessionModel()
        self.probe = probe
    }

    func refresh() {
        guard !isRefreshing else { return }
        // Prevent collision with any session hardware probe currently in flight
        guard !session.isSamplingInProgress else { return }

        isRefreshing = true
        lastError = nil

        let probe = self.probe
        Task.detached(priority: .userInitiated) {
            let result = probe.read()
            await MainActor.run {
                self.snapshot = result
                self.isRefreshing = false
            }
        }
    }
}
