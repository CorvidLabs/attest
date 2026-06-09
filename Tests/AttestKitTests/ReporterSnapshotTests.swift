import XCTest
@testable import AttestKit

/// Golden-file snapshots of the human-readable terminal output, captured in both
/// plain (no-color) and colored (raw ANSI) modes.
///
/// These lock the *exact* bytes the CLI emits — including ANSI escape codes — so
/// the GitHub Pages site can mirror the real colored experience from a single
/// source of truth, and so future colour work can never silently change output.
///
/// Every fixture is fully deterministic: timestamps are fixed constants and the
/// renderer never reads a wall clock. The one signed record uses a fixed private
/// key; Ed25519 signatures are deterministic (RFC 8032), so the `signed[ok]`
/// badge resolves identically on every run.
final class ReporterSnapshotTests: XCTestCase {
    /// A fixed point in time for all fixtures (2023-11-14T22:13:20Z).
    private let now = 1_700_000_000

    /// A fixed 32-byte Ed25519 private key (base64) for deterministic signing.
    private static let fixedPrivateKey = Data(repeating: 7, count: 32).base64EncodedString()

    private static let enabled = Colorizer(enabled: true)

    // MARK: - Fixtures

    private func makeAttestation(
        commit: String = "abc1234567def",
        reviewer: String,
        confidence: Double,
        verdict: Verdict?,
        testsPassed: Bool,
        humanApproved: Bool,
        note: String? = nil
    ) -> Attestation {
        Attestation(
            commit: commit,
            reviewer: reviewer,
            confidence: confidence,
            verdict: verdict,
            testsPassed: testsPassed,
            humanApproved: humanApproved,
            timestamp: now,
            note: note
        )
    }

    private func fixedSigner() throws -> Ed25519Signer {
        try Ed25519Signer(base64PrivateKey: Self.fixedPrivateKey)
    }

    // MARK: - verify PASS

    func testVerifyPassPlainSnapshot() {
        let result = VerificationResult(passed: true, checkedCommits: 3, violations: [])
        assertSnapshot(Reporter.renderVerification(result, colorizer: .plain), "verify-pass-plain")
    }

    func testVerifyPassColorSnapshot() {
        let result = VerificationResult(passed: true, checkedCommits: 3, violations: [])
        assertSnapshot(Reporter.renderVerification(result, colorizer: Self.enabled), "verify-pass-color")
    }

    // MARK: - verify FAIL

    private func failResult() -> VerificationResult {
        VerificationResult(passed: false, checkedCommits: 2, violations: [
            Violation(
                commit: "abc1234567def",
                rule: "requireTestsPassed",
                detail: "no attestation reports passing tests"
            )
        ])
    }

    func testVerifyFailPlainSnapshot() {
        assertSnapshot(Reporter.renderVerification(failResult(), colorizer: .plain), "verify-fail-plain")
    }

    func testVerifyFailColorSnapshot() {
        assertSnapshot(Reporter.renderVerification(failResult(), colorizer: Self.enabled), "verify-fail-color")
    }

    // MARK: - ledger / log

    /// A realistic ledger: one commit with a signed, human-approved review record
    /// and an unsigned agent record that proceeds.
    private func ledgerGroups() throws -> [(commit: String, attestations: [Attestation])] {
        let signedHuman = try fixedSigner().sign(
            makeAttestation(
                reviewer: "human:leif",
                confidence: 0.72,
                verdict: .review,
                testsPassed: true,
                humanApproved: true,
                note: "reviewed the migration by hand"
            )
        )
        let unsignedAgent = makeAttestation(
            reviewer: "agent:claude",
            confidence: 0.95,
            verdict: .proceed,
            testsPassed: true,
            humanApproved: false
        )
        return [(commit: "abc1234567def", attestations: [unsignedAgent, signedHuman])]
    }

    func testLedgerMixPlainSnapshot() throws {
        assertSnapshot(Reporter.renderLog(try ledgerGroups(), colorizer: .plain), "ledger-mix-plain")
    }

    func testLedgerMixColorSnapshot() throws {
        assertSnapshot(Reporter.renderLog(try ledgerGroups(), colorizer: Self.enabled), "ledger-mix-color")
    }
}
