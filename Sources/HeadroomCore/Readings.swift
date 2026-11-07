import Foundation

public struct QuotaWindow: Decodable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

public struct CreditBalance: Decodable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public var amount: Decimal? {
        guard let balance, !balance.isEmpty,
              balance.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return value
    }

    public var formatted: String? {
        if unlimited { return "∞" }
        guard let amount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .down
        return formatter.string(from: NSDecimalNumber(decimal: amount))
    }
}

public struct QuotaBucket: Decodable {
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let credits: CreditBalance?
}

public struct QuotaResponse: Decodable {
    public let rateLimits: QuotaBucket?
    public let rateLimitsByLimitId: [String: QuotaBucket]?

    private var codexBucket: QuotaBucket? {
        // Never substitute another model's bucket or assume secondary means weekly.
        if let buckets = rateLimitsByLimitId, !buckets.isEmpty { return buckets["codex"] }
        return rateLimits
    }

    public var credits: CreditBalance? { codexBucket?.credits }

    public var weekly: QuotaWindow? {
        [codexBucket?.primary, codexBucket?.secondary].compactMap { $0 }
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
