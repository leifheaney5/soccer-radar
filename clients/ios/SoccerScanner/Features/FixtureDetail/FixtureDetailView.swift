import SwiftUI

public struct FixtureDetailView: View {
    @AppStorage("soccer-radar:broadcast-region") private var broadcastRegion = "all"
    let fixture: Fixture
    let timeZone: TimeZone
    @Binding private var scoresRevealed: Bool
    let providers: [ProviderReport]
    let freshness: Freshness?
    let client: FixtureFetching

    public init(
        fixture: Fixture,
        timeZone: TimeZone,
        scoresRevealed: Binding<Bool>,
        providers: [ProviderReport] = [],
        freshness: Freshness? = nil,
        client: FixtureFetching
    ) {
        self.fixture = fixture
        self.timeZone = timeZone
        self._scoresRevealed = scoresRevealed
        self.providers = providers
        self.freshness = freshness
        self.client = client
    }

    public var body: some View {
        List {
            Section {
                matchHero
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: Theme.Spacing.sm, leading: Theme.Spacing.lg,
                bottom: Theme.Spacing.sm, trailing: Theme.Spacing.lg
            ))

            if fixture.status.scoreAvailable {
                Section {
                    Button {
                        scoresRevealed.toggle()
                    } label: {
                        Label(
                            scoresRevealed
                                ? String(localized: "Hide score")
                                : String(localized: "Reveal score"),
                            systemImage: scoresRevealed ? "eye.slash" : "eye"
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accentPrimary)
                    }
                    .accessibilityIdentifier("detail-score-toggle")
                } header: {
                    sectionHeader(String(localized: "Spoiler control"))
                }
                .detailCardRows()
            }

            Section {
                LabeledContent(String(localized: "Kick-off"),
                               value: FixtureTime.kickoff(fixture.utcDate, in: timeZone))
                LabeledContent(String(localized: "Timezone"), value: timeZone.identifier)
                LabeledContent(
                    String(localized: "Competition"),
                    value: fixture.competition?.displayName ?? String(localized: "Unavailable")
                )
                .accessibilityIdentifier("detail-competition")
                LabeledContent(
                    String(localized: "Country"),
                    value: fixture.competition?.countryName ?? String(localized: "Unavailable")
                )
                LabeledContent(
                    String(localized: "Venue"),
                    value: fixture.venue ?? String(localized: "Unavailable")
                )
            } header: {
                sectionHeader(String(localized: "Match"))
            }
            .detailCardRows()

            Section {
                Picker(String(localized: "Broadcast region"), selection: $broadcastRegion) {
                    Text(String(localized: "All regions")).tag("all")
                    ForEach(broadcastRegions, id: \.self) { region in
                        Text(region).tag(region)
                    }
                }
                .tint(Theme.Palette.accentPrimary)
                .accessibilityIdentifier("broadcast-region")
                .accessibilityValue(
                    broadcastRegion == "all"
                        ? String(localized: "All regions")
                        : broadcastRegion
                )
                if visibleWatchOptions.contains(where: { $0.status == "stale" }) {
                    Text(String(localized: "Broadcast listings may be out of date."))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.warning)
                }
                if visibleWatchOptions.isEmpty {
                    Text(emptyBroadcastMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    ForEach(Array(visibleWatchOptions.enumerated()), id: \.offset) { index, option in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            if let url = option.officialLinkURL {
                                Link(option.displayName, destination: url)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.accentPrimary)
                            } else {
                                Text(option.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                            }
                            HStack {
                                Text(option.categoryLabel)
                                Spacer()
                                // Region is always shown, and labelled honestly when
                                // the provider did not supply one.
                                Text(option.regionLabel)
                            }
                            .font(Theme.Typography.data(.caption))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .accessibilityIdentifier("detail-broadcast-\(fixture.id)-\(index)")
                    }
                }
                Text(String(localized: "Availability varies by region and subscription. Listings may be incomplete or out of date."))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textMuted)
            } header: {
                sectionHeader(String(localized: "Where to watch"))
            }
            .detailCardRows()

