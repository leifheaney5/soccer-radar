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
    ///
    /// Identity follows the web's `groupMatches`: the canonical ID when the
    /// provider supplied one, otherwise the display name. The section title is
    /// kept separate from that key, so provider label variants of one
    /// competition share a section and distinct competitions never merge.
    public static func byCompetition(_ fixtures: [Fixture]) -> [FixtureCompetitionGroup] {
        var order: [String] = []
        var buckets: [String: [Fixture]] = [:]
        for fixture in fixtures {
            let key = groupKey(fixture.competition)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(fixture)
        }
        return order.map { key in
            let members = buckets[key] ?? []
            return FixtureCompetitionGroup(
                id: key,
                title: members.lazy.compactMap { $0.competition?.displayName }.first
                    ?? String(localized: "Other fixtures"),
                fixtures: members
            )
        }
    }

    private static func groupKey(_ competition: Competition?) -> String {
        if let canonicalId = competition?.canonicalId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !canonicalId.isEmpty {
            return "id:\(canonicalId)"
        }
        if let name = competition?.displayName {
            return "name:\(name)"
        }
        return "other"
    }
}
