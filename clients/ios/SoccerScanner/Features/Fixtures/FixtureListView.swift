import SwiftUI

public struct FixtureListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: FixtureListViewModel
    @State private var selectedFixture: Fixture?
    @State private var unavailableDestination = false
    @State private var routeOperationalFailure = false
    @State private var initialLoadCompleted = false
    @State private var claimedRoute: AppRoute?
    @State private var advancedFilterPresented = false
    @State private var draftFilter = FixtureFilter()
    private let router: AppRouter
    private let environment: AppEnvironment
    private let client: FixtureFetching

    public init(
        model: FixtureListViewModel,
        router: AppRouter,
        client: FixtureFetching,
        environment: AppEnvironment = .production
    ) {
        _model = State(initialValue: model)
        self.router = router
        self.client = client
        self.environment = environment
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                fixtureControls
                if unavailableDestination {
                    unavailableDestinationNotice
                }
                if routeOperationalFailure {
                    routeOperationalFailureNotice
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                .background(Theme.Palette.bgPrimary.ignoresSafeArea())
                .navigationTitle(String(localized: "Fixtures"))
                .navigationBarTitleDisplayMode(.inline)
                .themedNavigationBar()
                .toolbar { toolbarContent }
                .navigationDestination(item: $selectedFixture) { fixture in
                    FixtureDetailView(
                        fixture: fixture,
                        timeZone: model.selectedTimeZone,
                        scoresRevealed: Binding(
                            get: { model.scoresRevealed },
                            set: { revealed in
                                if model.scoresRevealed != revealed {
                                    model.toggleScores()
                                }
                            }
                        ),
                        providers: model.currentProviders,
                        freshness: model.currentFreshness,
                        client: client
                    )
                }
        }
        .task {
            await model.load()
            initialLoadCompleted = true
            await consumeRouteIfNeeded(router.route)
        }
        .onChange(of: router.route) { _, route in
            guard initialLoadCompleted else { return }
            Task { await consumeRouteIfNeeded(route) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard initialLoadCompleted, phase == .active, router.route == nil else { return }
            Task { await model.load() }
        }
        .sheet(isPresented: $advancedFilterPresented) {
            AdvancedFixtureFilterSheet(
                filter: $draftFilter,
                competitionOptions: model.availableCompetitionOptions,
                countryOptions: model.availableCountryOptions,
                onApply: {
                    model.applyFilter($0)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.Palette.bgSecondary)
        }
        .searchable(
            text: Binding(
                get: { model.filter.searchText },
                set: { model.setSearchText($0) }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search teams or competitions"
        )
        .accessibilityIdentifier("fixture-search")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            BrandLockup()
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    model.toggleScores()
                } label: {
                    ToolbarIcon(
                        title: model.scoresRevealed
                            ? String(localized: "Hide scores")
                            : String(localized: "Reveal scores"),
                        systemImage: model.scoresRevealed ? "eye" : "eye.slash",
                        active: model.scoresRevealed
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("score-toggle")

                NavigationLink {
                    SettingsView(
                        environment: environment,
                        timeZone: model.selectedTimeZone
                    )
                } label: {
                    ToolbarIcon(title: String(localized: "Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-link")
            }
        }
    }

    private var fixtureControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical, showsIndicators: false) {
                    fixtureControlContent
                }
                .frame(maxHeight: 240)
                .accessibilityIdentifier("fixture-controls-scroll")
            } else {
                fixtureControlContent
            }
        }
    }

    private var fixtureControlContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // At accessibility sizes the day controls come first so they stay
            // on screen; the summary header would push them out of view.
            if !dynamicTypeSize.isAccessibilitySize {
                pageHeader
            }
            VStack(spacing: Theme.Spacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        dayNavigationButtons
                        datePicker
                        Spacer(minLength: 0)
                        timeZoneMenu
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.sm) {
                            dayNavigationButtons
                            datePicker
                        }
                        timeZoneMenu
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    selectedDayText
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                statusFilter
                advancedFilterButton
            }
            .padding(Theme.Spacing.md)
            .cardSurface(fill: Theme.Palette.bgSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    /// The web dashboard's page header: title, selected day, and day summary.
    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(String(localized: "Fixtures"))
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            selectedDayText
            if let summary = daySummary {
                summaryLine(summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedDayText: some View {
        Text(FixtureTime.dayHeading(for: model.day, in: model.selectedTimeZone))
            .font(Theme.Typography.data(.footnote))
            .foregroundStyle(Theme.Palette.textSecondary)
            .accessibilityLabel(String(localized: "Selected fixture day"))
            .accessibilityValue(model.day)
            .accessibilityIdentifier("selected-day")
    }

    private var daySummary: FixtureDaySummary? {
        switch model.state {
        case .loaded(let data), .partial(let data, _), .stale(let data):
            return FixtureDaySummary(fixtures: data.fixtures)
        case .idle, .loading, .empty, .failed:
            return nil
        }
    }

    private func summaryLine(_ summary: FixtureDaySummary) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(summary.matchesLabel)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(String(localized: "\(summary.live) live"))
                .foregroundStyle(summary.live > 0 ? Theme.Palette.accentPrimary : Theme.Palette.textMuted)
            Text(String(localized: "\(summary.upcoming) upcoming"))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(String(localized: "\(summary.finished) finished"))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .font(Theme.Typography.data(.caption))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityIdentifier("fixtures-summary")
    }

    @ViewBuilder
    private var statusFilter: some View {
        if dynamicTypeSize.isAccessibilitySize {
            statusPicker
                .pickerStyle(.menu)
                .tint(Theme.Palette.accentPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            statusPicker.pickerStyle(.segmented)
        }
    }

    private var statusPicker: some View {
        Picker(
            String(localized: "Status"),
            selection: Binding(
                get: { model.filter.status },
                set: { model.setStatusFilter($0) }
            )
        ) {
            ForEach(FixtureStatusFilter.allCases, id: \.self) { status in
                Text(statusLabel(status)).tag(status)
            }
        }
        .accessibilityIdentifier("status-filter")
    }

    private var advancedFilterButton: some View {
        Button {
            draftFilter = model.filter
            advancedFilterPresented = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Label(String(localized: "Advanced filters"), systemImage: "slider.horizontal.3")
                Spacer(minLength: 0)
                Text(String(model.activeFilterCount))
                    .font(Theme.Typography.data(.caption, weight: .bold))
                    .foregroundStyle(
                        model.activeFilterCount > 0 ? Theme.Palette.bgPrimary : Theme.Palette.textMuted
                    )
                    .frame(minWidth: 22, minHeight: 22)
                    .background(
                        Circle().fill(
                            model.activeFilterCount > 0
                                ? Theme.Palette.accentPrimary
                                : Theme.Palette.bgTertiary
                        )
                    )
                    .accessibilityIdentifier("advanced-filter-count")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SurfaceButtonStyle())
        .accessibilityLabel(String(localized: "Advanced filters"))
        .accessibilityValue(String(localized: "\(model.activeFilterCount) active filters"))
        .accessibilityIdentifier("advanced-filter-button")
    }

    private var unavailableDestinationNotice: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Label(String(localized: "Fixture unavailable"), systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
            Text(String(localized: "This match is no longer available. You can continue browsing fixtures."))
                .font(.footnote)
            Spacer(minLength: 0)
            Button(String(localized: "Dismiss")) {
                unavailableDestination = false
            }
            .font(.footnote)
        }
        .noticeSurface(Theme.Palette.warning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fixture-unavailable")
    }

    private var routeOperationalFailureNotice: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Label(String(localized: "Fixture couldn't be opened"), systemImage: "wifi.exclamationmark")
                .font(.footnote.weight(.semibold))
            Text(String(localized: "The fixture could not be opened. Try again later."))
                .font(.footnote)
            Spacer(minLength: 0)
            Button(String(localized: "Dismiss")) {
                routeOperationalFailure = false
            }
            .font(.footnote)
        }
        .noticeSurface(Theme.Palette.danger)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fixture-route-error")
    }

    private var dayNavigationButtons: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button {
                Task { await model.shiftDay(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(String(localized: "Previous day"))
            .accessibilityIdentifier("previous-day")

            Button(String(localized: "Today")) {
                Task { await model.selectDay(FixtureTime.today(in: model.selectedTimeZone)) }
            }
            .accessibilityIdentifier("today-day")

            Button {
                Task { await model.shiftDay(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(String(localized: "Next day"))
            .accessibilityIdentifier("next-day")
        }
        .buttonStyle(SurfaceButtonStyle())
    }

    private var datePicker: some View {
        DatePicker(
            String(localized: "Fixture date"),
            selection: Binding(
                get: { FixtureTime.datePickerDate(for: model.day, in: model.selectedTimeZone) },
                set: { date in
                    Task {
                        await model.selectDay(
                            FixtureTime.calendarDate(for: date, in: model.selectedTimeZone)
                        )
                    }
                }
            ),
            displayedComponents: .date
        )
        .labelsHidden()
        .tint(Theme.Palette.accentPrimary)
        .environment(\.timeZone, model.selectedTimeZone)
        .accessibilityLabel(String(localized: "Select fixture date"))
        .accessibilityValue(model.day)
        .accessibilityIdentifier("date-picker")
    }

    private var timeZoneMenu: some View {
        Menu {
            Button {
                model.selectedTimeZone = .current
            } label: {
                Text(String(localized: "Device local time"))
            }
            .accessibilityIdentifier("timezone-device")

            Divider()

            ForEach(commonTimeZoneIdentifiers, id: \.self) { identifier in
                if let timeZone = TimeZone(identifier: identifier) {
                    Button {
                        model.selectedTimeZone = timeZone
                    } label: {
                        Text(identifier)
                    }
                    .accessibilityIdentifier("timezone-\(identifier)")
                }
            }
        } label: {
            Label(FixtureTime.zoneLabel(model.selectedTimeZone), systemImage: "globe")
                .font(Theme.Typography.data(.caption, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: Theme.minimumTapTarget)
                .cardSurface(fill: Theme.Palette.bgSecondary, radius: Theme.Radius.control)
        }
        .accessibilityLabel(FixtureTime.accessibleZoneName(model.selectedTimeZone))
        .accessibilityValue(model.selectedTimeZone.identifier)
        .accessibilityIdentifier("timezone-menu")
    }

    private var commonTimeZoneIdentifiers: [String] {
        [
            "UTC",
            "America/New_York",
            "America/Los_Angeles",
            "Europe/London",
            "Europe/Berlin",
            "Asia/Tokyo",
            "Australia/Sydney",
        ]
    }

    private func statusLabel(_ status: FixtureStatusFilter) -> String {
        switch status {
        case .all: return String(localized: "All")
        case .live: return String(localized: "Live")
        case .upcoming: return String(localized: "Upcoming")
        case .finished: return String(localized: "Finished")
        }
    }

    private func consumeRouteIfNeeded(_ route: AppRoute?) async {
        guard let route else { return }
        guard claimedRoute != route else { return }
        claimedRoute = route
        defer {
            if claimedRoute == route {
                claimedRoute = nil
            }
        }

        switch route {
        case .fixture(let id, let timeZoneIdentifier, let calendarDay):
            unavailableDestination = false
            routeOperationalFailure = false
            let outcome = await model.openRouteFixture(
                id: id,
                timeZoneIdentifier: timeZoneIdentifier,
                calendarDay: calendarDay,
                isCurrentRoute: { router.route == route }
            )
            guard router.route == route else { return }
            switch outcome {
            case .found(let fixture):
                unavailableDestination = false
                routeOperationalFailure = false
                selectedFixture = fixture
            case .missing:
                unavailableDestination = true
            case .failed:
                routeOperationalFailure = true
            case .superseded:
                break
            }
        case .unsupported:
            unavailableDestination = false
            routeOperationalFailure = false
        }

        router.consume(route)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView {
                Text(String(localized: "Loading fixtures"))
                    .font(Theme.Typography.data(.footnote))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .tint(Theme.Palette.accentPrimary)
            .accessibilityIdentifier("fixtures-loading")
        case .loaded(let data):
            fixtureList(data, notice: model.notice(model.loadErrorNotice))
        case .stale(let data):
            fixtureList(data, notice: model.notice(String(localized: "Showing recently cached fixtures.")))
        case .partial(let data, let reason):
            fixtureList(data, notice: model.notice(reason))
        case .empty:
            ContentUnavailableView(
                String(localized: "No fixtures"),
                systemImage: "calendar",
                description: Text(String(localized: "No matches are scheduled for this day."))
            )
            .accessibilityIdentifier("fixtures-empty")
        case .failed(let error):
            errorView(error)
        }
    }

    private func fixtureList(_ data: FixtureDayViewData, notice: String?) -> some View {
        List {
            if let notice {
                Section {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.md)
                        .cardSurface(
                            fill: Theme.Palette.warning.opacity(0.12),
                            border: Theme.Palette.warning.opacity(0.6)
                        )
                        .accessibilityIdentifier("fixtures-notice")
                }
                .themedListRows()
            }
            if model.filteredFixtures.isEmpty {
                Section {
                    ContentUnavailableView(
                        String(localized: "No matching fixtures"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(String(localized: "No matches match your filters."))
                    )
                    .accessibilityIdentifier("fixtures-filtered-empty")
                }
                .themedListRows()
            } else {
                ForEach(FixtureGrouping.byCompetition(model.filteredFixtures)) { group in
                    Section {
                        ForEach(group.fixtures) { fixture in
                            fixtureButton(fixture)
                        }
                    } header: {
                        CompetitionHeader(group: group)
                    }
                    .themedListRows()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bgPrimary)
        .refreshable { await model.load() }
        .accessibilityIdentifier("fixtures-list")
    }

    private func fixtureButton(_ fixture: Fixture) -> some View {
        Button {
            selectedFixture = fixture
        } label: {
            FixtureRow(
                fixture: fixture,
                timeZone: model.selectedTimeZone,
                scoreText: model.scoreText(for: fixture)
            )
        }
        .buttonStyle(.plain)
        // The identifier belongs on the control, not its label:
        // the Button is the element that is queried and tapped.
        .accessibilityLabel(
            "\(fixture.homeTeam.name) versus \(fixture.awayTeam.name), "
                + "\(fixture.status.label), "
                + "\(FixtureTime.kickoff(fixture.utcDate, in: model.selectedTimeZone))"
        )
        .accessibilityIdentifier("fixture-row-\(fixture.id)")
    }

    private func errorView(_ error: APIError) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Fixtures unavailable"), systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.userMessage)
        } actions: {
            if error.isRetryable {
                Button(String(localized: "Try again")) {
                    Task { await model.load() }
                }
                .buttonStyle(SurfaceButtonStyle(prominent: true))
                .accessibilityIdentifier("fixtures-retry")
            }
        }
        // Without `.contain` the view is not an accessibility container, so the
        // identifier is not queryable by assistive technology or UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fixtures-error")
    }
}

/// The web header's square icon buttons; the title stays in the accessibility
/// tree while only the icon is drawn.
private struct ToolbarIcon: View {
    let title: String
    let systemImage: String
    var active = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(active ? Theme.Palette.accentPrimary : Theme.Palette.textPrimary)
            .frame(width: 38, height: 38)
            .cardSurface(
                fill: Theme.Palette.bgSecondary,
                border: active ? Theme.Palette.accentPrimary : Theme.Palette.borderColor,
                radius: Theme.Radius.control
            )
            .contentShape(Rectangle())
    }
}

/// Competition group heading, as on the web match schedule.
private struct CompetitionHeader: View {
    let group: FixtureCompetitionGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(group.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.sm)
            Text(group.countLabel)
                .font(Theme.Typography.data(.caption2))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .textCase(nil)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.bgPrimary)
        .listRowInsets(EdgeInsets())
    }
}

private extension View {
    /// Rows draw their own card, so the list contributes no chrome of its own.
    func themedListRows() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Theme.Spacing.xs + 2,
                leading: Theme.Spacing.lg,
                bottom: Theme.Spacing.xs + 2,
                trailing: Theme.Spacing.lg
            ))
    }

    func noticeSurface(_ tint: Color) -> some View {
        self
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(Theme.Spacing.md)
            .cardSurface(fill: tint.opacity(0.12), border: tint.opacity(0.6))
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
    }
}

