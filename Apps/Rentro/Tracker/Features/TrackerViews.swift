import SwiftUI
import UIKit
import VisionKit

/// Route gate: pair → consent → home. No coordinates exist before the middle step is accepted.
struct TrackerRootView: View {
    @Environment(TrackerModel.self) private var model

    var body: some View {
        Group {
            if model.pairing == nil { PairView() }
            else if model.needsConsentScreen { NavigationStack { ConsentView(readOnly: false) } }
            else { NavigationStack { TrackerHomeView() } }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .alert("Rentro Tracker", isPresented: .init(get: { model.notice != nil }, set: { if !$0 { model.dismissNotice() } })) {
            Button("OK") { model.dismissNotice() }
        } message: { Text(model.notice ?? "") }
    }
}

// MARK: T01 Pair Device. Figma 44:4000 / 44:4026

struct PairView: View {
    @Environment(TrackerModel.self) private var model
    @AppStorage("deviceRole") private var role = ""
    @State private var manual = false
    @State private var scanning = false
    #if DEBUG
    @Environment(DevPairingCode.self) private var devCode
    #endif

    var body: some View {
        NavigationStack {
            // Scrolls, with the actions pinned below: nothing is truncated at large text sizes.
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    Text("Connect this rental iPhone").font(.title.bold()).foregroundStyle(Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Pairing identifies the unit to Rentro. Location access is requested separately.")
                        .font(.subheadline).foregroundStyle(Color.textSecondary)
                    if let m = model.fleetMessage {
                        Label(m, systemImage: "icloud.slash").font(.footnote).foregroundStyle(Color.textWarning)
                            .accessibilityIdentifier("rentro.tracker.fleet.status")
                    }
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 72, weight: .regular)).foregroundStyle(Color.textAccent)
                        .frame(width: 200, height: 200).background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.r16))
                        .frame(maxWidth: .infinity).padding(.vertical, Space.s24).accessibilityHidden(true)
                    #if DEBUG
                    if let code = devCode.value {
                        Text(PairingCode.display(code)).font(.footnote.monospaced()).foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity).accessibilityIdentifier("rentro.tracker.debug.code")   // dev loopback only
                    }
                    #endif
                    if let e = model.pairError { Text(e).font(.footnote).foregroundStyle(Color.textDanger).accessibilityIdentifier("rentro.tracker.pair.error") }
                }
                .padding(Space.s20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Space.s8) {
                    Button("Scan Pairing Code") { scanning = true }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!QRScannerView.isAvailable || model.busy || !model.canAttemptPairing)
                        .accessibilityIdentifier("rentro.tracker.pair.scan")
                    if !QRScannerView.isAvailable {
                        Text("Scanning isn't available on this device. Enter the code manually.").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    TextLinkButton("Or enter code manually") { manual = true }
                        .disabled(!model.canAttemptPairing)
                        .accessibilityIdentifier("rentro.tracker.pair.manual")
                    TextLinkButton("Use Rentro to run a rental business instead") { role = "" }
                        .accessibilityIdentifier("rentro.role.change")
                }
                .padding(.horizontal, Space.s20).padding(.bottom, Space.s8).background(Color.bgCanvas)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color.bgCanvas.ignoresSafeArea())
            .task { await model.refreshFleetAccess() }
            .sheet(isPresented: $manual) { ManualCodeView() }
            .fullScreenCover(isPresented: $scanning) {
                QRScannerView { payload in scanning = false; Task { await model.pair(code: payload) } }
                    .ignoresSafeArea().overlay(alignment: .topLeading) {
                        Button("Cancel") { scanning = false }.padding().background(.regularMaterial, in: Capsule()).padding()
                    }
            }
        }
    }
}

/// A text-only action with a full 44 pt hit area (the frame lives inside the label, so the whole row is tappable).
struct TextLinkButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    init(_ title: LocalizedStringKey, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color.textAccent)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
    }
}

