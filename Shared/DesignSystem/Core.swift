import SwiftUI

import SwiftUI

struct RentroWordmark: View {
    var body: some View {
        Text("Rentro")
            .font(.system(size: 40, weight: .heavy, design: .rounded))
            .tracking(-1)
            .foregroundStyle(Color.textAccent)
            .accessibilityLabel("Rentro")
    }
}

enum PillTone {
    case success, warning, danger
    var fg: Color { switch self { case .success: .textSuccess; case .warning: .textWarning; case .danger: .textDanger } }
    var bg: Color { switch self { case .success: .bgSuccess; case .warning: .bgWarning; case .danger: .bgDanger } }
}

struct StatusPill: View {
    let text: String
    let tone: PillTone
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.fg)
            .fixedSize()                                                  // a status word never breaks across lines
            .padding(.horizontal, Space.s12).padding(.vertical, Space.s4)
            .background(tone.bg, in: Capsule())
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.r16))
    }
}
extension View { func card() -> some View { modifier(CardBackground()) } }

struct SectionHeading<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    var body: some View {
        // Side by side while it fits; stacked (never hyphenated) at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack {
                heading
                Spacer()
                trailing
            }
            VStack(alignment: .leading, spacing: Space.s4) { heading; trailing }
        }
    }
    private var heading: some View {
        Text(title).font(.headline).foregroundStyle(Color.textPrimary).accessibilityAddTraits(.isHeader)
    }
}

struct IconTile: View {
    let symbol: String
    var warning = false
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40      // grows with text so the symbol never overflows its tile
    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(warning ? Color.iconWarning : Color.iconDefault)
            .frame(width: side, height: side)
            .background(warning ? Color.bgWarning : Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.r12))
            .accessibilityHidden(true)
    }
}

/// Leading label, trailing value on one center line (PRD 5.3).
struct AlignedLabelValueRow: View {
    let label: LocalizedStringKey
    let value: String
    var body: some View {
        // Figma 44:640 / 44:688: dark label, quieter trailing value.
        // One line while both fit; otherwise label above value, so neither is squeezed into a narrow column.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(Color.textPrimary)
                Spacer(minLength: Space.s16)
                Text(value).font(.subheadline).foregroundStyle(Color.textSecondary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(label).foregroundStyle(Color.textPrimary)
                Text(value).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Native empty state; `reset` shows Clear Filters for the filtered-empty case.
struct EmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String
    var action: (title: LocalizedStringKey, run: () -> Void)?
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let action { Button(action.title, action: action.run).buttonStyle(.borderedProminent).tint(.brandSolid) }
        }
        .foregroundStyle(Color.textSecondary)
    }
}

/// Label above a 48pt surface field (PRD 5.3).
struct RentroFormField<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            content
                .padding(.horizontal, Space.s12)
                .frame(minHeight: 48, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.r16))
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.textOnBrand)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.brandSolid, in: RoundedRectangle(cornerRadius: Radius.r16))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

struct SummaryCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text(title).textCase(.uppercase).font(.caption).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.s8)
            VStack(alignment: .leading, spacing: Space.s12) { content }.card()
        }
    }
}
