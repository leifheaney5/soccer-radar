import Foundation

public extension FixtureStatusFilter {
    /// Single definition of each status bucket, shared by the list filter and
    /// the day summary so the two can never disagree.
    func includes(_ status: MatchStatus) -> Bool {
        switch self {
        case .all: return true
        case .live: return status.isActive
        case .upcoming:
            return !status.isActive && !status.isTerminal
                && [.scheduled, .delayed, .unknown].contains(status)
        case .finished: return status == .finished
        }
    }
}

/// Day-level counts shown above the fixture list, matching the web dashboard's
/// summary line. Counts describe the whole loaded day, not the active filter.
public struct FixtureDaySummary: Equatable, Sendable {
    public let total: Int
    public let live: Int
    public let upcoming: Int
    public let finished: Int

    public init(fixtures: [Fixture]) {
        total = fixtures.count
        live = fixtures.filter { FixtureStatusFilter.live.includes($0.status) }.count
        upcoming = fixtures.filter { FixtureStatusFilter.upcoming.includes($0.status) }.count
        finished = fixtures.filter { FixtureStatusFilter.finished.includes($0.status) }.count
    }

    public var matchesLabel: String {
        total == 1 ? String(localized: "1 match") : String(localized: "\(total) matches")
    }

    public var accessibilityLabel: String {
        String(localized: "\(matchesLabel), \(live) live, \(upcoming) upcoming, \(finished) finished")
    }
}

/// Fixtures sharing a competition, in the order the list already presents them.
public struct FixtureCompetitionGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let fixtures: [Fixture]

    public var countLabel: String {
        fixtures.count == 1
            ? String(localized: "1 match")
            : String(localized: "\(fixtures.count) matches")
    }
}

public enum FixtureGrouping {
    /// Groups by competition in first-appearance order, so the chosen sort
    /// still decides both group order and order within each group.
    public static func byCompetition(_ fixtures: [Fixture]) -> [FixtureCompetitionGroup] {
        let otherKey = "\u{0}other"
        var order: [String] = []
        var buckets: [String: [Fixture]] = [:]
        for fixture in fixtures {
            let key = fixture.competition?.displayName ?? otherKey
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(fixture)
        }
        return order.map { key in
            FixtureCompetitionGroup(
                id: key,
                title: key == otherKey ? String(localized: "Other fixtures") : key,
                fixtures: buckets[key] ?? []
            )
        }
    }
}
