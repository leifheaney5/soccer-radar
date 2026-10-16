import XCTest
@testable import SoccerScanner

final class FixtureListPresentationTests: XCTestCase {
    private func fixtures(_ json: String) throws -> [Fixture] {
        try JSONDecoder().decode([Fixture].self, from: Data(json.utf8))
    }

    private func match(
        _ id: String,
        status: String,
        competition: String?,
        competitionId: String? = nil
    ) -> String {
        var fields: [String] = []
        if let competitionId { fields.append(#""canonicalId":"\#(competitionId)""#) }
        if let competition { fields.append(#""name":"\#(competition)""#) }
        let competitionJSON = competition == nil && competitionId == nil
            ? "null"
            : "{" + fields.joined(separator: ",") + "}"
        return """
        {"canonicalFixtureId":"\(id)","utcDate":"2026-08-05T19:00:00Z",
         "status":{"code":"\(status)"},"homeTeam":{"name":"Home \(id)"},
         "awayTeam":{"name":"Away \(id)"},"competition":\(competitionJSON),"broadcasts":[]}
        """
    }

    func testSummaryCountsUseTheSameBucketsAsTheStatusFilter() throws {
        let day = try fixtures("""
        [\(match("a", status: "IN_PLAY", competition: "Premier League")),
         \(match("b", status: "HALF_TIME", competition: "Premier League")),
         \(match("c", status: "TIMED", competition: "LaLiga")),
         \(match("d", status: "FINISHED", competition: "LaLiga")),
         \(match("e", status: "POSTPONED", competition: "LaLiga"))]
        """)

        let summary = FixtureDaySummary(fixtures: day)

        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.live, 2)
        XCTAssertEqual(summary.upcoming, 1)
        XCTAssertEqual(summary.finished, 1)
        for filter in FixtureStatusFilter.allCases {
            let expected = day.filter { filter.includes($0.status) }.count
            switch filter {
            case .all: XCTAssertEqual(summary.total, expected)
            case .live: XCTAssertEqual(summary.live, expected)
            case .upcoming: XCTAssertEqual(summary.upcoming, expected)
            case .finished: XCTAssertEqual(summary.finished, expected)
            }
        }
        XCTAssertEqual(summary.matchesLabel, "5 matches")
        XCTAssertEqual(FixtureDaySummary(fixtures: Array(day.prefix(1))).matchesLabel, "1 match")
    }

    func testGroupingKeepsListOrderAndCollectsMissingCompetitions() throws {
        let day = try fixtures("""
        [\(match("a", status: "TIMED", competition: "LaLiga")),
         \(match("b", status: "TIMED", competition: nil)),
         \(match("c", status: "TIMED", competition: "Premier League")),
         \(match("d", status: "TIMED", competition: "LaLiga")),
         \(match("e", status: "TIMED", competition: "  "))]
        """)

        let groups = FixtureGrouping.byCompetition(day)

        XCTAssertEqual(groups.map(\.title), ["LaLiga", "Other fixtures", "Premier League"])
        XCTAssertEqual(groups.map { $0.fixtures.map(\.id) }, [["a", "d"], ["b", "e"], ["c"]])
        XCTAssertEqual(groups.map(\.countLabel), ["2 matches", "2 matches", "1 match"])
        XCTAssertEqual(groups.flatMap(\.fixtures).count, day.count, "grouping must not drop fixtures")
    }

    func testGroupingUsesCanonicalIdentityRatherThanTheProviderLabel() throws {
        let day = try fixtures("""
        [\(match("a", status: "TIMED", competition: "Premier League", competitionId: "eng.1")),
         \(match("b", status: "TIMED", competition: "English Premier League", competitionId: "eng.1")),
         \(match("c", status: "TIMED", competition: "Cup", competitionId: "eng.fa")),
         \(match("d", status: "TIMED", competition: "Cup", competitionId: "esp.copa_del_rey")),
         \(match("e", status: "TIMED", competition: "Cup")),
         \(match("f", status: "TIMED", competition: nil, competitionId: "eng.1"))]
        """)

        let groups = FixtureGrouping.byCompetition(day)

        // One competition under two provider labels shares a section titled
        // by its first label; distinct competitions sharing a label stay apart.
        XCTAssertEqual(groups.map { $0.fixtures.map(\.id) }, [["a", "b", "f"], ["c"], ["d"], ["e"]])
        XCTAssertEqual(groups.map(\.title), ["Premier League", "Cup", "Cup", "Cup"])
        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count, "section identities must be unique")
    }

    func testGroupingAnEmptyDayProducesNoSections() {
        XCTAssertTrue(FixtureGrouping.byCompetition([]).isEmpty)
    }
}
