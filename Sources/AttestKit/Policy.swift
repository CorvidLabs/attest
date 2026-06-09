@preconcurrency import Foundation

// MARK: - Policy

/// A declarative gate over the attestations recorded for a commit.
///
/// Loaded from a JSON file (`.attest.json`) with Foundation's `JSONDecoder`
/// (zero extra dependencies). Every field is optional with a permissive default,
/// so an empty `{}` policy passes everything and the tool is usable with no
/// configuration.
public struct Policy: Sendable, Codable, Equatable {
    /// Require at least one attestation per commit. Defaults to `true`.
    public var requireAttestation: Bool
    /// Require `humanApproved == true` when the recorded verdict is at least this
    /// level. `nil` disables the rule.
    public var requireHumanApprovalWhenVerdictAtLeast: Verdict?
    /// Require at least one attestation with `testsPassed == true`.
    public var requireTestsPassed: Bool
    /// Require at least one *valid signed* attestation.
    public var requireSignature: Bool
    /// Require the strongest attestation's `confidence` to meet this floor (0...1).
    public var minimumConfidence: Double?

    public init(
        requireAttestation: Bool = true,
        requireHumanApprovalWhenVerdictAtLeast: Verdict? = nil,
        requireTestsPassed: Bool = false,
        requireSignature: Bool = false,
        minimumConfidence: Double? = nil
    ) {
        self.requireAttestation = requireAttestation
        self.requireHumanApprovalWhenVerdictAtLeast = requireHumanApprovalWhenVerdictAtLeast
        self.requireTestsPassed = requireTestsPassed
        self.requireSignature = requireSignature
        self.minimumConfidence = minimumConfidence
    }

    enum CodingKeys: String, CodingKey {
        case requireAttestation
        case requireHumanApprovalWhenVerdictAtLeast
        case requireTestsPassed
        case requireSignature
        case minimumConfidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requireAttestation = try container.decodeIfPresent(Bool.self, forKey: .requireAttestation) ?? true
        self.requireHumanApprovalWhenVerdictAtLeast =
            try container.decodeIfPresent(Verdict.self, forKey: .requireHumanApprovalWhenVerdictAtLeast)
        self.requireTestsPassed = try container.decodeIfPresent(Bool.self, forKey: .requireTestsPassed) ?? false
        self.requireSignature = try container.decodeIfPresent(Bool.self, forKey: .requireSignature) ?? false
        self.minimumConfidence = try container.decodeIfPresent(Double.self, forKey: .minimumConfidence)
    }

    /// The default policy: require an attestation, nothing more.
    public static let `default` = Policy()

    /// Loads a policy from a JSON file at `path`.
    public static func load(fromFile path: String) throws -> Policy {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(Policy.self, from: data)
    }
}

// MARK: - Violations

/// One reason a commit failed policy.
public struct Violation: Sendable, Codable, Equatable {
    public let commit: String
    public let rule: String
    public let detail: String

    public init(commit: String, rule: String, detail: String) {
        self.commit = commit
        self.rule = rule
        self.detail = detail
    }
}

/// The outcome of checking a set of commits against a policy.
public struct VerificationResult: Sendable, Codable, Equatable {
    public let passed: Bool
    public let checkedCommits: Int
    public let violations: [Violation]

    public init(passed: Bool, checkedCommits: Int, violations: [Violation]) {
        self.passed = passed
        self.checkedCommits = checkedCommits
        self.violations = violations
    }

    /// Stable, agent-friendly JSON.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

// MARK: - Verifier

/// Checks commits' attestations against a `Policy`.
public struct Verifier: Sendable {
    private let policy: Policy

    public init(policy: Policy) {
        self.policy = policy
    }

    /// Evaluates `policy` against the given commits, collecting all violations.
    ///
    /// - Parameter commits: An ordered map of commit SHA to its attestations.
    /// - Returns: A `VerificationResult` that `passed` only when there are no
    ///   violations across all commits.
    public func verify(commits: [(commit: String, attestations: [Attestation])]) -> VerificationResult {
        var violations: [Violation] = []
        for entry in commits {
            violations.append(contentsOf: evaluate(commit: entry.commit, attestations: entry.attestations))
        }
        return VerificationResult(
            passed: violations.isEmpty,
            checkedCommits: commits.count,
            violations: violations
        )
    }

    // MARK: - Rules

    private func evaluate(commit: String, attestations: [Attestation]) -> [Violation] {
        var violations: [Violation] = []

        if attestations.isEmpty {
            if policy.requireAttestation {
                violations.append(Violation(
                    commit: commit,
                    rule: "requireAttestation",
                    detail: "commit has no attestations"
                ))
            }
            // With no attestations, no further per-record rule can be satisfied,
            // but only the rules that demand evidence should fire.
            if policy.requireTestsPassed {
                violations.append(Violation(commit: commit, rule: "requireTestsPassed", detail: "no attestation reports passing tests"))
            }
            if policy.requireSignature {
                violations.append(Violation(commit: commit, rule: "requireSignature", detail: "no valid signed attestation"))
            }
            if let floor = policy.minimumConfidence {
                violations.append(Violation(commit: commit, rule: "minimumConfidence", detail: "no attestation meets confidence floor \(floor)"))
            }
            return violations
        }

        if policy.requireTestsPassed, !attestations.contains(where: { $0.testsPassed }) {
            violations.append(Violation(commit: commit, rule: "requireTestsPassed", detail: "no attestation reports passing tests"))
        }

        if policy.requireSignature, !attestations.contains(where: { Ed25519Verifier.isValid($0) }) {
            violations.append(Violation(commit: commit, rule: "requireSignature", detail: "no valid signed attestation"))
        }

        if let floor = policy.minimumConfidence {
            let best = attestations.map(\.confidence).max() ?? 0
            if best < floor {
                violations.append(Violation(
                    commit: commit,
                    rule: "minimumConfidence",
                    detail: "highest confidence \(best) is below floor \(floor)"
                ))
            }
        }

        if let threshold = policy.requireHumanApprovalWhenVerdictAtLeast {
            let triggering = attestations.filter { ($0.verdict ?? .proceed) >= threshold }
            if !triggering.isEmpty, !triggering.contains(where: { $0.humanApproved }) {
                violations.append(Violation(
                    commit: commit,
                    rule: "requireHumanApprovalWhenVerdictAtLeast",
                    detail: "verdict is at least \(threshold.rawValue) but no attestation is human-approved"
                ))
            }
        }

        return violations
    }
}
