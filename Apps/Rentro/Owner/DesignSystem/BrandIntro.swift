import SwiftUI

/// Round "R" monogram (Figma 58:4342 / 58:4345 idea; the app icon itself comes from the asset catalog).
struct BrandMonogram: View {
    var size: CGFloat = 96
    var body: some View {
        Text("R").font(.system(size: size * 0.62, weight: .heavy, design: .rounded)).foregroundStyle(Color.textAccent)
            .frame(width: size, height: size).background(Color.bgSubtle, in: Circle())
            .accessibilityHidden(true)
    }
}

/// B03: when the optional first-run intro may play. Never for returning users, never with Reduce Motion (static content at once).
enum BrandIntroPolicy {
    static let baseDuration: Duration = .milliseconds(1450)   // Figma prototype timing (demo value); the intro never delays routing
    /// UI tests hold it longer (`-brandIntroHold`) so they can observe it; tapping still skips.
    static var duration: Duration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-brandIntroHold") { return .seconds(8) }
        #endif
        return baseDuration
    }
    static func shouldPlay(seen: Bool, reduceMotion: Bool) -> Bool { !seen && !reduceMotion }
}

/// B03 Optional in-app brand intro (Figma 58:4320 / 58:4332): halo, monogram, wordmark, tagline. Tap anywhere to skip.
struct AnimatedBrandIntro: View {
    let onFinish: () -> Void
    @State private var halo = false
    @State private var monogram = false
    @State private var wordmark = false
    @State private var tagline = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.bgCanvas.ignoresSafeArea()
            VStack(spacing: Space.s20) {
                ZStack {
                    Circle().fill(Color.textAccent.opacity(0.10)).frame(width: 168, height: 168).opacity(halo ? 1 : 0)
                    BrandMonogram().scaleEffect(monogram ? 1 : 0.6).opacity(monogram ? 1 : 0)
                }
                RentroWordmark().scaleEffect(wordmark ? 1 : 0.9).opacity(wordmark ? 1 : 0)
                Text("Manage rentals and devices with less friction.").font(.subheadline).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center).opacity(tagline ? 1 : 0)
            }
            .padding(Space.s24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rentro. Manage rentals and devices with less friction.")
        .accessibilityHint("Double tap to skip")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("rentro.intro")
        .task {
            withAnimation(.easeOut(duration: 0.45)) { halo = true }
            withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(0.1)) { monogram = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) { wordmark = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.75)) { tagline = true }
            try? await Task.sleep(for: BrandIntroPolicy.duration)
            if !Task.isCancelled { finish() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
