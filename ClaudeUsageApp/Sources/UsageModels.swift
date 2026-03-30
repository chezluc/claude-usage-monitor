import Foundation
import SwiftUI

struct UsageSnapshot: Codable, Equatable {
    let used: Int?
    let total: Int?
    let percent: Int?
    let resetDate: String?
    let lastUpdated: String?
    let plans: [UsagePlan]?

    static let empty = UsageSnapshot(
        used: nil,
        total: nil,
        percent: nil,
        resetDate: nil,
        lastUpdated: nil,
        plans: nil
    )

    var resolvedPlans: [UsagePlan] {
        if let plans, !plans.isEmpty {
            return plans
        }

        guard let used, let total else {
            return []
        }

        return [
            UsagePlan(
                name: "Messages",
                used: used,
                total: total,
                percent: percent ?? Self.percentFor(used: used, total: total),
                resetDate: resetDate
            )
        ]
    }

    var displayPercent: Int? {
        if let percent {
            return percent
        }

        if let firstPlan = resolvedPlans.first {
            return firstPlan.percent
        }

        return nil
    }

    static func percentFor(used: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(used) / Double(total) * 100).rounded())
    }
}

struct UsagePlan: Codable, Equatable, Identifiable {
    let name: String
    let used: Int
    let total: Int
    let percent: Int
    let resetDate: String?
    let resetLabel: String?   // e.g. "Resets in 3 hr 41 min" or "Resets Thu 9:59 AM"
    let section: String?      // e.g. "Plan usage limits" or "Weekly limits"
    let icon: String?         // e.g. "sparkle" for Sonnet

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, used, total, percent, resetDate, resetLabel, section, icon
    }

    init(name: String, used: Int, total: Int, percent: Int, resetDate: String?, resetLabel: String? = nil, section: String? = nil, icon: String? = nil) {
        self.name = name
        self.used = used
        self.total = total
        self.percent = percent
        self.resetDate = resetDate
        self.resetLabel = resetLabel
        self.section = section
        self.icon = icon
    }
}

extension UsageSnapshot {
    /// Groups plans by section name, preserving order
    var planSections: [(title: String, plans: [UsagePlan])] {
        let plans = resolvedPlans
        var sections: [(title: String, plans: [UsagePlan])] = []
        var seen = Set<String>()
        for plan in plans {
            let sec = plan.section ?? "Usage"
            if !seen.contains(sec) {
                seen.insert(sec)
                sections.append((title: sec, plans: plans.filter { ($0.section ?? "Usage") == sec }))
            }
        }
        return sections
    }
}

enum UsageLevel {
    case low
    case medium
    case high

    init(percent: Int) {
        switch percent {
        case ..<70:
            self = .low
        case ..<90:
            self = .medium
        default:
            self = .high
        }
    }

    var color: Color {
        switch self {
        case .low:
            return Color(red: 0.29, green: 0.56, blue: 0.89)  // blue like claude.ai
        case .medium:
            return Color(red: 0.98, green: 0.8, blue: 0.27)
        case .high:
            return Color(red: 0.98, green: 0.38, blue: 0.35)
        }
    }
}

enum UsageFormatters {
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!

    static func parseISODate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: rawValue)
    }

    static func resetDateText(_ rawValue: String?) -> String {
        guard let date = parseISODate(rawValue) else {
            return "Unknown"
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func shortCountdown(_ rawValue: String?) -> String? {
        guard let date = parseISODate(rawValue) else { return nil }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return nil }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    static func resetCountdown(_ rawValue: String?) -> String {
        guard let date = parseISODate(rawValue) else { return "Unknown" }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "Now" }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 { return "in \(hours) hr \(minutes) min" }
        return "in \(minutes) min"
    }

    static func lastUpdatedText(_ rawValue: String?) -> String {
        guard let date = parseISODate(rawValue) else {
            return "Never"
        }

        return date.formatted(date: .omitted, time: .shortened)
    }

    static func relativeUpdatedText(_ rawValue: String?) -> String {
        guard let date = parseISODate(rawValue) else { return "Never" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60)) minutes ago" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
