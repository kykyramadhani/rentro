import AuthenticationServices
import SwiftUI

/// Keychain slot for the stable Apple user identifier (PRD 8.3). Closures so tests can swap it.
@MainActor struct SessionStorage {
    var read: () -> String?
    var write: (String) -> Void
    var clear: () -> Void

    static let keychain: SessionStorage = {
        let slot = KeychainSlot(service: "com.rentro.admin.session", account: "appleUserID")
        return SessionStorage(read: slot.read, write: slot.write, clear: slot.clear)
    }()
}

@MainActor @Observable
final class AuthStore {
    enum State: Equatable { case resolving, signedOut, signedIn(userID: String) }

    private(set) var state: State = .resolving
    private(set) var errorMessage: String?
    private let storage: SessionStorage
    private let credentialState: (String) async -> ASAuthorizationAppleIDProvider.CredentialState

    init(storage: SessionStorage = .keychain,
         credentialState: @escaping (String) async -> ASAuthorizationAppleIDProvider.CredentialState = AuthStore.appleCredentialState) {
        self.storage = storage
        self.credentialState = credentialState
    }

    /// Default check; offline/errored lookups trust the Keychain so local-first use keeps working.
    // ponytail: an offline revoked account stays signed in until the next successful check.
    static func appleCredentialState(_ userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { c in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { s, error in
                c.resume(returning: error == nil ? s : .authorized)
            }
        }
    }

    /// Cold start / foreground: nothing protected shows until this resolves (PRD S00, S01).
    func restore() async {
        guard let id = storage.read() else { state = .signedOut; return }
        switch await credentialState(id) {
        case .authorized: state = .signedIn(userID: id)
        default: storage.clear(); state = .signedOut     // .revoked, .notFound, .transferred
        }
    }

    func didAuthorize(userID: String) {
        storage.write(userID)
        errorMessage = nil
        state = .signedIn(userID: userID)
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return fail() }
            didAuthorize(userID: cred.user)
        case .failure(let error):
            // Cancelling is not a failure. Never log tokens or codes (PRD 8.3).
            if (error as? ASAuthorizationError)?.code == .canceled { errorMessage = nil } else { fail() }
        }
    }

    func signOut() {
        storage.clear()
        errorMessage = nil
        state = .signedOut
    }

    private func fail() { errorMessage = String(localized: "Sign in with Apple didn't complete. Try again.") }
}
