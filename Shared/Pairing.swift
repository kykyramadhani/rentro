import CryptoKit
import Foundation

/// One-time pairing codes (PRD T01): short, unambiguous, stored only as a hash, expire fast.
enum PairingCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no I, O, 0, 1
    static let length = 8
    static let lifetime: TimeInterval = 60     // owner decision: 1 minute; the code is shown, scanned and gone

    static func generate<G: RandomNumberGenerator>(using g: inout G) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &g)! })
    }
    static func generate() -> String { var g = SystemRandomNumberGenerator(); return generate(using: &g) }

    /// "K7M2-9QXA" for display and QR payloads.
    static func display(_ raw: String) -> String { "\(raw.prefix(4))-\(raw.dropFirst(4))" }

    /// Accepts "k7m2 9qxa", "K7M2-9QXA"; nil when the shape is wrong, so typos never reach the transport.
    static func normalize(_ input: String) -> String? {
        let s = input.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        return s.count == length && s.allSatisfy(alphabet.contains) ? s : nil
    }

    /// QR payload: "rentro://pair?code=K7M2-9QXA" or a bare code. Anything else is not ours.
    static func fromQR(_ payload: String) -> String? {
        if let url = URL(string: payload), url.scheme == "rentro", url.host == "pair",
           let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
            return normalize(code)
        }
        return normalize(payload)
    }
    static func qrPayload(_ raw: String) -> String { "rentro://pair?code=\(display(raw))" }

    static func hash(_ normalized: String) -> String { SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined() }
}
