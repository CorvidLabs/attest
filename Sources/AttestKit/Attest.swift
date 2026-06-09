@preconcurrency import Foundation

// MARK: - Facade

/// High-level entry point: record and read attestations against a store.
///
/// `Attest` composes an `AttestationStore` (git notes in production, an
/// in-memory fake in tests) with optional signing. It is the surface the CLI
/// drives and the unit the engine tests exercise.
public struct Attest: Sendable {
    private let store: any AttestationStore

    public init(store: any AttestationStore) {
        self.store = store
    }

    /// Records an attestation, optionally signing it first.
    ///
    /// - Parameters:
    ///   - attestation: The record to store.
    ///   - signer: When provided, the record is signed before storage.
    /// - Returns: The attestation as stored (signed when a signer was given).
    @discardableResult
    public func record(_ attestation: Attestation, signer: Ed25519Signer? = nil) throws -> Attestation {
        let final = try signer.map { try $0.sign(attestation) } ?? attestation
        try store.append(final)
        return final
    }

    /// All attestations for a commit, oldest first.
    public func attestations(for commit: String) throws -> [Attestation] {
        try store.attestations(for: commit)
    }

    /// Checks the given commits' attestations against a policy.
    ///
    /// - Parameters:
    ///   - commits: The commit SHAs to check.
    ///   - policy: The policy to evaluate.
    ///   - now: The reference time (Unix epoch seconds) for the `maxAgeDays`
    ///     freshness rule, injected so verification is deterministic. Defaults to
    ///     the current epoch.
    public func verify(
        commits: [String],
        policy: Policy,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> VerificationResult {
        let groups = try commits.map { commit in
            (commit: commit, attestations: try store.attestations(for: commit))
        }
        return Verifier(policy: policy).verify(commits: groups, now: now)
    }
}
