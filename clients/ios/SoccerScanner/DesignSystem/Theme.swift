import SwiftUI
import UIKit

/// Shared visual language, mirroring the web dashboard (`static/css/base.css`)
/// so the native app and soccer-radar.com read as one product. The app runs in
/// a fixed dark appearance, as the website does.
public enum Theme {
    /// One-to-one with the web design tokens; `tests/test_ios_design_parity.py`
    /// fails if a value drifts from `base.css`.
    public enum Palette {
        public static let bgPrimary = Color(hex: 0x000000)
        public static let bgSecondary = Color(hex: 0x121212)
        public static let bgTertiary = Color(hex: 0x252525)
        public static let bgCard = Color(hex: 0x191919)
        public static let borderColor = Color(hex: 0x404040)
        public static let textPrimary = Color(hex: 0xFFFFFF)
        public static let textSecondary = Color(hex: 0xC8C8C8)
        public static let textMuted = Color(hex: 0xA5A5A5)
        public static let accentPrimary = Color(hex: 0x7CFF00)
        public static let accentSecondary = Color(hex: 0xA8FF4D)
        public static let success = Color(hex: 0x22C55E)
        public static let warning = Color(hex: 0xF59E0B)
        public static let danger = Color(hex: 0xEF4444)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radius {
        public static let card: CGFloat = 12
        public static let control: CGFloat = 8
        public static let badge: CGFloat = 6
    }

    /// Web fonts: Orbitron for the wordmark, a monospace face for data
    /// (IBM Plex Mono on the web, SF Mono here) and the system UI font.
    public enum Typography {
        public static func brand(size: CGFloat) -> Font {
            .custom("Orbitron", size: size, relativeTo: .headline).weight(.bold)
        }

        public static func data(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
            .system(style, design: .monospaced, weight: weight)
        }
    }

    /// Minimum comfortable hit target per Apple's HIG.
    public static let minimumTapTarget: CGFloat = 44

