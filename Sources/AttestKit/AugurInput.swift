@preconcurrency import Foundation

// MARK: - Augur Integration

/// The slice of `augur check --json` output that `attest` consumes.
///
/// `augur` emits a top-level `verdict` (`proceed`/`review`/`block`) and a
/// `riskScore` in `0...100`. `attest` maps the risk score to a confidence as
/// `1 - riskScore / 100`, so a low-risk change becomes a high-confidence
/// attestation. Only these two fields are required; everything else is ignored.
public struct AugurVerdict: Sendable, Equatable {
    /// The verdict augur assigned, if it parsed to a known value.
    public let verdict: Verdict?
    /// Confidence in `0...1`, derived from augur's `riskScore`.
    public let confidence: Double

    public init(verdict: Verdict?, confidence: Double) {
        self.verdict = verdict
        self.confidence = max(0, min(1, confidence))
    }

    /// Parses augur JSON from raw bytes.
    ///
    /// - Throws: `AttestError.malformedAugurJSON` if the payload is not an object
    ///   or lacks a numeric `riskScore`.
    public static func parse(_ data: Data) throws -> AugurVerdict {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            throw AttestError.malformedAugurJSON("expected a JSON object")
        }
        guard let risk = (dictionary["riskScore"] as? NSNumber)?.doubleValue else {
            throw AttestError.malformedAugurJSON("missing numeric 'riskScore'")
        }
        let verdict: Verdict?
        if let raw = dictionary["verdict"] as? String {
            verdict = Verdict(rawValue: raw)
        } else {
            verdict = nil
        }
        return AugurVerdict(verdict: verdict, confidence: 1 - risk / 100)
    }

    /// Parses augur JSON from a UTF-8 string.
    public static func parse(_ string: String) throws -> AugurVerdict {
        guard let data = string.data(using: .utf8) else {
            throw AttestError.malformedAugurJSON("input is not valid UTF-8")
        }
        return try parse(data)
    }
}