private struct ManualCodeView: View {
    @Environment(TrackerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s16) {
                RentroFormField(label: "Pairing code") {
                    TextField("K7M2-9QXA", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.body.monospaced())
                        .accessibilityIdentifier("rentro.tracker.pair.code")
                }
                if let e = model.pairError { Text(e).font(.footnote).foregroundStyle(Color.textDanger).accessibilityIdentifier("rentro.tracker.pair.error") }
                Spacer()
                Button(model.busy ? "Pairing…" : "Pair Device") {
                    Task { await model.pair(code: code); if model.pairing != nil { dismiss() } }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.busy || code.isEmpty)
                .accessibilityIdentifier("rentro.tracker.pair.submit")
            }
            .padding(Space.s20)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle("Enter Code").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// VisionKit QR reader. Needs a camera, so it is unavailable in the simulator (manual entry covers it).
struct QRScannerView: UIViewControllerRepresentable {
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let b) in items { if let p = b.payloadStringValue, PairingCode.fromQR(p) != nil { done = true; onCode(p); return } }
        }
    }
}

// MARK: T02 Tracking Consent. Figma 44:4052 / 44:4085

struct ConsentView: View {
    @Environment(TrackerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let readOnly: Bool
    @State private var understood = false

    var body: some View {
        let p = model.pairing
        let business = p?.businessName ?? String(localized: "the rental business"), unit = p?.unitCode ?? String(localized: "this iPhone")
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                Text("How location is used").font(.title.bold()).foregroundStyle(Color.textPrimary).accessibilityAddTraits(.isHeader)
                DisclosureCard(title: "Operational purpose", text: "Show the last reported location of \(unit) to authorized staff of \(business).")
                DisclosureCard(title: "What is shared", text: "Latitude, longitude, accuracy and time of each location update. Updates are best effort and can be delayed or missing.")
                DisclosureCard(title: "Your control", text: "iOS asks for location permission. You can change it in Settings, or stop sharing in this app, at any time.")
                DisclosureCard(title: "Retention", text: "\(business) keeps location for \(ConsentText.retentionDays) days, then it is deleted.")
                DisclosureCard(title: "Questions", text: "Contact \(business) about this agreement.")
            }
            .padding(Space.s20)
        }
        .safeAreaInset(edge: .bottom) {
            if !readOnly {
                VStack(spacing: Space.s8) {
                    // Pinned above the button so the reason Continue is disabled is always on screen.
                    Toggle(isOn: $understood) { Text("I understand how location is collected and used.").foregroundStyle(Color.textOnSoft) }
                        .toggleStyle(CheckToggleStyle()).accessibilityIdentifier("rentro.tracker.consent.understood")
                    Button("Continue to iOS Permission") { model.acceptConsent() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!understood).accessibilityIdentifier("rentro.tracker.consent.continue")
                    TextLinkButton("Not now") { model.declineConsent(); dismiss() }
                        .accessibilityIdentifier("rentro.tracker.consent.decline")
                }
                .padding(.horizontal, Space.s20).padding(.bottom, Space.s8).background(Color.bgCanvas)
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Location Tracking").navigationBarTitleDisplayMode(.inline)
    }
}

private struct DisclosureCard: View {
    let title: LocalizedStringKey, text: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).font(.headline).foregroundStyle(Color.textPrimary)
            Text(text).font(.footnote).foregroundStyle(Color.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .card().accessibilityElement(children: .combine)
    }
}

private struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: Space.s12) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.textSuccess)
                configuration.label.multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(Space.s16).frame(minHeight: 44).background(Color.bgSuccess, in: RoundedRectangle(cornerRadius: Radius.r16))
        }
        .buttonStyle(.plain).accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: T03 Tracker Home. Figma 44:4118 / 44:4150