    /// UIKit-backed controls (segmented pickers) do not follow SwiftUI styling,
    /// so they are themed once at launch.
    @MainActor
    public static func applyAppearance() {
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(Palette.bgSecondary)
        segmented.selectedSegmentTintColor = UIColor(Palette.bgTertiary)
        segmented.setTitleTextAttributes(
            [.foregroundColor: UIColor(Palette.textSecondary)],
            for: .normal
        )
        segmented.setTitleTextAttributes(
            [.foregroundColor: UIColor(Palette.accentPrimary)],
            for: .selected
        )
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Surfaces

/// The web card: dark fill, 1pt neutral border, 12pt corners.
struct CardSurface: ViewModifier {
    var fill: Color = Theme.Palette.bgCard
    var border: Color = Theme.Palette.borderColor
    var radius: CGFloat = Theme.Radius.card

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(
        fill: Color = Theme.Palette.bgCard,
        border: Color = Theme.Palette.borderColor,
        radius: CGFloat = Theme.Radius.card
    ) -> some View {
        modifier(CardSurface(fill: fill, border: border, radius: radius))
    }

    /// Solid black bar, as on the web header, instead of the translucent default.
    func themedNavigationBar(_ background: Color = Theme.Palette.bgPrimary) -> some View {
        self
            .toolbarBackground(background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Uppercase monospace section label, as on the web ("ALL COMPETITIONS").
    func sectionLabelStyle() -> some View {
        self
            .font(Theme.Typography.data(.caption2, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.textMuted)
    }
}

/// Bordered dark button; `prominent` is the neon primary action ("Apply").
struct SurfaceButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.Palette.bgPrimary : Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
            .cardSurface(
                fill: prominent ? Theme.Palette.accentPrimary : Theme.Palette.bgSecondary,
                border: prominent ? Theme.Palette.accentPrimary : Theme.Palette.borderColor,
                radius: Theme.Radius.control
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

// MARK: - Brand

/// The web header's radar mark, drawn natively from the same 360-unit SVG.
struct RadarMark: View {
    private static let outerRing = Color(hex: 0x59BE00)
    private static let innerRing = Color(hex: 0x68DF00)
    private static let light = Color(hex: 0xF2F2F2)
    private static let ringDashes: [CGFloat] = [162, 22, 45, 22, 132, 22]
    private static let blips: [(CGFloat, CGFloat)] = [(102, 136), (238, 82), (242, 240)]

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 360
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            func ring(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(
                    x: (180 - radius) * unit, y: (180 - radius) * unit,
                    width: radius * 2 * unit, height: radius * 2 * unit
                ))
            }
            func arc(from start: Double, to end: Double) -> Path {
                var path = Path()
                // y-down coordinates: increasing angles run visually clockwise,
                // which SwiftUI expresses as `clockwise: false`.
                path.addArc(center: point(180, 180), radius: 154 * unit,
                            startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                return path
            }
            let accent = Theme.Palette.accentPrimary

            var sweep = Path()
            sweep.move(to: point(180, 180))
            sweep.addLine(to: point(180, 44))
            sweep.addArc(center: point(180, 180), radius: 136 * unit,
                         startAngle: .degrees(-90), endAngle: .degrees(-31.5), clockwise: false)
            sweep.closeSubpath()
            context.fill(sweep, with: .linearGradient(
                Gradient(colors: [accent.opacity(0.42), accent.opacity(0.03)]),
                startPoint: point(180, 180), endPoint: point(294, 74)
            ))

            context.stroke(ring(116), with: .color(Self.outerRing), lineWidth: 6 * unit)
            context.stroke(
                ring(78).applying(
                    CGAffineTransform(translationX: 180 * unit, y: 180 * unit)
                        .rotated(by: -.pi / 2)
                        .translatedBy(x: -180 * unit, y: -180 * unit)
                ),
                with: .color(Self.innerRing),
                style: StrokeStyle(lineWidth: 6 * unit, dash: Self.ringDashes.map { $0 * unit })
            )

            let round = StrokeStyle(lineWidth: 8 * unit, lineCap: .round)
            context.stroke(arc(from: 183, to: 267), with: .color(Self.light), style: round)
            context.stroke(arc(from: 273, to: 357), with: .color(Self.light), style: round)
            context.stroke(arc(from: 3, to: 87), with: .color(accent), style: round)
            context.stroke(arc(from: 93, to: 177), with: .color(accent), style: round)

            var vertical = Path()
            vertical.move(to: point(180, 18))
            vertical.addLine(to: point(180, 342))
            context.stroke(vertical, with: .color(Self.light), lineWidth: 10 * unit)
            var horizontal = Path()
            horizontal.move(to: point(18, 180))
            horizontal.addLine(to: point(342, 180))
            context.stroke(horizontal, with: .color(accent), lineWidth: 7 * unit)

            for (x, y) in Self.blips {
                context.fill(Path(ellipseIn: CGRect(
                    x: (x - 12) * unit, y: (y - 12) * unit, width: 24 * unit, height: 24 * unit
                )), with: .color(accent))
            }

            context.fill(ring(50), with: .color(Theme.Palette.bgPrimary))
            context.stroke(ring(42), with: .color(Self.light), lineWidth: 10 * unit)
            context.fill(ring(12), with: .color(Self.light))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Radar mark plus the "SOCCER RADAR" Orbitron wordmark from the web header.
struct BrandLockup: View {
    var markSize: CGFloat = 28
    var fontSize: CGFloat = 14

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RadarMark()
                .frame(width: markSize, height: markSize)
            HStack(spacing: 6) {
                Text(verbatim: "SOCCER").foregroundStyle(Theme.Palette.textPrimary)
                Text(verbatim: "RADAR").foregroundStyle(Theme.Palette.accentPrimary)
            }
            .font(Theme.Typography.brand(size: fontSize))
            .tracking(fontSize * 0.08)
            .lineLimit(1)
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Soccer Radar"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Provider-supplied crest in the web's circular frame, with a neutral shield
/// when the provider sent none or it fails to load.
struct TeamCrest: View {
    let url: URL?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.bgTertiary)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.16)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.Palette.borderColor, lineWidth: 1))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "shield.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.26)
            .foregroundStyle(Theme.Palette.textMuted)
    }
}

// MARK: - Status

public extension MatchStatus {
    /// Live states share the brand accent so HT/ET/PEN read as a family while
    /// remaining textually distinct.
    var tint: Color {
        switch self {
        case .inProgress, .halfTime, .extraTime, .penalties:
            return Theme.Palette.accentPrimary
        case .delayed, .postponed, .suspended:
            return Theme.Palette.warning
        case .cancelled, .abandoned:
            return Theme.Palette.danger
        case .finished:
            return Theme.Palette.textPrimary
        case .scheduled, .unknown:
            return Theme.Palette.textMuted
        }
    }
}

public struct StatusBadge: View {
    private let status: MatchStatus

    public init(status: MatchStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            if status.isActive {
                Circle()
                    .fill(status.tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: status.tint.opacity(0.8), radius: 3)
            }
            Text(status.shortLabel)
                .font(Theme.Typography.data(.caption, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(status.tint)
        // The badge is an abbreviation; announce the full meaning instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
        .accessibilityHint(status.accessibilityDescription)
    }
}