            if !providers.isEmpty || freshness != nil {
                Section {
                    ForEach(providers, id: \.name) { provider in
                        LabeledContent(
                            provider.name ?? String(localized: "Provider unavailable"),
                            value: providerStatusLabel(provider.status)
                        )
                    }
                    if let ageSeconds = freshness?.ageSeconds, ageSeconds >= 0 {
                        LabeledContent(
                            String(localized: "Last updated"),
                            value: freshnessLabel(ageSeconds)
                        )
                    }
                    Text(String(localized: "Provider coverage and update age describe this response, not a guarantee that every fixture is complete."))
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.textMuted)
                } header: {
                    sectionHeader(String(localized: "Source and freshness"))
                }
                .detailCardRows()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bgPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Match details"))
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
        .accessibilityIdentifier("fixture-detail")
    }

    /// The web "Match context" panel: competition, fixture title, status, and
    /// crested team panels around the kickoff time (or the revealed score).
    private var matchHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let competition = fixture.competition?.displayName {
                Text(competition)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("\(fixture.homeTeam.name) v \(fixture.awayTeam.name)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            StatusBadge(status: fixture.status)

            teamPanel(fixture.homeTeam)
            centreLine
            teamPanel(fixture.awayTeam)

            if revealedScoreText == nil {
                if fixture.status.scoreAvailable && fixture.hasFullTimeScore {
                    Label(String(localized: "Score hidden"), systemImage: "eye.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .accessibilityIdentifier("detail-score-hidden")
                } else if fixture.status.scoreAvailable {
                    Label(String(localized: "Score unavailable"), systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .accessibilityIdentifier("detail-score-unavailable")
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(
            border: fixture.status.isActive
                ? Theme.Palette.accentPrimary.opacity(0.55)
                : Theme.Palette.borderColor
        )
    }

    /// The revealed score when the viewer opted in; otherwise the kickoff time.
    @ViewBuilder
    private var centreLine: some View {
        if let scoreText = revealedScoreText {
            Text(scoreText)
                .font(Theme.Typography.data(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("detail-score")
        } else {
            Text(FixtureTime.kickoff(fixture.utcDate, in: timeZone))
                .font(Theme.Typography.data(.title2, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
        }
    }

    private func teamPanel(_ team: Team) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            TeamCrest(url: team.crest, size: 32)
            Text(team.name)
                .font(.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .cardSurface(fill: Theme.Palette.bgSecondary, radius: Theme.Radius.control)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).sectionLabelStyle()
    }

    private var broadcastRegions: [String] {
        let reported = fixture.broadcastCoverage?.regions.map(\.region) ?? []
        let listed = fixture.whereToWatch.compactMap(\.region)
        var regions = Set((reported + listed).filter {
            !$0.isEmpty && $0 != "Region unknown"
        })
        if broadcastRegion != "all" { regions.insert(broadcastRegion) }
        return regions.sorted()
    }

    private var visibleWatchOptions: [WatchOption] {
        guard broadcastRegion != "all" else { return fixture.whereToWatch }
        return fixture.whereToWatch.filter { $0.region == broadcastRegion }
    }

    private var emptyBroadcastMessage: String {
        let status = broadcastRegion == "all"
            ? fixture.broadcastCoverage?.status
            : fixture.broadcastCoverage?.status(for: broadcastRegion)
        switch status {
        case "confirmed_none": return String(localized: "No listing confirmed for this region.")
        case "stale": return String(localized: "Broadcast listing may be out of date.")
        case "unverified": return String(localized: "Not verified yet.")
        default: return String(localized: "Broadcast listing not provided.")
        }
    }

    private func providerStatusLabel(_ status: String?) -> String {
        switch status?.lowercased() {
        case "success": return String(localized: "Available")
        case "disabled": return String(localized: "Disabled")
        case "partial": return String(localized: "Partial")
        case "rate_limited": return String(localized: "Rate limited")
        case "unavailable": return String(localized: "Unavailable")
        default: return String(localized: "Status unavailable")
        }
    }

    private func freshnessLabel(_ ageSeconds: Double) -> String {
        let seconds = Int(ageSeconds.rounded())
        if seconds < 60 { return String(localized: "\(seconds) seconds ago") }
        let minutes = seconds / 60
        if minutes < 60 { return String(localized: "\(minutes) minutes ago") }
        return String(localized: "\(minutes / 60) hours ago")
    }

    private var revealedScoreText: String? {
        guard scoresRevealed, fixture.status.scoreAvailable,
              let home = fixture.score?.fullTime?.home,
              let away = fixture.score?.fullTime?.away else { return nil }
        return "\(home) – \(away)"
    }
}

private extension View {
    func detailCardRows() -> some View {
        listRowBackground(Theme.Palette.bgCard)
    }
}
