import SwiftUI

public struct SettingsView: View {
    private let environment: AppEnvironment
    private let timeZone: TimeZone
    private let publicBaseURL: URL

    public init(environment: AppEnvironment, timeZone: TimeZone) {
        self.environment = environment
        self.timeZone = timeZone
        self.publicBaseURL = AppEnvironment.production.baseURL
    }

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    BrandLockup(markSize: 40, fontSize: 18)
                    Text(String(localized: "Spoiler-safe football fixtures."))
                        .font(Theme.Typography.data(.footnote))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
            .listRowBackground(Color.clear)

            Section(String(localized: "About")) {
                LabeledContent(String(localized: "Version"), value: Bundle.appVersion)
                LabeledContent(String(localized: "Build"), value: Bundle.buildNumber)
                LabeledContent(
                    String(localized: "Timezone"),
                    value: FixtureTime.accessibleZoneName(timeZone)
                )
                if environment != .production {
                    LabeledContent(String(localized: "Environment"), value: environment.name)
                        .accessibilityIdentifier("settings-environment")
                }
            }
            .listRowBackground(Theme.Palette.bgCard)

            Section(String(localized: "Scores")) {
                Text(String(localized: "Scores stay hidden until you choose Reveal scores on the fixture list."))
                    .accessibilityIdentifier("settings-score-explanation")
            }
            .listRowBackground(Theme.Palette.bgCard)

            Section(String(localized: "Data sources")) {
                Text(String(localized: "Fixture sources and availability are documented on the website."))
                Link(String(localized: "Data sources"), destination: pageURL("data-sources"))
                    .accessibilityIdentifier("settings-data-sources-link")
            }
            .listRowBackground(Theme.Palette.bgCard)

            Section(String(localized: "Support")) {
                Link(
                    String(localized: "support@trequa.io"),
                    destination: URL(string: "mailto:support@trequa.io")!
                )
                .accessibilityIdentifier("settings-support-email-link")
            }
            .listRowBackground(Theme.Palette.bgCard)

            Section(String(localized: "Website and legal")) {
                Link(String(localized: "Soccer Radar website"), destination: publicBaseURL)
                    .accessibilityIdentifier("settings-website-link")
                Link(String(localized: "Privacy"), destination: pageURL("privacy"))
                    .accessibilityIdentifier("settings-privacy-link")
                Link(String(localized: "Terms of Service"), destination: pageURL("terms"))
                    .accessibilityIdentifier("settings-terms-link")
            }
            .listRowBackground(Theme.Palette.bgCard)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bgPrimary.ignoresSafeArea())
        .tint(Theme.Palette.accentPrimary)
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
        .accessibilityIdentifier("settings-view")
    }

    private func pageURL(_ path: String) -> URL {
        publicBaseURL.appendingPathComponent(path)
    }
}
