import AppKit
import Combine
import HeadroomCore

@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var disk: DiskReading?
    @Published private(set) var weekly: QuotaWindow?
    @Published private(set) var diskError: String?
    @Published private(set) var quotaError: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var refreshing = false
    @Published var floating = false
    @Published var showNumbers = UserDefaults.standard.object(forKey: "showNumbers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showNumbers, forKey: "showNumbers") }
    }
    let client = CodexClient()
    private var timer: Timer?
    private var lastAttempt = Date.distantPast
    private var retryInterval: TimeInterval = 60
    private var sleeping = false

    var stale: Bool { quotaError != nil || (updatedAt.map { Date().timeIntervalSince($0) > 180 } ?? false) }

    func start() {
        client.onUpdate = { [weak self] weekly in self?.accept(weekly) }
        sampleDisk()
        refreshQuota()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.sleeping else { return }
                self.sampleDisk()
                if Date().timeIntervalSince(self.lastAttempt) >= self.retryInterval { self.refreshQuota() }
            }
        }
        timer?.tolerance = 5
    }

    func opened() {
        sampleDisk()
        if Date().timeIntervalSince(lastAttempt) >= 30 { refreshQuota() }
    }

    func refresh() {
        sampleDisk()
        // A manual refresh remains bounded even when a user clicks repeatedly.
        if Date().timeIntervalSince(lastAttempt) >= 5 { refreshQuota() }
    }

    private func sampleDisk() {
        do { disk = try DiskReading.read(); diskError = nil }
        catch { diskError = error.localizedDescription }
    }

    private func accept(_ weekly: QuotaWindow) {
        self.weekly = weekly
        quotaError = nil
        updatedAt = Date()
        retryInterval = 60
    }

    private func refreshQuota() {
        guard !refreshing, !sleeping else { return }
        refreshing = true
        lastAttempt = Date()
        Task {
            defer { refreshing = false }
            do {
                let weekly = try await client.readWeekly()
                if !sleeping { accept(weekly) }
            } catch {
                if !sleeping {
                    quotaError = error.localizedDescription
                    retryInterval = min(300, retryInterval * 2)
                }
            }
        }
    }

    func sleep() { sleeping = true; client.stop() }
    func wake() { sleeping = false; sampleDisk(); refreshQuota() }
    func stop() { timer?.invalidate(); timer = nil; client.stop() }
}
