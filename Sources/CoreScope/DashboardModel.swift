import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: SensorSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    let session: ThermalSessionModel
    private let probe: SensorProbe
    private var cancellables = Set<AnyCancellable>()

    init(snapshot: SensorSnapshot? = nil, session: ThermalSessionModel? = nil, probe: SensorProbe = SensorProbe()) {
        self.snapshot = snapshot
        let s = session ?? ThermalSessionModel()
        self.session = s
        self.probe = probe

        s.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
