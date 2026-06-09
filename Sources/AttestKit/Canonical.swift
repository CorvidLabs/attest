@preconcurrency import Foundation

// MARK: - Canonical Serialization

extension Attestation {
    /// The deterministic byte representation that is signed and verified.
    ///
    /// The canonical form is JSON with sorted keys and slashes left unescaped,
    /// and it deliberately **excludes** the `signature` and `publicKey` fields so
    /// that attaching a signature does not change the bytes being signed. Two
    /// attestations with identical content always produce identical bytes,
    /// regardless of field declaration order or platform.
    public func canonicalData() throws -> Data {
        let payload = CanonicalPayload(self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    /// The canonical serialization as a UTF-8 string.
    public func canonicalString() throws -> String {
        String(decoding: try canonicalData(), as: UTF8.self)
    }
}

/// The signed subset of an `Attestation`: everything except the signature pair.
///
/// `Optional` fields are encoded only when present (`encodeIfPresent`) so the
/// canonical bytes stay compact and stable.
private struct CanonicalPayload: Encodable {
    let commit: String
    let confidence: Double
    let humanApproved: Bool
    let note: String?
    let reviewer: String
    let testsPassed: Bool
    let timestamp: Int
    let verdict: Verdict?

    init(_ attestation: Attestation) {
        self.commit = attestation.commit
        self.confidence = attestation.confidence
        self.humanApproved = attestation.humanApproved
        self.note = attestation.note
        self.reviewer = attestation.reviewer
        self.testsPassed = attestation.testsPassed
        self.timestamp = attestation.timestamp
        self.verdict = attestation.verdict
    }

    enum CodingKeys: String, CodingKey {
        case commit, confidence, humanApproved, note, reviewer, testsPassed, timestamp, verdict
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commit, forKey: .commit)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(humanApproved, forKey: .humanApproved)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(reviewer, forKey: .reviewer)
        try container.encode(testsPassed, forKey: .testsPassed)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(verdict, forKey: .verdict)
    }
}

// MARK: - JSON

extension Attestation {
    /// Stable, agent-friendly JSON of the full record (including any signature).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}