struct TrackerHomeView: View {
    @Environment(TrackerModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showConsent = false

    var body: some View {
        let p = model.pairing, s = model.status
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                Text("\(p?.unitCode ?? "") · \(p?.deviceModel ?? "")").font(.subheadline).foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: Space.s12) {
                    Text(s.title).font(.title3.weight(.semibold)).foregroundStyle(s == .sharing ? Color.textSuccess : Color.textWarning)
                        .accessibilityIdentifier("rentro.tracker.status")
                    Text(statusDetail(s)).font(.footnote).foregroundStyle(Color.textSecondary)
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        VStack(alignment: .leading, spacing: Space.s8) {
                            line("Last sent", Age.text(from: model.stored.lastUploadAckAt, now: ctx.date))
                            line("Location permission", permissionText(model.auth) + (model.auth == .denied || model.auth == .restricted ? "" : model.isPrecise ? String(localized: " · Precise on") : String(localized: " · Approximate")))
                            line("Updates", String(localized: "Battery-aware, best effort"))
                        }
                    }
                }.card()

                if s == .needsConsent { Button("Review tracking terms") { showConsent = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rentro.tracker.home.review") }
                if s == .permissionRequired {
                    Button("Open iOS Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rentro.tracker.home.settings")
                }
                if model.stored.consent?.isActive == true, model.auth != .denied, model.auth != .restricted {
                    Toggle("Share location", isOn: .init(get: { model.stored.sharingEnabled }, set: { model.setSharing($0) }))
                        .tint(.brandSelected).frame(minHeight: 44).foregroundStyle(Color.textPrimary).card()
                        .accessibilityIdentifier("rentro.tracker.home.share")
                }
                if model.auth == .whenInUse, model.stored.consent?.isActive == true {
                    TextLinkButton("Allow sharing in the background") { model.requestBackgroundSharing() }
                        .accessibilityIdentifier("rentro.tracker.home.always")
                }

                NavigationLink { DiagnosticsView() } label: { navRow("Diagnostics", "Permissions and delivery health") }
                    .accessibilityIdentifier("rentro.tracker.home.diagnostics")
                NavigationLink { ConsentView(readOnly: true) } label: { navRow("Privacy", "Review tracking disclosure") }
                    .accessibilityIdentifier("rentro.tracker.home.privacy")
                NavigationLink { UnpairView() } label: { navRow("Unpair Device", "Stop this tracking agreement") }
                    .accessibilityIdentifier("rentro.tracker.home.unpair")

                Text("This device is paired to \(p?.businessName ?? "").").font(.caption).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity).padding(.top, Space.s16)
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Rentro Tracker")
        .sheet(isPresented: $showConsent) { NavigationStack { ConsentView(readOnly: false) } }
        .onChange(of: model.stored.consent) { _, c in if c?.isActive == true { showConsent = false } }
        .task { model.watchNetwork() }
    }

    private func statusDetail(_ s: TrackerStatus) -> String {
        switch s {
        case .sharing: String(localized: "A recent location reached the business.")
        case .noRecentSignal: String(localized: "No location has reached the business recently. This can happen in the background, offline, or without a GPS fix.")
        case .permissionRequired: String(localized: "Location access is off. The business cannot see this iPhone's location.")
        case .paused: String(localized: "You paused sharing. Nothing is being sent.")
        case .needsConsent: String(localized: "Nothing is collected until you review and accept the tracking terms.")
        case .ended: String(localized: "The sharing period for this rental has ended.")
        case .notPaired: String(localized: "")
        }
    }
    private func permissionText(_ a: OSLocationAuth) -> String {
        switch a { case .always: String(localized: "Always"); case .whenInUse: String(localized: "While using the app"); case .denied: String(localized: "Off"); case .restricted: String(localized: "Restricted"); case .notDetermined: String(localized: "Not asked yet") }
    }
    private func line(_ l: LocalizedStringKey, _ v: String) -> some View {
        HStack { Text(l).foregroundStyle(Color.textSecondary); Spacer(); Text(v).foregroundStyle(Color.textPrimary) }.font(.footnote)
            .accessibilityElement(children: .combine)
    }
    private func navRow(_ t: LocalizedStringKey, _ sub: LocalizedStringKey) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(t).font(.headline).foregroundStyle(Color.textPrimary)
                Text(sub).font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.textSecondary)
        }.card()
    }
}

// MARK: T04 Tracker Diagnostics. Figma 44:4182 / 44:4225

