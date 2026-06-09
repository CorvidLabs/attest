@preconcurrency import Foundation

// MARK: - Verification Status

/// The cryptographic verification status of a single attestation record in an
/// audit export.
///
/// An audit trail must say not just *what* was attested but *whether each
/// signed record actually verifies*. Unsigned records are valid provenance, so
/// `signed` distinguishes them from signed records, and `verified` reports the
/// outcome of `Ed25519Verifier` over a signed record's canonical bytes (`nil`
/// for unsigned records, where verification does not apply).
public struct VerificationStatus: Sendable, Codable, Equatable {
    /// Whether the record carries a signature and public key.
    public let signed: Bool
    /// For a signed record, whether its embedded signature verifies against its
    /// embedded public key; `nil` for an unsigned record.
    public let verified: Bool?

    public init(signed: Bool, verified: Bool?) {
        self.signed = signed
        self.verified = verified
    }

    enum CodingKeys: String, CodingKey {
        case signed
        case verified
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signed, forKey: .signed)
        try container.encodeIfPresent(verified, forKey: .verified)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.signed = try container.decode(Bool.self, forKey: .signed)
        self.verified = try container.decodeIfPresent(Bool.self, forKey: .verified)
    }

    /// Computes the verification status for an attestation by running
    /// `Ed25519Verifier` over a signed record (and reporting `nil` for unsigned).
    public static func evaluate(_ attestation: Attestation) -> VerificationStatus {
        guard attestation.isSigned else {
            return VerificationStatus(signed: false, verified: nil)
        }
        return VerificationStatus(signed: true, verified: Ed25519Verifier.isValid(attestation))
    }
}

// MARK: - Audit Records

/// One attestation enriched with its computed verification status, as it
/// appears in an audit export.
public struct AuditRecord: Sendable, Codable, Equatable {
    /// The recorded attestation, including any signature pair.
    public let attestation: Attestation
    /// The computed cryptographic verification status of `attestation`.
    public let verification: VerificationStatus

    public init(attestation: Attestation, verification: VerificationStatus) {
        self.attestation = attestation
        self.verification = verification
    }
}

/// Every attestation for a single commit, enriched and (optionally) judged
/// against a policy.
public struct AuditCommit: Sendable, Codable, Equatable {
    /// The commit SHA this group of records is about.
    public let commit: String
    /// The commit's attestations, oldest first, each with a verification status.
    public let records: [AuditRecord]
    /// Whether this commit passes the export's policy; `nil` when no policy was
    /// supplied to the exporter.
    public let policyPassed: Bool?

    public init(commit: String, records: [AuditRecord], policyPassed: Bool?) {
        self.commit = commit
        self.records = records
        self.policyPassed = policyPassed
    }

    enum CodingKeys: String, CodingKey {
        case commit
        case records
        case policyPassed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commit, forKey: .commit)
        try container.encode(records, forKey: .records)
        try container.encodeIfPresent(policyPassed, forKey: .policyPassed)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.commit = try container.decode(String.self, forKey: .commit)
        self.records = try container.decode([AuditRecord].self, forKey: .records)
        self.policyPassed = try container.decodeIfPresent(Bool.self, forKey: .policyPassed)
    }
}

// MARK: - Audit Report

/// The complete provenance trail across a commit range, suitable for compliance
/// archival.
///
/// Distinct from `attest log` (a human/diagnostic listing): an `AuditReport` is
/// a single stable document covering *every* commit in a range (including
/// commits with no attestations, when a policy is applied, so a reviewer sees
/// the full surface) with a computed verification status per record and, when a
/// policy is supplied, a per-commit pass/fail.
public struct AuditReport: Sendable, Codable, Equatable {
    /// The format version of this report document.
    public static let formatVersion = 1

    /// The report format version (stable, integer; bumps on shape changes).
    public let version: Int
    /// Commits in the export, in the order the exporter received them (the order
    /// git returns the range, oldest first).
    public let commits: [AuditCommit]
    /// Total number of commits covered.
    public let commitCount: Int
    /// Total number of attestation records across all commits.
    public let recordCount: Int
    /// Whether a policy was applied to the export.
    public let policyApplied: Bool
    /// When a policy was applied, whether every commit passed it; `nil` otherwise.
    public let allPassed: Bool?

