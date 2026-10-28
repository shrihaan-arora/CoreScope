import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: SensorSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let probe = SensorProbe()

    init(snapshot: SensorSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func refresh() {
        guard !isRefreshing else { return }
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
