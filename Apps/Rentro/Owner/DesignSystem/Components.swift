import SwiftUI

struct RentroSearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey = "Search devices, customers, bookings"
    var id: String
    var onSubmit: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        HStack(spacing: Space.s8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.textSecondary).accessibilityHidden(true)
            // A long placeholder would shrink to fit at large sizes; "Search" stays readable.
            TextField("", text: $text, prompt: Text(size.isAccessibilitySize ? "Search" : prompt).foregroundStyle(Color.textSecondary))
                .foregroundStyle(Color.textPrimary)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(id)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.s12)
        .frame(minHeight: 48)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.r16))
    }
}

/// Teal title block shared by the tab roots (Figma hero); extends under the status bar.
struct Hero: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var query: Binding<String>?
    var searchID = ""
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Chrome is capped at accessibility2/1 so the hero cannot crowd out the content, but it still wraps instead of truncating.
            Text(title).font(.largeTitle.bold()).foregroundStyle(Color.textOnBrand)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(Color.textHeaderSecondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1).fixedSize(horizontal: false, vertical: true)
            if let query {
                RentroSearchField(text: query, id: searchID, onSubmit: onSubmit).padding(.top, Space.s16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s20)
        .padding(.top, Space.s16)
        .padding(.bottom, Space.s24)
        .background(Color.brandSolid.ignoresSafeArea(edges: .top))
    }
}

extension RentalBadge {
    var tone: PillTone {
        switch self {
        case .active, .returned: .success
        case .overdue: .danger
        case .upcoming, .dueToday, .cancelled: .warning
        }
    }
}

extension DeviceStatus {
    var tone: PillTone { switch self { case .available: .success; case .rented, .maintenance: .warning } }
}

struct FleetKpiCard: View {
    let symbol: String
    let value: Int
    let label: LocalizedStringKey
    var warning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s8) {
                HStack(spacing: Space.s12) {
                    IconTile(symbol: symbol, warning: warning)
                    Text("\(value)").font(.title.bold()).foregroundStyle(Color.textPrimary)
                }
                Text(label).font(.footnote).foregroundStyle(Color.textSecondary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label) + Text(verbatim: ", \(value)"))
    }
}

struct FilterPills<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var id: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s12) {
                ForEach(options, id: \.self) { o in
                    let on = o == selection
                    Button { selection = o } label: {
                        Text(title(o)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Color.textOnBrand : Color.textOnSoft)
                            .padding(.horizontal, Space.s16)
                            .frame(minHeight: 44)
                            .background(on ? Color.brandSolid : Color.bgSubtle, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(id).\(title(o).lowercased())")
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// Shared page scaffold: hero above a scrolling canvas.
struct TabPage<Content: View>: View {
    let hero: Hero
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        let stack = VStack(alignment: .leading, spacing: Space.s16) { content }
            .padding(.horizontal, Space.s20).padding(.vertical, Space.s16)
        Group {
            if size.isAccessibilitySize {
                // At large text the hero scrolls away with the page so the content keeps the screen.
                ScrollView { VStack(spacing: 0) { hero; stack } }
            } else {
                VStack(spacing: 0) { hero; ScrollView { stack } }
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Whole-rupiah input: "Rp" prefix, number pad, never a Double (PRD 4.1).
struct RupiahField: View {
    @Binding var value: Int
    var id: String
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: Space.s8) {
            Text("Rp").foregroundStyle(Color.textSecondary)
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .focused($focused)
                .accessibilityIdentifier(id)
                .onChange(of: text) { _, new in
                    guard focused else { return }
                    let n = Rupiah.parse(new)
                    if n != value { value = n }
                    // Raw digits while editing: rewriting the text mid-typing drops keystrokes. Only strip pasted separators.
                    let digits = String(new.filter(\.isWholeNumber).prefix(12))
                    if digits != new { text = digits }
                }
                .onChange(of: focused) { _, on in
                    text = on ? (value == 0 ? "" : String(value)) : Rupiah.group(value, blankWhenZero: true)
                }
        }
        .foregroundStyle(Color.textPrimary)
        .onAppear { text = Rupiah.group(value, blankWhenZero: true) }
        .onChange(of: value) { _, v in if !focused { text = Rupiah.group(v, blankWhenZero: true) } }
    }
}

/// Digits <-> "250.000" for the Rupiah field; whole rupiah only.
enum Rupiah {
    static func parse(_ s: String) -> Int { Int(String(s.filter(\.isWholeNumber).prefix(12))) ?? 0 }
    static func group(_ n: Int, blankWhenZero: Bool = false) -> String {
        n == 0 && blankWhenZero ? "" : String(Money(idr: Int64(n)).formatted.dropFirst(3))
    }
}

extension Date {
    /// "12:42" in the business timezone.
    func clock(_ tz: TimeZone, locale: Locale = .current) -> String { formatted(Date.FormatStyle(timeZone: tz).locale(locale).hour().minute()) }
    /// "24 Oct · 10:00" in the business timezone (Figma 44:640); the year is added only for another year (PRD 10.2).
    func stamp(_ tz: TimeZone, now: Date = .now, locale: Locale = .current) -> String {
        var cal = Calendar.current
        cal.timeZone = tz
        let sameYear = cal.component(.year, from: self) == cal.component(.year, from: now)
        var dayStyle = Date.FormatStyle(timeZone: tz).locale(locale).day().month(.abbreviated)
        if !sameYear { dayStyle = dayStyle.year() }
        let time = formatted(Date.FormatStyle(timeZone: tz).locale(locale).hour().minute())
        return "\(formatted(dayStyle)) · \(time)"
    }
}

extension Int {
    var rupiah: String { Money(idr: Int64(self)).formatted }
}