    public init(
        version: Int = AuditReport.formatVersion,
        commits: [AuditCommit],
        policyApplied: Bool,
        allPassed: Bool?
    ) {
        self.version = version
        self.commits = commits
        self.commitCount = commits.count
        self.recordCount = commits.reduce(0) { $0 + $1.records.count }
        self.policyApplied = policyApplied
        self.allPassed = allPassed
    }

    enum CodingKeys: String, CodingKey {
        case version
        case commits
        case commitCount
        case recordCount
        case policyApplied
        case allPassed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(commits, forKey: .commits)
        try container.encode(commitCount, forKey: .commitCount)
        try container.encode(recordCount, forKey: .recordCount)
        try container.encode(policyApplied, forKey: .policyApplied)
        try container.encodeIfPresent(allPassed, forKey: .allPassed)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.commits = try container.decode([AuditCommit].self, forKey: .commits)
        self.commitCount = try container.decode(Int.self, forKey: .commitCount)
        self.recordCount = try container.decode(Int.self, forKey: .recordCount)
        self.policyApplied = try container.decode(Bool.self, forKey: .policyApplied)
        self.allPassed = try container.decodeIfPresent(Bool.self, forKey: .allPassed)
    }

    /// Stable JSON for the report: sorted keys, slashes unescaped, deterministic.
    /// - Parameter pretty: When `true`, emit indented (pretty-printed) JSON.
    public func jsonString(pretty: Bool = true) throws -> String {
        String(decoding: try jsonData(pretty: pretty), as: UTF8.self)
    }

    /// Stable JSON bytes for the report.
    public func jsonData(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }
}

// MARK: - Exporter

/// Aggregates the complete provenance trail across a commit range into a single
/// stable `AuditReport`.
///
/// `Exporter` is a thin, dependency-clean engine type: it reads attestations
/// from an `AttestationStore`, computes each record's verification status with
/// the same `Ed25519Verifier` the rest of the engine uses, and (when given a
/// `Policy`) records each commit's pass/fail. It performs **no** git range
/// walking of its own — the caller resolves the range to an ordered list of
/// commit SHAs (via `NotesStore.commits(inRange:)`, exactly as `verify`/`log`
/// do) and hands it in, so range semantics stay consistent across commands.
///
/// Output is deterministic: commits appear in the order supplied, records in
/// store order (oldest first), and serialization uses sorted keys.
public struct Exporter: Sendable {
    private let store: any AttestationStore

    public init(store: any AttestationStore) {
        self.store = store
    }

    /// Builds an audit report over the given commits.
    ///
    /// - Parameters:
    ///   - commits: The commit SHAs to cover, in the order they should appear
    ///     (typically oldest-first, as `NotesStore.commits(inRange:)` returns).
    ///   - policy: When supplied, each commit is judged against it and the
    ///     report records a per-commit `policyPassed` plus a top-level
    ///     `allPassed`. When `nil`, those fields are omitted.
    ///   - now: The reference time (Unix epoch seconds) for the policy's
    ///     `maxAgeDays` freshness rule, injected so the export is deterministic.
    ///     Defaults to the current epoch and is ignored when no policy is given.
    /// - Returns: A `Codable`, deterministic `AuditReport`.
    public func report(
        commits: [String],
        policy: Policy? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> AuditReport {
        let verifier = policy.map { Verifier(policy: $0) }
        var auditCommits: [AuditCommit] = []
        var allPassed = true

        for commit in commits {
            let attestations = try store.attestations(for: commit)
            let records = attestations.map { attestation in
                AuditRecord(attestation: attestation, verification: VerificationStatus.evaluate(attestation))
            }
            var policyPassed: Bool?
            if let verifier {
                let result = verifier.verify(commits: [(commit: commit, attestations: attestations)], now: now)
                policyPassed = result.passed
                if !result.passed { allPassed = false }
            }
            auditCommits.append(AuditCommit(commit: commit, records: records, policyPassed: policyPassed))
        }

        return AuditReport(
            commits: auditCommits,
            policyApplied: policy != nil,
            allPassed: policy != nil ? allPassed : nil
        )
    }
}
