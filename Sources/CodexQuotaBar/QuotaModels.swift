import Foundation

struct RateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }
}

struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    var weekly: RateLimitWindow? {
        window(duration: 10_080) ?? primary ?? secondary
    }

    private func window(duration: Int) -> RateLimitWindow? {
        [primary, secondary]
            .compactMap { $0 }
            .first { $0.windowDurationMins == duration }
    }

    var hasZeroUsageWindow: Bool {
        weekly?.usedPercent == 0
    }

    func hasSuspiciousZeroUsage(comparedTo previous: RateLimitSnapshot?) -> Bool {
        hasSuspiciousZeroUsage(current: weekly, previous: previous?.weekly)
    }

    private func hasSuspiciousZeroUsage(
        current: RateLimitWindow?,
        previous: RateLimitWindow?
    ) -> Bool {
        guard let current,
              current.usedPercent == 0,
              let previous,
              previous.usedPercent > 0 else {
            return false
        }

        return current.resetsAt == previous.resetsAt
    }
}

struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitSnapshot
}

struct QuotaDisplayState: Equatable {
    var weekly: RateLimitWindow?
    var status: String
    var updatedAt: Date?

    static let loading = QuotaDisplayState(
        weekly: nil,
        status: "正在连接本机 Codex…",
        updatedAt: nil
    )

    static func pending(_ status: String) -> QuotaDisplayState {
        QuotaDisplayState(
            weekly: nil,
            status: status,
            updatedAt: nil
        )
    }

    init(snapshot: RateLimitSnapshot, updatedAt: Date = Date()) {
        weekly = snapshot.weekly
        status = "已更新"
        self.updatedAt = updatedAt
    }

    init(weekly: RateLimitWindow?, status: String, updatedAt: Date?) {
        self.weekly = weekly
        self.status = status
        self.updatedAt = updatedAt
    }
}

enum QuotaText {
    static func resetTime(_ timestamp: Int64?, compact: Bool) -> String {
        guard let timestamp else {
            return "重置时间未知"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        if calendar.isDateInToday(date) {
            formatter.dateFormat = compact ? "HH:mm重置" : "今天 HH:mm 重置"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = compact ? "明天HH:mm" : "明天 HH:mm 重置"
        } else {
            formatter.dateFormat = compact ? "M/d HH:mm" : "M月d日 HH:mm 重置"
        }
        return formatter.string(from: date)
    }

    static func updatedTime(_ date: Date?) -> String {
        guard let date else {
            return "尚未更新"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return "更新于 \(formatter.string(from: date))"
    }
}
