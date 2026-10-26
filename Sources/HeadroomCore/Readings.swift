import Foundation

public struct QuotaWindow: Decodable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

public struct QuotaBucket: Decodable {
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
}

public struct QuotaResponse: Decodable {
    public let rateLimits: QuotaBucket?
    public let rateLimitsByLimitId: [String: QuotaBucket]?

    public var weekly: QuotaWindow? {
        // Never substitute another model's bucket or assume secondary means weekly.
        let bucket: QuotaBucket?
        if let buckets = rateLimitsByLimitId, !buckets.isEmpty {
            bucket = buckets["codex"]
        } else {
            bucket = rateLimits
        }
        return [bucket?.primary, bucket?.secondary].compactMap { $0 }
            .first { $0.windowDurationMins == 7 * 24 * 60 }
    }
}

public struct DiskReading {
    public let available: Int64
    public let total: Int64
    public var fraction: Double { min(1, max(0, Double(available) / Double(max(1, total)))) }
    public var formatted: String {
        ByteCountFormatter.string(fromByteCount: available, countStyle: .decimal)
    }

    public static func read() throws -> DiskReading {
        // Home is on the writable Data volume on modern macOS. No directory scan.
        let values = try FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        guard let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0 else {
            throw ReadingError.diskUnavailable
        }
        return DiskReading(available: available, total: Int64(total))
    }
}

public enum ReadingError: LocalizedError {
    case diskUnavailable, codexMissing, disconnected, timedOut, unavailable, noWeeklyWindow
    public var errorDescription: String? {
        switch self {
        case .diskUnavailable: return "Disk reading unavailable"
        case .codexMissing: return "Install Codex CLI to connect"
        case .disconnected: return "Codex connection interrupted"
        case .timedOut: return "Codex did not respond"
        case .unavailable: return "Codex unavailable. Check your Codex sign-in."
        case .noWeeklyWindow: return "No weekly Codex allowance reported"
        }
    }
}
