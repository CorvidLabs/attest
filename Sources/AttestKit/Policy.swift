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
    /// Require at least one human-approved attestation on a commit when any of its
    /// attestations carries a verdict at or above this level. The human sign-off can
    /// be a *separate* attestation (it need not restate the verdict). `nil` disables
    /// the rule.
    public var requireHumanApprovalWhenVerdictAtLeast: Verdict?
    /// Require at least one attestation with `testsPassed == true`.
    public var requireTestsPassed: Bool
    /// Require at least one *valid signed* attestation.
    public var requireSignature: Bool
    /// Require the strongest attestation's `confidence` to meet this floor (0...1).
    public var minimumConfidence: Double?
    /// Restrict the reviewers permitted to attest on a commit. When non-`nil`, every
    /// attestation on the commit must have a `reviewer` that matches one of the listed
    /// patterns. Matching is, per pattern: an **exact** match against the full reviewer
    /// string, *or* — when the pattern ends with `:` (e.g. `"human:"`) — a **prefix**
    /// match on the role segment, so `"human:"` allows any `human:*` reviewer. A `nil` or
    /// empty list disables the rule.
    public var allowedReviewers: [String]?
    /// Require at least one *valid signed* attestation on a commit when any of its
    /// attestations carries a verdict at or above this level. The signature can live on a
    /// *separate* attestation (it need not be the one carrying the high verdict). `nil`
    /// disables the rule.
    public var requireSignatureWhenVerdictAtLeast: Verdict?
    /// Require at least one attestation with `testsPassed == true` on a commit when any of
    /// its attestations carries a verdict at or above this level. The passing-tests record
    /// can be a *separate* attestation. `nil` disables the rule.
    public var requireTestsPassedWhenVerdictAtLeast: Verdict?
    /// A list of trusted base64 Ed25519 public keys. When non-`nil` and non-empty, every
    /// *signed* attestation on a commit must verify **and** carry a `publicKey` present in this
    /// list; a signed attestation whose key is untrusted (or whose signature fails) fails the
    /// commit. Unsigned attestations are not forced to sign by this rule — they are governed by
    /// the separate `requireSignature*` rules — so `trustedKeys` constrains *which keys count as
    /// trusted*, not whether signing is required. A `nil` or empty list disables the rule.
    public var trustedKeys: [String]?
    /// Bind specific reviewers to specific base64 Ed25519 public keys. When non-`nil` and
    /// non-empty, any attestation whose `reviewer` is a key in this map must be *signed* with the
    /// pinned public key **and** the signature must verify; an attestation claiming a pinned
    /// reviewer but signed with a different key (or left unsigned) fails the commit. Reviewers
    /// absent from the map are unaffected. This is what stops `reviewer: human:leif` spoofing. A
    /// `nil` or empty map disables the rule.
    public var signerPinning: [String: String]?
    /// Require a commit's attestations to be *recent*. When set, the commit must carry at least one
    /// attestation whose `timestamp` is within `maxAgeDays` of a reference "now" (the days are
    /// computed from epoch seconds against an injected clock, so verification is deterministic and
    /// testable). A commit whose newest attestation is older than `maxAgeDays`, or which has no
    /// attestations at all, fails this rule. The reference time is supplied to
    /// `Verifier.verify(commits:now:)` (the CLI defaults it to the current epoch). `nil` disables
    /// the rule.
    public var maxAgeDays: Int?

    public init(
        requireAttestation: Bool = true,
        requireHumanApprovalWhenVerdictAtLeast: Verdict? = nil,
        requireTestsPassed: Bool = false,
        requireSignature: Bool = false,
        minimumConfidence: Double? = nil,
        allowedReviewers: [String]? = nil,
        requireSignatureWhenVerdictAtLeast: Verdict? = nil,
        requireTestsPassedWhenVerdictAtLeast: Verdict? = nil,
        trustedKeys: [String]? = nil,
        signerPinning: [String: String]? = nil,
        maxAgeDays: Int? = nil
    ) {
        self.requireAttestation = requireAttestation
        self.requireHumanApprovalWhenVerdictAtLeast = requireHumanApprovalWhenVerdictAtLeast
        self.requireTestsPassed = requireTestsPassed
        self.requireSignature = requireSignature
        self.minimumConfidence = minimumConfidence
        self.allowedReviewers = allowedReviewers
        self.requireSignatureWhenVerdictAtLeast = requireSignatureWhenVerdictAtLeast
        self.requireTestsPassedWhenVerdictAtLeast = requireTestsPassedWhenVerdictAtLeast
        self.trustedKeys = trustedKeys
        self.signerPinning = signerPinning
        self.maxAgeDays = maxAgeDays
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case requireAttestation
        case requireHumanApprovalWhenVerdictAtLeast
        case requireTestsPassed
        case requireSignature
        case minimumConfidence
        case allowedReviewers
        case requireSignatureWhenVerdictAtLeast
        case requireTestsPassedWhenVerdictAtLeast
        case trustedKeys
        case signerPinning
        case maxAgeDays
    }

    /// A pass-through key type used to read every key present in the JSON, so
    /// unknown (e.g. misspelled) rule names can be rejected instead of silently
    /// ignored — a misspelled rule is a rule that is off.
    private struct AnyPolicyKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    public init(from decoder: any Decoder) throws {
        // Strict decoding: reject unknown keys before reading any rule, naming
        // the offenders and listing the valid rule names.
        let rawContainer = try decoder.container(keyedBy: AnyPolicyKey.self)
        let validKeys = CodingKeys.allCases.map(\.stringValue)
        let unknownKeys = rawContainer.allKeys
            .map(\.stringValue)
            .filter { !validKeys.contains($0) }
            .sorted()
        guard unknownKeys.isEmpty else {
            throw AttestError.unknownPolicyKeys(keys: unknownKeys, validKeys: validKeys.sorted())
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requireAttestation = try container.decodeIfPresent(Bool.self, forKey: .requireAttestation) ?? true
        self.requireHumanApprovalWhenVerdictAtLeast =
            try container.decodeIfPresent(Verdict.self, forKey: .requireHumanApprovalWhenVerdictAtLeast)
        self.requireTestsPassed = try container.decodeIfPresent(Bool.self, forKey: .requireTestsPassed) ?? false
        self.requireSignature = try container.decodeIfPresent(Bool.self, forKey: .requireSignature) ?? false
        self.minimumConfidence = try container.decodeIfPresent(Double.self, forKey: .minimumConfidence)
        self.allowedReviewers = try container.decodeIfPresent([String].self, forKey: .allowedReviewers)
        self.requireSignatureWhenVerdictAtLeast =
            try container.decodeIfPresent(Verdict.self, forKey: .requireSignatureWhenVerdictAtLeast)
        self.requireTestsPassedWhenVerdictAtLeast =
            try container.decodeIfPresent(Verdict.self, forKey: .requireTestsPassedWhenVerdictAtLeast)
        self.trustedKeys = try container.decodeIfPresent([String].self, forKey: .trustedKeys)
        self.signerPinning = try container.decodeIfPresent([String: String].self, forKey: .signerPinning)
        self.maxAgeDays = try container.decodeIfPresent(Int.self, forKey: .maxAgeDays)
    }

    /// The default policy: require an attestation, nothing more.
    public static let `default` = Policy()

    /// Loads a policy from a JSON file at `path`.
    ///
    /// Decoding is strict: a missing file throws `AttestError.policyNotFound`,
    /// an unknown (misspelled) rule name throws `AttestError.unknownPolicyKeys`,
    /// and any other decoding problem is rendered as a human-readable
    /// `AttestError.malformedPolicy` (file, problem, and key path / position
    /// where available) rather than a raw Swift `DecodingError`.
    public static func load(fromFile path: String) throws -> Policy {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AttestError.policyNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        do {
            return try JSONDecoder().decode(Policy.self, from: data)
        } catch let error as AttestError {
            throw error
        } catch let error as DecodingError {
            throw AttestError.malformedPolicy(file: path, detail: Self.describe(error))
        }
    }

    /// Renders a `DecodingError` as a short human-readable problem description.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            // Foundation puts the useful position info ("around line N,
            // column M") in the underlying NSError's debug description.
            if let underlying = context.underlyingError as NSError?,
               let debug = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
                return "not valid JSON (\(debug))"
            }
            return "not valid JSON (\(context.debugDescription))"
        case .keyNotFound(let key, _):
            return "missing required key '\(key.stringValue)'"
        case .typeMismatch(_, let context):
            return "wrong value type at '\(keyPath(of: context))' (\(context.debugDescription))"
        case .valueNotFound(_, let context):
            return "missing value at '\(keyPath(of: context))' (\(context.debugDescription))"
        @unknown default:
            return "could not be decoded"
        }
    }

    /// The dotted key path of a decoding context, e.g. `signerPinning.human:leif`.
    private static func keyPath(of context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "(top level)" : path
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

    /// The number of seconds in one day, used to compute attestation age.
    private static let secondsPerDay = 86_400

    /// Evaluates `policy` against the given commits, collecting all violations.
    ///
    /// - Parameters:
    ///   - commits: An ordered map of commit SHA to its attestations.
    ///   - now: The reference time, in Unix epoch seconds, used by the freshness
    ///     rule (`maxAgeDays`). It is injected rather than read from the system
    ///     clock so verification is deterministic and testable; the CLI defaults
    ///     it to the current epoch. Rules other than `maxAgeDays` ignore it.
    /// - Returns: A `VerificationResult` that `passed` only when there are no
    ///   violations across all commits.
    public func verify(
        commits: [(commit: String, attestations: [Attestation])],
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> VerificationResult {
        var violations: [Violation] = []
        for entry in commits {
            violations.append(contentsOf: evaluate(commit: entry.commit, attestations: entry.attestations, now: now))
        }
        return VerificationResult(
            passed: violations.isEmpty,
            checkedCommits: commits.count,
            violations: violations
        )
    }

    // MARK: - Rules

    private func evaluate(commit: String, attestations rawAttestations: [Attestation], now: Int) -> [Violation] {
        var violations: [Violation] = []

        // Commit binding: an attestation is evidence only for the commit it names.
        // The `commit` parameter is the git-note key the records are stored under;
        // discard any record whose inner `commit` does not equal that key before any
        // rule runs. This stops a legitimately signed attestation from being copied
        // verbatim onto another commit (its signature still validates over its own
        // unchanged bytes, but it does not name this commit, so it is not evidence
        // for it). After filtering, the remaining records are the only ones the rules
        // see, so `requireAttestation` correctly fails a commit whose only record was
        // a transplanted one.
        let attestations = rawAttestations.filter { $0.commit == commit }

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
            if let maxAge = policy.maxAgeDays {
                violations.append(Violation(
                    commit: commit,
                    rule: "maxAgeDays",
                    detail: "no attestation exists to satisfy maxAgeDays=\(maxAge)"
                ))
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
            // The rule triggers when *any* attestation carries a verdict at or above the
            // threshold. It is satisfied by a human sign-off recorded *anywhere* on the
            // commit — a human typically files a separate `humanApproved` attestation
            // rather than restating the verdict — so we check all attestations, not just
            // the one carrying the high verdict.
            let triggered = attestations.contains { ($0.verdict ?? .proceed) >= threshold }
            let humanApproved = attestations.contains { $0.humanApproved }
            if triggered, !humanApproved {
                violations.append(Violation(
                    commit: commit,
                    rule: "requireHumanApprovalWhenVerdictAtLeast",
                    detail: "verdict is at least \(threshold.rawValue) on this commit but no attestation is human-approved"
                ))
            }
        }

        if let allowed = policy.allowedReviewers, !allowed.isEmpty {
            for attestation in attestations where !Verifier.reviewerIsAllowed(attestation.reviewer, patterns: allowed) {
                violations.append(Violation(
                    commit: commit,
                    rule: "allowedReviewers",
                    detail: "reviewer \(attestation.reviewer) is not in the allow-list \(allowed)"
                ))
            }
        }

        if let threshold = policy.requireSignatureWhenVerdictAtLeast {
            // Mirrors `requireHumanApprovalWhenVerdictAtLeast`: triggers when any attestation
            // on the commit carries a verdict at or above the threshold, and is satisfied by
            // any *valid signed* attestation anywhere on the commit (not necessarily the one
            // carrying the high verdict). Reuses the existing `Ed25519Verifier`.
            let triggered = attestations.contains { ($0.verdict ?? .proceed) >= threshold }
            let signed = attestations.contains { Ed25519Verifier.isValid($0) }
            if triggered, !signed {
                violations.append(Violation(
                    commit: commit,
                    rule: "requireSignatureWhenVerdictAtLeast",
                    detail: "verdict is at least \(threshold.rawValue) on this commit but no attestation is validly signed"
                ))
            }
        }

        if let threshold = policy.requireTestsPassedWhenVerdictAtLeast {
            // Conditional form of `requireTestsPassed`: triggers when any attestation on the
            // commit carries a verdict at or above the threshold, and is satisfied by any
            // attestation with `testsPassed == true` anywhere on the commit.
            let triggered = attestations.contains { ($0.verdict ?? .proceed) >= threshold }
            let testsPassed = attestations.contains { $0.testsPassed }
            if triggered, !testsPassed {
                violations.append(Violation(
                    commit: commit,
                    rule: "requireTestsPassedWhenVerdictAtLeast",
                    detail: "verdict is at least \(threshold.rawValue) on this commit but no attestation reports passing tests"
                ))
            }
        }

        if let trusted = policy.trustedKeys, !trusted.isEmpty {
            // Constrain *which keys count as trusted* for any signed attestation. An unsigned
            // record is untouched here (it is governed by the separate `requireSignature*`
            // rules). A record that carries a signature must verify against its embedded key
            // *and* that key must be in the trusted set; a signed record whose key is untrusted
            // or whose signature fails is rejected. Reuses the existing `Ed25519Verifier`.
            for attestation in attestations where attestation.isSigned {
                if !Ed25519Verifier.isValid(attestation) {
                    violations.append(Violation(
                        commit: commit,
                        rule: "trustedKeys",
                        detail: "signed attestation by \(attestation.reviewer) does not validate"
                    ))
                } else if let key = attestation.publicKey, !trusted.contains(key) {
                    violations.append(Violation(
                        commit: commit,
                        rule: "trustedKeys",
                        detail: "signed attestation by \(attestation.reviewer) uses an untrusted public key"
                    ))
                }
            }
        }

        if let pinning = policy.signerPinning, !pinning.isEmpty {
            // Bind identity to a key: any attestation claiming a pinned reviewer must be signed
            // with that exact pinned public key and the signature must verify. This is what stops
            // a spoofed `reviewer: human:leif`. Reviewers absent from the map are unaffected.
            for attestation in attestations {
                guard let pinnedKey = pinning[attestation.reviewer] else {
                    continue
                }
                if !attestation.isSigned {
                    violations.append(Violation(
                        commit: commit,
                        rule: "signerPinning",
                        detail: "reviewer \(attestation.reviewer) is pinned to a key but the attestation is unsigned"
                    ))
                } else if !Ed25519Verifier.isValid(attestation, expectedPublicKey: pinnedKey) {
                    violations.append(Violation(
                        commit: commit,
                        rule: "signerPinning",
                        detail: "reviewer \(attestation.reviewer) is not signed by its pinned public key"
                    ))
                }
            }
        }

        if let maxAge = policy.maxAgeDays {
            // Freshness: at least one attestation must be recent. The age of an attestation is the
            // whole-day distance between `now` and its `timestamp` (epoch seconds), against the
            // injected clock — never the system clock — so verification stays deterministic. We use
            // the *newest* attestation (the smallest age), so one fresh record clears the commit
            // even when older ones are also present. Records timestamped in the future have a
            // non-positive age and are therefore always within the window.
            let newestTimestamp = attestations.map(\.timestamp).max() ?? 0
            let ageDays = (now - newestTimestamp) / Verifier.secondsPerDay
            if ageDays > maxAge {
                violations.append(Violation(
                    commit: commit,
                    rule: "maxAgeDays",
                    detail: "newest attestation is \(ageDays) days old, exceeds maxAgeDays=\(maxAge)"
                ))
            }
        }

        return violations
    }

    /// Whether `reviewer` matches any of the allow-list `patterns`.
    ///
    /// A pattern matches when it equals `reviewer` exactly, or — when the pattern ends with
    /// `:` (a role prefix such as `"human:"`) — when `reviewer` begins with that prefix.
    private static func reviewerIsAllowed(_ reviewer: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if reviewer == pattern {
                return true
            }
            if pattern.hasSuffix(":"), reviewer.hasPrefix(pattern) {
                return true
            }
        }
        return false
    }
}