private struct AdvancedFixtureFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: FixtureFilter
    let competitionOptions: [String]
    let countryOptions: [String]
    let onApply: (FixtureFilter) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    FilterField(title: String(localized: "Competition")) {
                        Picker(
                            String(localized: "Competition"),
                            selection: Binding(
                                get: { filter.competition ?? "" },
                                set: { filter.competition = $0.isEmpty ? nil : $0 }
                            )
                        ) {
                            Text(String(localized: "All competitions")).tag("")
                            ForEach(competitionOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("advanced-competition")
                    }

                    FilterField(title: String(localized: "Country or area")) {
                        Picker(
                            String(localized: "Country or area"),
                            selection: Binding(
                                get: { filter.country ?? "" },
                                set: { filter.country = $0.isEmpty ? nil : $0 }
                            )
                        ) {
                            Text(String(localized: "All countries or areas")).tag("")
                            ForEach(countryOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("advanced-country")
                    }

                    FilterField(title: String(localized: "Time window")) {
                        Picker(String(localized: "Time window"), selection: $filter.timeWindow) {
                            ForEach(FixtureTimeWindow.allCases, id: \.self) { window in
                                Text(window.label).tag(window)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("advanced-time-window")
                    }

                    FilterField(title: String(localized: "Sort")) {
                        Picker(String(localized: "Sort fixtures"), selection: $filter.sort) {
                            ForEach(FixtureSort.allCases, id: \.self) { sort in
                                Text(sort.label).tag(sort)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("advanced-sort")
                    }

                    Toggle(String(localized: "Hide finished fixtures"), isOn: $filter.hideFinished)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .tint(Theme.Palette.accentPrimary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(minHeight: Theme.minimumTapTarget)
                        .cardSurface(fill: Theme.Palette.bgCard, radius: Theme.Radius.control)
                        .accessibilityIdentifier("advanced-hide-finished")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
                .accessibilityIdentifier("advanced-filter-scroll")
                .scrollDismissesKeyboard(.interactively)

                actionBar
            }
            .background(Theme.Palette.bgSecondary.ignoresSafeArea())
            .navigationTitle(String(localized: "Filter fixtures"))
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar(Theme.Palette.bgSecondary)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("advanced-filter-sheet")
        }
        .onChange(of: competitionOptions) { _, options in
            if let selected = filter.competition, !options.contains(selected) {
                filter.competition = nil
            }
        }
        .onChange(of: countryOptions) { _, options in
            if let selected = filter.country, !options.contains(selected) {
                filter.country = nil
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(String(localized: "Reset")) {
                filter.resetAdvanced()
            }
            .buttonStyle(SurfaceButtonStyle())
            .accessibilityIdentifier("advanced-filter-reset")

            Spacer(minLength: Theme.Spacing.sm)

            Button(String(localized: "Close")) {
                dismiss()
            }
            .buttonStyle(SurfaceButtonStyle())
            .accessibilityIdentifier("advanced-filter-close")

            Button(String(localized: "Apply filters")) {
                onApply(filter)
                dismiss()
            }
            .buttonStyle(SurfaceButtonStyle(prominent: true))
            .accessibilityIdentifier("advanced-filter-apply")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.bgSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Palette.borderColor).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A labelled select, styled like the web filter panel's fields.
private struct FilterField<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .accessibilityHidden(true)
            control
                .tint(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xs)
                .cardSurface(fill: Theme.Palette.bgCard, radius: Theme.Radius.control)
        }
    }
}

struct FixtureRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let fixture: Fixture
    let timeZone: TimeZone
    let scoreText: String?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                normalLayout
            }
        }
        .padding(Theme.Spacing.md + 2)
        .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget, alignment: .leading)
        .cardSurface(
            border: fixture.status.isActive
                ? Theme.Palette.accentPrimary.opacity(0.55)
                : Theme.Palette.borderColor
        )
        .contentShape(Rectangle())
    }

    /// Web fixture card: status and kickoff, the score slot, crested team
    /// lines, then competition, venue, and a details affordance.
    private var normalLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                StatusBadge(status: fixture.status)
                Text(FixtureTime.kickoff(fixture.utcDate, in: timeZone))
                    .font(Theme.Typography.data(.caption))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .monospacedDigit()
                Spacer(minLength: Theme.Spacing.sm)
                scoreIndicator
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                teamLine(fixture.homeTeam)
                teamLine(fixture.awayTeam)
            }

            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    if let competition = fixture.competition?.displayName {
                        Text(competition)
                    }
                    if let venue = fixture.venue, !venue.isEmpty {
                        Text(venue)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                detailsAffordance
            }
        }
    }

    private func teamLine(_ team: Team) -> some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            TeamCrest(url: team.crest, size: 30)
            Text(team.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
        }
    }

    private var detailsAffordance: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(String(localized: "Details"))
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .cardSurface(fill: Theme.Palette.bgSecondary, radius: Theme.Radius.control)
        // The whole card is the control; this is a visual cue only.
        .accessibilityHidden(true)
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    StatusBadge(status: fixture.status)
                    Text(FixtureTime.kickoff(fixture.utcDate, in: timeZone))
                        .font(Theme.Typography.data(.caption))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Theme.Spacing.sm)
                scoreIndicator
            }

            accessibilityTeamNames
            competitionName
        }
    }

    private var accessibilityTeamNames: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(fixture.homeTeam.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fixture-home-team-\(fixture.id)")
            Text(fixture.awayTeam.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fixture-away-team-\(fixture.id)")
        }
        .layoutPriority(2)
    }

    @ViewBuilder
    private var competitionName: some View {
        if let competition = fixture.competition?.displayName {
            Text(competition)
                .font(.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fixture-competition-\(fixture.id)")
        }
    }

    @ViewBuilder
    private var scoreIndicator: some View {
        if let scoreText {
            Text(scoreText)
                .font(Theme.Typography.data(.title3, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("fixture-score")
        } else if fixture.status.scoreAvailable && fixture.hasFullTimeScore {
            // A score exists but is deliberately concealed.
            scorePill(String(localized: "Score hidden"), systemImage: "eye.slash")
                .accessibilityIdentifier("fixture-score-hidden")
        } else if fixture.status.scoreAvailable {
            scorePill(String(localized: "Score unavailable"), systemImage: "questionmark.circle")
                .accessibilityIdentifier("fixture-score-unavailable")
        }
    }

    private func scorePill(_ title: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(title)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

#Preview("Loaded") {
    let client = PreviewFixtureClient()
    FixtureListView(
        model: FixtureListViewModel(client: client),
        router: AppRouter(),
        client: client,
        environment: .development
    )
}
