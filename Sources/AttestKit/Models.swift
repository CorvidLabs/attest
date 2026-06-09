@preconcurrency import Foundation

// MARK: - Verdict

/// The action recorded for a change, mirroring `augur`'s verdict vocabulary.
///
/// `attest` records the verdict that a reviewer (human or agent) assigned; it
/// does not compute one. The ordering lets a policy compare "at least review".
public enum Verdict: String, Sendable, Codable, CaseIterable, Comparable {
    /// Low risk: safe for an agent to proceed / a human to fast-track.
    case proceed
    /// Elevated risk: a human should review.
    case review
    /// High risk: should not merge without deliberate human sign-off.
    case block

    private var order: Int {
        switch self {
        case .proceed: return 0
        case .review: return 1
        case .block: return 2
        }
    }

    public static func < (lhs: Verdict, rhs: Verdict) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Attestation

/// A signed (or unsigned) provenance record asserting who or what reviewed a
/// change and at what confidence.
///
/// An attestation is keyed to a git commit SHA and stored portably in git notes.
/// Signing is optional: an unsigned attestation is still a valid record, so the
/// tool works with zero setup. When signed, `signature` covers the canonical
/// bytes produced by `canonicalData()`, which deliberately excludes the
/// `signature` field itself.
public struct Attestation: Sendable, Codable, Equatable {
    /// The git commit SHA this attestation is about.
    public let commit: String
    /// Who or what reviewed, e.g. `agent:claude` or `human:leif`.
    public let reviewer: String
    /// Reviewer confidence in the change, clamped to `0...1`.
    public let confidence: Double
    /// The recorded verdict, if any.
    public let verdict: Verdict?
    /// Whether the change's tests passed.
    public let testsPassed: Bool
    /// Whether a human explicitly approved the change.
    public let humanApproved: Bool
    /// Unix epoch seconds when the attestation was made.
    public let timestamp: Int
    /// An optional free-text note.
    public let note: String?
    /// Base64 Ed25519 signature over `canonicalData()`, if signed.
    public let signature: String?
    /// Base64 Ed25519 public key of the signer, if signed.
    public let publicKey: String?

    public init(
        commit: String,
        reviewer: String,
        confidence: Double,
        verdict: Verdict? = nil,
        testsPassed: Bool = false,
        humanApproved: Bool = false,
        timestamp: Int,
        note: String? = nil,
        signature: String? = nil,
        publicKey: String? = nil
    ) {
        self.commit = commit
        self.reviewer = reviewer
        self.confidence = max(0, min(1, confidence))
        self.verdict = verdict
        self.testsPassed = testsPassed
        self.humanApproved = humanApproved
        self.timestamp = timestamp
        self.note = note
        self.signature = signature
        self.publicKey = publicKey
    }

    /// Whether this attestation carries a signature and public key.
    public var isSigned: Bool {
        signature != nil && publicKey != nil
    }

    /// Returns a copy with the signature and public key attached.
    public func attaching(signature: String, publicKey: String) -> Attestation {
        Attestation(
            commit: commit,
            reviewer: reviewer,
            confidence: confidence,
            verdict: verdict,
            testsPassed: testsPassed,
            humanApproved: humanApproved,
            timestamp: timestamp,
            note: note,
            signature: signature,
            publicKey: publicKey
        )
    }
}

// MARK: - Errors

public enum AttestError: Error, LocalizedError, Sendable, Equatable {
    case notARepository(String)
    case git(command: String, status: Int32)
    case noAttestations(commit: String)
    case malformedRecord(String)
    case keyNotFound(String)
    case keyAlreadyExists(String)
    case invalidKey(String)
    case signatureMissing
    case verificationFailed(reason: String)
    case malformedAugurJSON(String)

    public var errorDescription: String? {
        switch self {
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .git(let command, let status):
            return "git \(command) failed (exit \(status))"
        case .noAttestations(let commit):
            return "No attestations found for \(commit)."
        case .malformedRecord(let detail):
            return "Malformed attestation record: \(detail)"
        case .keyNotFound(let path):
            return "No signing key at \(path). Run `attest keygen` first."
        case .keyAlreadyExists(let path):
            return "A signing key already exists at \(path). Use --force to overwrite."
        case .invalidKey(let detail):
            return "Invalid signing key: \(detail)"
        case .signatureMissing:
            return "Attestation is not signed."
        case .verificationFailed(let reason):
            return "Signature verification failed: \(reason)"
        case .malformedAugurJSON(let detail):
            return "Could not parse augur JSON: \(detail)"
        }
    }
}