struct DiagnosticsView: View {
    @Environment(TrackerModel.self) private var model

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        ScrollView {
            VStack(spacing: Space.s12) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    VStack(spacing: Space.s12) {
                        row("Location permission", model.auth == .always ? String(localized: "Always") : model.auth == .whenInUse ? String(localized: "While using the app") : String(localized: "Off"),
                            ok: model.auth == .always || model.auth == .whenInUse)
                        row("Background refresh", UIApplication.shared.backgroundRefreshStatus == .available ? String(localized: "Available") : String(localized: "Off or restricted"),
                            ok: UIApplication.shared.backgroundRefreshStatus == .available)
                        // Measuring and uploading fail independently, so they are reported independently (AT-43).
                        row("Last measurement", Age.text(from: model.stored.lastFixAt, now: ctx.date), ok: nil, id: "rentro.tracker.diag.measurement")
                        row("Last upload", model.stored.lastUploadError.map { String(localized: "Failed · \($0)") } ?? Age.text(from: model.stored.lastUploadAckAt, now: ctx.date),
                            ok: model.stored.lastUploadError == nil ? nil : false, id: "rentro.tracker.diag.upload")
                        row("Waiting to upload", model.queuedCount == 1 ? String(localized: "1 location") : String(localized: "\(model.queuedCount) locations"), ok: nil)
                        row("Network", model.isOnline ? String(localized: "Connected") : String(localized: "Offline"), ok: model.isOnline)
                        row("App version", "\(version) (\(build))", ok: nil)
                    }
                }
                Button("Send test location") { model.sendTestLocation() }
                    .buttonStyle(PrimaryButtonStyle()).padding(.top, Space.s8)
                    .disabled(model.status == .needsConsent || model.status == .permissionRequired || model.status == .notPaired)
                    .accessibilityIdentifier("rentro.tracker.diag.test")
                if model.queuedCount > 0 {
                    TextLinkButton("Retry upload") { Task { await model.flush() } }
                        .accessibilityIdentifier("rentro.tracker.diag.retry")
                }
                Text("iOS may delay or pause location in the background to save battery. Contact the rental business if this iPhone keeps showing no recent signal.")
                    .font(.caption).foregroundStyle(Color.textSecondary).padding(.top, Space.s8)
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Tracker Diagnostics").navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, ok: Bool?, id: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(title).font(.headline).foregroundStyle(Color.textPrimary)
                Text(value).font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if let ok { Image(systemName: ok ? "checkmark" : "exclamationmark.triangle").foregroundStyle(ok ? Color.textAccent : Color.textWarning) }
        }
        .card().accessibilityElement(children: .combine).accessibilityIdentifier(id ?? "")
    }
}

// MARK: T05 Unpair Tracker. Figma 44:4268 / 44:4293

struct UnpairView: View {
    @Environment(TrackerModel.self) private var model
    @State private var confirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                Text("Stop this tracking agreement?").font(.title.bold()).foregroundStyle(Color.textPrimary).accessibilityAddTraits(.isHeader)
                Text("Unpairing stops Rentro from associating future location updates with this rental unit. Data the business already holds follows its retention policy.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary)
                Text("Use this when the rental device is being removed or reconfigured. Pairing again needs a new code and a new agreement.")
                    .font(.footnote).foregroundStyle(Color.textDanger).padding(Space.s16)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.bgDanger, in: RoundedRectangle(cornerRadius: Radius.r16))
            }
            .padding(Space.s20)
        }
        .safeAreaInset(edge: .bottom) {
            Button { confirm = true } label: {
                Text("Unpair Device").font(.headline).foregroundStyle(Color.textDanger)
                    .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                    .background(Color.bgDanger, in: RoundedRectangle(cornerRadius: Radius.r16))
            }
            .buttonStyle(.plain)                      // no system overlay: what is drawn is exactly the token colours
            .padding(.horizontal, Space.s20).padding(.bottom, Space.s8).background(Color.bgCanvas)
            .accessibilityIdentifier("rentro.tracker.unpair.button")
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Unpair Device").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Unpair this iPhone?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Unpair Device", role: .destructive) { Task { await model.unpair() } }
        } message: { Text("Location sharing stops and queued locations are deleted.") }
    }
}
