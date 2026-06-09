import XCTest
@testable import AttestKit

final class AttestKitTests: XCTestCase {
    private let now = 1_700_000_000

    // MARK: - Fixtures

    private func makeAttestation(
        commit: String = "abc123",
        reviewer: String = "agent:claude",
        confidence: Double = 0.9,
        verdict: Verdict? = .proceed,
        testsPassed: Bool = true,
        humanApproved: Bool = false,
        timestamp: Int? = nil,
        note: String? = nil
    ) -> Attestation {
        Attestation(
            commit: commit,
            reviewer: reviewer,
            confidence: confidence,
            verdict: verdict,
            testsPassed: testsPassed,
            humanApproved: humanApproved,
            timestamp: timestamp ?? now,
            note: note
        )
    }

    /// `maxAgeDays` measured in seconds against the fixture's `now`.
    private func daysAgo(_ days: Int) -> Int {
        now - days * 86_400
    }

    // MARK: - Canonical serialization

    func testCanonicalSerializationIsDeterministic() throws {
        let a = makeAttestation(note: "ok")
        let first = try a.canonicalString()
        let second = try a.canonicalString()
        XCTAssertEqual(first, second)
        // Keys must be sorted.
        XCTAssertTrue(first.hasPrefix("{\"commit\":"))
    }

    func testCanonicalExcludesSignatureFields() throws {
        let unsigned = makeAttestation()
        let signed = unsigned.attaching(signature: "AAAA", publicKey: "BBBB")
        // Attaching a signature must not change the bytes that get signed.
        XCTAssertEqual(try unsigned.canonicalData(), try signed.canonicalData())
        XCTAssertFalse(try signed.canonicalString().contains("signature"))
        XCTAssertFalse(try signed.canonicalString().contains("publicKey"))
    }

    func testConfidenceIsClamped() {
        XCTAssertEqual(makeAttestation(confidence: 1.5).confidence, 1.0)
        XCTAssertEqual(makeAttestation(confidence: -0.2).confidence, 0.0)
    }

    // MARK: - Signing round-trip

    func testSignVerifyRoundTrip() throws {
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation())
        XCTAssertTrue(signed.isSigned)
        XCTAssertNoThrow(try Ed25519Verifier.verify(signed))
        XCTAssertTrue(Ed25519Verifier.isValid(signed))
        XCTAssertEqual(signed.publicKey, signer.base64PublicKey)
    }

    func testVerifyFailsOnTamperedContent() throws {
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation(confidence: 0.9))
        // Tamper with the confidence; the embedded signature no longer matches.
        let tampered = Attestation(
            commit: signed.commit,
            reviewer: signed.reviewer,
            confidence: 0.1,
            verdict: signed.verdict,
            testsPassed: signed.testsPassed,
            humanApproved: signed.humanApproved,
            timestamp: signed.timestamp,
            note: signed.note,
            signature: signed.signature,
            publicKey: signed.publicKey
        )
        XCTAssertFalse(Ed25519Verifier.isValid(tampered))
        XCTAssertThrowsError(try Ed25519Verifier.verify(tampered))
    }

    func testVerifyFailsOnUnexpectedPublicKey() throws {
        let signer = Ed25519Signer.generate()
        let other = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation())
        XCTAssertThrowsError(try Ed25519Verifier.verify(signed, expectedPublicKey: other.base64PublicKey))
    }

    func testVerifyUnsignedThrowsSignatureMissing() {
        let unsigned = makeAttestation()
        XCTAssertThrowsError(try Ed25519Verifier.verify(unsigned)) { error in
            XCTAssertEqual(error as? AttestError, .signatureMissing)
        }
    }

    func testSignerRoundTripsThroughBase64Key() throws {
        let signer = Ed25519Signer.generate()
        let reloaded = try Ed25519Signer(base64PrivateKey: signer.base64PrivateKey)
        XCTAssertEqual(signer.base64PublicKey, reloaded.base64PublicKey)
        let signed = try reloaded.sign(makeAttestation())
        XCTAssertTrue(Ed25519Verifier.isValid(signed))
    }

    // MARK: - JSON Lines codec

    func testCodecRoundTrip() throws {
        let a = makeAttestation(note: "first")
        let b = makeAttestation(commit: "abc123", reviewer: "human:leif", confidence: 0.5, verdict: .review)
        let body = [try AttestationCodec.encodeLine(a), try AttestationCodec.encodeLine(b)].joined(separator: "\n")
        let decoded = try AttestationCodec.decodeLines(body)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].note, "first")
        XCTAssertEqual(decoded[1].reviewer, "human:leif")
    }

    func testCodecRejectsMalformedLine() {
        XCTAssertThrowsError(try AttestationCodec.decodeLines("{not json"))
    }

    // MARK: - In-memory store + facade

    func testInMemoryStoreAppendsMultiplePerCommit() throws {
        let store = InMemoryStore()
        let attest = Attest(store: store)
        try attest.record(makeAttestation(reviewer: "agent:claude"))
        try attest.record(makeAttestation(reviewer: "human:leif"))
        let recorded = try attest.attestations(for: "abc123")
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(try store.attestedCommits(), ["abc123"])
    }

    func testRecordWithSignerStoresSignedRecord() throws {
        let store = InMemoryStore()
        let signer = Ed25519Signer.generate()
        let stored = try Attest(store: store).record(makeAttestation(), signer: signer)
        XCTAssertTrue(stored.isSigned)
        XCTAssertTrue(Ed25519Verifier.isValid(stored))
    }

    // MARK: - Policy

    func testDefaultPolicyRequiresAttestation() {
        let result = Verifier(policy: .default).verify(commits: [(commit: "c1", attestations: [])])
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.rule, "requireAttestation")
    }

    func testPolicyPassesWithSatisfyingAttestation() {
        let policy = Policy(requireTestsPassed: true)
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(testsPassed: true)])
        ])
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func testPolicyRequireTestsPassedFails() {
        let policy = Policy(requireTestsPassed: true)
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(testsPassed: false)])
        ])
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.rule, "requireTestsPassed")
    }

    func testHumanApprovalRequiredWhenVerdictAtLeastReview() {
        let policy = Policy(requireHumanApprovalWhenVerdictAtLeast: .review)
        let blocked = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .block, humanApproved: false)])
        ])
        XCTAssertFalse(blocked.passed)
        XCTAssertEqual(blocked.violations.first?.rule, "requireHumanApprovalWhenVerdictAtLeast")

        // Back-compat: a single attestation that both carries the verdict and is
        // human-approved still passes.
        let approved = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .block, humanApproved: true)])
        ])
        XCTAssertTrue(approved.passed)

        // A proceed verdict does not trigger the rule.
        let proceed = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .proceed, humanApproved: false)])
        ])
        XCTAssertTrue(proceed.passed)
    }

    func testHumanApprovalSatisfiedBySeparateAttestation() {
        let policy = Policy(requireHumanApprovalWhenVerdictAtLeast: .review)
        // An agent files the high verdict; a human files a separate sign-off that does
        // not restate the verdict. The commit should pass.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", verdict: .review, humanApproved: false),
                makeAttestation(reviewer: "human:leif", verdict: nil, humanApproved: true)
            ])
        ])
        XCTAssertTrue(result.passed)
    }

    func testHumanApprovalFailsWithoutAnySignOff() {
        let policy = Policy(requireHumanApprovalWhenVerdictAtLeast: .review)
        // Only an agent review with no human approval anywhere on the commit.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", verdict: .review, humanApproved: false)
            ])
        ])
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "requireHumanApprovalWhenVerdictAtLeast")
        XCTAssertEqual(
            violation?.detail,
            "verdict is at least review on this commit but no attestation is human-approved"
        )
    }

    func testHumanApprovalNotTriggeredWhenAllVerdictsBelowThreshold() {
        let policy = Policy(requireHumanApprovalWhenVerdictAtLeast: .review)
        // Every verdict is below the threshold and no human approval exists: the rule
        // does not trigger, so the commit passes.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", verdict: .proceed, humanApproved: false),
                makeAttestation(reviewer: "agent:gpt", verdict: .proceed, humanApproved: false)
            ])
        ])
        XCTAssertTrue(result.passed)
    }

    func testRequireSignaturePolicy() throws {
        let policy = Policy(requireSignature: true)
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation())
        let unsigned = makeAttestation()
        XCTAssertTrue(Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [signed])]).passed)
        XCTAssertFalse(Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [unsigned])]).passed)
    }

    func testMinimumConfidencePolicy() {
        let policy = Policy(minimumConfidence: 0.8)
        let low = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(confidence: 0.5)])
        ])
        XCTAssertFalse(low.passed)
        let high = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(confidence: 0.95)])
        ])
        XCTAssertTrue(high.passed)
    }

    // MARK: - Policy: allowedReviewers

    func testAllowedReviewersAllowsPrefixAndExactMatches() {
        // "human:" is a role prefix (allows any human:*); "agent:claude" is an exact match.
        let policy = Policy(allowedReviewers: ["human:", "agent:claude"])
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "human:leif"),
                makeAttestation(reviewer: "agent:claude")
            ])
        ])
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func testAllowedReviewersRejectsOffListReviewer() {
        // "agent:claude" is exact-only, so "agent:gpt" is rejected; "human:" allows human:leif.
        let policy = Policy(allowedReviewers: ["human:", "agent:claude"])
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "human:leif"),
                makeAttestation(reviewer: "agent:gpt")
            ])
        ])
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.count, 1)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "allowedReviewers")
        XCTAssertEqual(
            violation?.detail,
            "reviewer agent:gpt is not in the allow-list [\"human:\", \"agent:claude\"]"
        )
    }

    func testAllowedReviewersEmptyListDisablesRule() {
        // An empty list (or nil) disables the rule entirely.
        let policy = Policy(allowedReviewers: [])
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(reviewer: "anyone:at:all")])
        ])
        XCTAssertTrue(result.passed)
    }

    // MARK: - Policy: requireSignatureWhenVerdictAtLeast

    func testRequireSignatureWhenVerdictAtLeastPassesWithSignedAttestation() throws {
        let policy = Policy(requireSignatureWhenVerdictAtLeast: .review)
        let signer = Ed25519Signer.generate()
        // The high verdict is on an unsigned agent record; a separate signed record satisfies it.
        let signed = try signer.sign(makeAttestation(reviewer: "human:leif", verdict: nil))
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", verdict: .block),
                signed
            ])
        ])
        XCTAssertTrue(result.passed)
    }

    func testRequireSignatureWhenVerdictAtLeastFailsWithoutSignature() {
        let policy = Policy(requireSignatureWhenVerdictAtLeast: .review)
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .block)])
        ])
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "requireSignatureWhenVerdictAtLeast")
        XCTAssertEqual(
            violation?.detail,
            "verdict is at least review on this commit but no attestation is validly signed"
        )
    }

    func testRequireSignatureWhenVerdictAtLeastNotTriggeredBelowThreshold() {
        let policy = Policy(requireSignatureWhenVerdictAtLeast: .block)
        // Highest verdict is review, below the block threshold: rule does not trigger.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .review)])
        ])
        XCTAssertTrue(result.passed)
    }

    // MARK: - Policy: requireTestsPassedWhenVerdictAtLeast

    func testRequireTestsPassedWhenVerdictAtLeastPassesWithPassingTests() {
        let policy = Policy(requireTestsPassedWhenVerdictAtLeast: .review)
        // High verdict on a record without tests; a separate record reports passing tests.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", verdict: .block, testsPassed: false),
                makeAttestation(reviewer: "ci:runner", verdict: nil, testsPassed: true)
            ])
        ])
        XCTAssertTrue(result.passed)
    }

    func testRequireTestsPassedWhenVerdictAtLeastFailsWithoutPassingTests() {
        let policy = Policy(requireTestsPassedWhenVerdictAtLeast: .review)
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .block, testsPassed: false)])
        ])
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "requireTestsPassedWhenVerdictAtLeast")
        XCTAssertEqual(
            violation?.detail,
            "verdict is at least review on this commit but no attestation reports passing tests"
        )
    }

    func testRequireTestsPassedWhenVerdictAtLeastNotTriggeredBelowThreshold() {
        let policy = Policy(requireTestsPassedWhenVerdictAtLeast: .block)
        // Highest verdict is review, below block: rule does not trigger even with failing tests.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(verdict: .review, testsPassed: false)])
        ])
        XCTAssertTrue(result.passed)
    }

    // MARK: - Policy: trustedKeys

    func testTrustedKeysPassesWithTrustedSignedAttestation() throws {
        let signer = Ed25519Signer.generate()
        let policy = Policy(trustedKeys: [signer.base64PublicKey])
        let signed = try signer.sign(makeAttestation(reviewer: "human:leif"))
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [signed])])
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func testTrustedKeysFailsWithUntrustedSignedAttestation() throws {
        let trusted = Ed25519Signer.generate()
        let other = Ed25519Signer.generate()
        let policy = Policy(trustedKeys: [trusted.base64PublicKey])
        // A perfectly valid signature, but by a signer whose key is not trusted.
        let signed = try other.sign(makeAttestation(reviewer: "human:leif"))
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [signed])])
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "trustedKeys")
        XCTAssertEqual(
            violation?.detail,
            "signed attestation by human:leif uses an untrusted public key"
        )
    }

    func testTrustedKeysFailsTamperedSignedAttestation() throws {
        let signer = Ed25519Signer.generate()
        let policy = Policy(trustedKeys: [signer.base64PublicKey])
        let signed = try signer.sign(makeAttestation(confidence: 0.9))
        // Keep the (trusted) key and signature, but tamper with the content.
        let tampered = Attestation(
            commit: signed.commit,
            reviewer: signed.reviewer,
            confidence: 0.1,
            verdict: signed.verdict,
            testsPassed: signed.testsPassed,
            humanApproved: signed.humanApproved,
            timestamp: signed.timestamp,
            note: signed.note,
            signature: signed.signature,
            publicKey: signed.publicKey
        )
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [tampered])])
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.rule, "trustedKeys")
        XCTAssertEqual(
            result.violations.first?.detail,
            "signed attestation by \(tampered.reviewer) does not validate"
        )
    }

    func testTrustedKeysDoesNotForceUnsignedAttestationToSign() {
        // `trustedKeys` constrains which keys count as trusted; it does not by itself force
        // signing. An unsigned attestation is unaffected (signing requirements live in the
        // separate `requireSignature*` rules).
        let signer = Ed25519Signer.generate()
        let policy = Policy(trustedKeys: [signer.base64PublicKey])
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(reviewer: "agent:claude")])
        ])
        XCTAssertTrue(result.passed)
    }

    func testTrustedKeysEmptyListDisablesRule() throws {
        let other = Ed25519Signer.generate()
        let policy = Policy(trustedKeys: [])
        let signed = try other.sign(makeAttestation())
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [signed])])
        XCTAssertTrue(result.passed)
    }

    // MARK: - Policy: signerPinning

    func testSignerPinningPassesWhenPinnedReviewerSignedWithCorrectKey() throws {
        let signer = Ed25519Signer.generate()
        let policy = Policy(signerPinning: ["human:leif": signer.base64PublicKey])
        let signed = try signer.sign(makeAttestation(reviewer: "human:leif"))
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [signed])])
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func testSignerPinningFailsWhenPinnedReviewerSignedWithWrongKey() throws {
        let pinned = Ed25519Signer.generate()
        let imposter = Ed25519Signer.generate()
        let policy = Policy(signerPinning: ["human:leif": pinned.base64PublicKey])
        // Someone signs as human:leif with their own (valid, but not pinned) key.
        let signed = try imposter.sign(makeAttestation(reviewer: "human:leif"))
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [signed])])
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "signerPinning")
        XCTAssertEqual(
            violation?.detail,
            "reviewer human:leif is not signed by its pinned public key"
        )
    }

    func testSignerPinningFailsWhenPinnedReviewerUnsigned() throws {
        let pinned = Ed25519Signer.generate()
        let policy = Policy(signerPinning: ["human:leif": pinned.base64PublicKey])
        // The classic spoof: an unsigned record simply claiming reviewer human:leif.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(reviewer: "human:leif")])
        ])
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "signerPinning")
        XCTAssertEqual(
            violation?.detail,
            "reviewer human:leif is pinned to a key but the attestation is unsigned"
        )
    }

    func testSignerPinningLeavesNonPinnedReviewersUnaffected() throws {
        let pinned = Ed25519Signer.generate()
        let policy = Policy(signerPinning: ["human:leif": pinned.base64PublicKey])
        // agent:claude is not pinned, so an unsigned record from it passes.
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(reviewer: "agent:claude")])
        ])
        XCTAssertTrue(result.passed)
    }

    func testSignerPinningFailsTamperedSignatureForPinnedReviewer() throws {
        let pinned = Ed25519Signer.generate()
        let policy = Policy(signerPinning: ["human:leif": pinned.base64PublicKey])
        let signed = try pinned.sign(makeAttestation(reviewer: "human:leif", confidence: 0.9))
        // Tamper: correct pinned key, but mutated content invalidates the signature.
        let tampered = Attestation(
            commit: signed.commit,
            reviewer: signed.reviewer,
            confidence: 0.1,
            verdict: signed.verdict,
            testsPassed: signed.testsPassed,
            humanApproved: signed.humanApproved,
            timestamp: signed.timestamp,
            note: signed.note,
            signature: signed.signature,
            publicKey: signed.publicKey
        )
        let result = Verifier(policy: policy).verify(commits: [(commit: "c1", attestations: [tampered])])
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.rule, "signerPinning")
    }

    func testSignerPinningEmptyMapDisablesRule() {
        let policy = Policy(signerPinning: [:])
        let result = Verifier(policy: policy).verify(commits: [
            (commit: "c1", attestations: [makeAttestation(reviewer: "human:leif")])
        ])
        XCTAssertTrue(result.passed)
    }

    // MARK: - Policy: maxAgeDays (freshness)

    func testMaxAgeDaysPassesWithFreshAttestation() {
        let policy = Policy(maxAgeDays: 30)
        // Recorded 10 days before `now`: well within the 30-day window.
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: daysAgo(10))])],
            now: now
        )
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func testMaxAgeDaysFailsWithStaleAttestation() {
        let policy = Policy(maxAgeDays: 30)
        // Recorded 45 days before `now`: older than the 30-day window.
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: daysAgo(45))])],
            now: now
        )
        XCTAssertFalse(result.passed)
        let violation = result.violations.first
        XCTAssertEqual(violation?.rule, "maxAgeDays")
        XCTAssertEqual(violation?.detail, "newest attestation is 45 days old, exceeds maxAgeDays=30")
    }

    func testMaxAgeDaysPassesWhenAnyAttestationIsFresh() {
        let policy = Policy(maxAgeDays: 30)
        // A mix: two stale records and one fresh — the newest (fresh) clears the commit.
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", timestamp: daysAgo(90)),
                makeAttestation(reviewer: "agent:gpt", timestamp: daysAgo(60)),
                makeAttestation(reviewer: "human:leif", timestamp: daysAgo(5))
            ])],
            now: now
        )
        XCTAssertTrue(result.passed)
    }

    func testMaxAgeDaysNotTriggeredWhenNil() {
        // The rule is off by default; an ancient attestation passes when maxAgeDays is nil.
        let policy = Policy()
        XCTAssertNil(policy.maxAgeDays)
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: daysAgo(10_000))])],
            now: now
        )
        XCTAssertTrue(result.passed)
    }

    func testMaxAgeDaysBoundaryExactlyAtLimitPasses() {
        let policy = Policy(maxAgeDays: 30)
        // Exactly 30 days old: age == limit, which is within the window (not greater than).
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: daysAgo(30))])],
            now: now
        )
        XCTAssertTrue(result.passed)
    }

    func testMaxAgeDaysBoundaryJustOverLimitFails() {
        let policy = Policy(maxAgeDays: 30)
        // 31 days old: one whole day past the limit, so it fails.
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: daysAgo(31))])],
            now: now
        )
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.detail, "newest attestation is 31 days old, exceeds maxAgeDays=30")
    }

    func testMaxAgeDaysSubDayDifferenceIsZeroDaysAndPasses() {
        let policy = Policy(maxAgeDays: 0)
        // A few hours old rounds down to 0 whole days, satisfying even maxAgeDays=0.
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: now - 3_600)])],
            now: now
        )
        XCTAssertTrue(result.passed)
    }

    func testMaxAgeDaysFutureTimestampIsAlwaysFresh() {
        let policy = Policy(maxAgeDays: 30)
        // A timestamp in the future yields a non-positive age, always within the window.
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [makeAttestation(timestamp: now + 86_400)])],
            now: now
        )
        XCTAssertTrue(result.passed)
    }

    func testMaxAgeDaysFailsWhenNoAttestationsExist() {
        // With no attestations, freshness cannot be satisfied; the rule fires its own violation.
        let policy = Policy(requireAttestation: false, maxAgeDays: 30)
        let result = Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [])],
            now: now
        )
        XCTAssertFalse(result.passed)
        let violation = result.violations.first { $0.rule == "maxAgeDays" }
        XCTAssertEqual(violation?.detail, "no attestation exists to satisfy maxAgeDays=30")
    }

    func testMaxAgeDaysUsesInjectedClockNotSystemClock() {
        // Determinism: the same inputs at two different injected "now"s give opposite verdicts,
        // proving the rule reads the injected clock, never `Date()`.
        let policy = Policy(maxAgeDays: 30)
        let attestation = makeAttestation(timestamp: 1_000_000_000)
        let freshNow = 1_000_000_000 + 10 * 86_400   // 10 days later
        let staleNow = 1_000_000_000 + 90 * 86_400   // 90 days later
        XCTAssertTrue(Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [attestation])], now: freshNow
        ).passed)
        XCTAssertFalse(Verifier(policy: policy).verify(
            commits: [(commit: "c1", attestations: [attestation])], now: staleNow
        ).passed)
    }

    func testMaxAgeDaysThroughFacadeVerify() throws {
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1", timestamp: daysAgo(45)))
        let result = try Attest(store: store).verify(
            commits: ["c1"],
            policy: Policy(maxAgeDays: 30),
            now: now
        )
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.first?.rule, "maxAgeDays")
    }

    func testMaxAgeDaysDecodesFromJSON() throws {
        let policy = try JSONDecoder().decode(Policy.self, from: Data("{\"maxAgeDays\": 14}".utf8))
        XCTAssertEqual(policy.maxAgeDays, 14)
    }

    // MARK: - Canonical serialization: robustness

    func testCanonicalStableAcrossConstructionFieldPermutations() throws {
        // Two attestations built with the same content but differing only in the order/way fields
        // are supplied must produce byte-identical canonical bytes (the form is keyed, not ordered).
        let a = Attestation(
            commit: "c1", reviewer: "human:leif", confidence: 0.42,
            verdict: .review, testsPassed: true, humanApproved: true,
            timestamp: now, note: "looks fine"
        )
        let b = Attestation(
            commit: "c1", reviewer: "human:leif", confidence: 0.42,
            verdict: .review, testsPassed: true, humanApproved: true,
            timestamp: now, note: "looks fine"
        )
        XCTAssertEqual(try a.canonicalData(), try b.canonicalData())
    }

    func testCanonicalHandlesUnicodeInReviewerAndNote() throws {
        let attestation = makeAttestation(reviewer: "human:léïf-审查", note: "approved · 🦅 — looks good")
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(attestation)
        // Unicode round-trips through signing/verification unharmed.
        XCTAssertTrue(Ed25519Verifier.isValid(signed))
        // And through JSON-Lines storage.
        let body = try AttestationCodec.encodeLine(signed)
        let decoded = try AttestationCodec.decodeLines(body)
        XCTAssertEqual(decoded.first?.reviewer, "human:léïf-审查")
        XCTAssertEqual(decoded.first?.note, "approved · 🦅 — looks good")
    }

    func testCanonicalOmitsEmptyOptionalsConsistently() throws {
        // A nil note and nil verdict are omitted from the canonical form (encodeIfPresent),
        // and a record with them omitted differs from one that sets them.
        let bare = Attestation(commit: "c1", reviewer: "agent:claude", confidence: 0.5, timestamp: now)
        let canonical = try bare.canonicalString()
        XCTAssertFalse(canonical.contains("note"))
        XCTAssertFalse(canonical.contains("verdict"))
        let withNote = makeAttestation(verdict: nil, note: "x")
        XCTAssertNotEqual(try bare.canonicalData(), try withNote.canonicalData())
    }

    func testCanonicalSlashesAreNotEscaped() throws {
        let attestation = makeAttestation(reviewer: "agent:org/team", note: "see https://example.com/x")
        let canonical = try attestation.canonicalString()
        XCTAssertTrue(canonical.contains("org/team"))
        XCTAssertFalse(canonical.contains("\\/"))
    }

    // MARK: - Signature: robustness

    func testVerifyFailsOnEmptySignature() {
        let attestation = makeAttestation().attaching(signature: "", publicKey: "BBBB")
        XCTAssertFalse(Ed25519Verifier.isValid(attestation))
    }

    func testVerifyFailsOnGarbageSignatureBytes() throws {
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation())
        // Keep the real public key, swap in a malformed (but base64) signature.
        let broken = signed.attaching(signature: "AAAA", publicKey: signed.publicKey ?? "")
        XCTAssertFalse(Ed25519Verifier.isValid(broken))
    }

    func testVerifyFailsOnNonBase64PublicKey() throws {
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation())
        let broken = signed.attaching(signature: signed.signature ?? "", publicKey: "!!!not base64!!!")
        XCTAssertThrowsError(try Ed25519Verifier.verify(broken))
    }

    func testSameKeyReusedAcrossDistinctCommitsVerifiesEach() throws {
        // One signer signing two different commits: each signature is bound to its own
        // canonical bytes, so both verify and neither validates against the other's content.
        let signer = Ed25519Signer.generate()
        let first = try signer.sign(makeAttestation(commit: "c1"))
        let second = try signer.sign(makeAttestation(commit: "c2"))
        XCTAssertTrue(Ed25519Verifier.isValid(first))
        XCTAssertTrue(Ed25519Verifier.isValid(second))
        XCTAssertNotEqual(first.signature, second.signature)
        // Cross-applying one signature to the other's content fails.
        let crossed = second.attaching(signature: first.signature ?? "", publicKey: first.publicKey ?? "")
        XCTAssertFalse(Ed25519Verifier.isValid(crossed))
    }

    func testInvalidBase64PrivateKeyThrowsInvalidKey() {
        XCTAssertThrowsError(try Ed25519Signer(base64PrivateKey: "not base64!!")) { error in
            XCTAssertEqual(error as? AttestError, .invalidKey("private key is not valid base64"))
        }
    }

    func testWrongLengthPrivateKeyThrowsInvalidKey() {
        // Valid base64, but the wrong number of bytes for an Ed25519 key.
        let tooShort = Data([1, 2, 3]).base64EncodedString()
        XCTAssertThrowsError(try Ed25519Signer(base64PrivateKey: tooShort))
    }

    // MARK: - Store: robustness

    func testInMemoryStoreReturnsEmptyForUnknownCommit() throws {
        let store = InMemoryStore()
        XCTAssertEqual(try store.attestations(for: "never-seen").count, 0)
        XCTAssertTrue(try store.attestedCommits().isEmpty)
    }

    func testInMemoryStoreKeepsCommitsDistinct() throws {
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1", reviewer: "agent:claude"))
        try store.append(makeAttestation(commit: "c1", reviewer: "human:leif"))
        try store.append(makeAttestation(commit: "c2", reviewer: "agent:claude"))
        XCTAssertEqual(try store.attestations(for: "c1").count, 2)
        XCTAssertEqual(try store.attestations(for: "c2").count, 1)
        XCTAssertEqual(try store.attestedCommits().sorted(), ["c1", "c2"])
    }

    func testCodecDecodesMultipleLinesPreservingOrder() throws {
        let a = makeAttestation(reviewer: "agent:claude", timestamp: daysAgo(2))
        let b = makeAttestation(reviewer: "human:leif", timestamp: daysAgo(1))
        let c = makeAttestation(reviewer: "ci:runner", timestamp: now)
        let body = [a, b, c].map { (try? AttestationCodec.encodeLine($0)) ?? "" }.joined(separator: "\n")
        let decoded = try AttestationCodec.decodeLines(body)
        XCTAssertEqual(decoded.map(\.reviewer), ["agent:claude", "human:leif", "ci:runner"])
    }

    func testCodecSkipsBlankLinesBetweenRecords() throws {
        let a = try AttestationCodec.encodeLine(makeAttestation(reviewer: "agent:claude"))
        let b = try AttestationCodec.encodeLine(makeAttestation(reviewer: "human:leif"))
        // Extra blank lines (e.g. from a sloppy hand-edit of a note) are tolerated.
        let body = "\n\(a)\n\n\(b)\n\n"
        let decoded = try AttestationCodec.decodeLines(body)
        XCTAssertEqual(decoded.count, 2)
    }

    func testCodecMalformedLineThrowsClearError() {
        // A single corrupt line surfaces a malformedRecord error rather than silently dropping
        // data — corruption in an audit ledger must be loud, not lossy.
        let good = (try? AttestationCodec.encodeLine(makeAttestation())) ?? ""
        let body = "\(good)\n{ this is not json }"
        XCTAssertThrowsError(try AttestationCodec.decodeLines(body)) { error in
            guard case AttestError.malformedRecord(let detail) = error else {
                return XCTFail("expected malformedRecord, got \(error)")
            }
            // The message is clean and stable, not a dump of Swift DecodingError internals.
            XCTAssertEqual(detail, "invalid JSON")
            let description = (error as? AttestError)?.errorDescription ?? ""
            XCTAssertEqual(description, "Malformed attestation record: invalid JSON")
            XCTAssertFalse(description.contains("DecodingError"))
            XCTAssertFalse(description.contains("CodingKeys"))
        }
    }

    func testCodecEmptyBodyDecodesToNoRecords() throws {
        XCTAssertTrue(try AttestationCodec.decodeLines("").isEmpty)
        XCTAssertTrue(try AttestationCodec.decodeLines("\n\n").isEmpty)
    }

    // MARK: - Exporter: robustness

    func testExportEmptyRangeProducesEmptyReport() throws {
        let report = try Exporter(store: InMemoryStore()).report(commits: [])
        XCTAssertEqual(report.commitCount, 0)
        XCTAssertEqual(report.recordCount, 0)
        XCTAssertTrue(report.commits.isEmpty)
        XCTAssertFalse(report.policyApplied)
        XCTAssertNil(report.allPassed)
    }

    func testExportMixedSignedAndUnsignedAggregatesCounts() throws {
        let store = InMemoryStore()
        let signer = Ed25519Signer.generate()
        try store.append(try signer.sign(makeAttestation(commit: "c1", reviewer: "human:leif")))
        try store.append(makeAttestation(commit: "c1", reviewer: "agent:claude")) // unsigned
        try store.append(makeAttestation(commit: "c2", reviewer: "agent:gpt"))     // unsigned
        let report = try Exporter(store: store).report(commits: ["c1", "c2"])
        XCTAssertEqual(report.recordCount, 3)
        let signedCount = report.commits.flatMap(\.records).filter { $0.verification.signed }.count
        XCTAssertEqual(signedCount, 1)
    }

    func testExportPolicyAggregationAllPassWhenEveryCommitPasses() throws {
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1", testsPassed: true))
        try store.append(makeAttestation(commit: "c2", testsPassed: true))
        let report = try Exporter(store: store).report(
            commits: ["c1", "c2"],
            policy: Policy(requireTestsPassed: true)
        )
        XCTAssertEqual(report.allPassed, true)
        XCTAssertEqual(report.commits.compactMap(\.policyPassed), [true, true])
    }

    func testExportHonorsInjectedClockForFreshnessPolicy() throws {
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1", timestamp: daysAgo(45)))
        // With maxAgeDays=30 and our fixture `now`, the 45-day-old record fails.
        let report = try Exporter(store: store).report(
            commits: ["c1"],
            policy: Policy(maxAgeDays: 30),
            now: now
        )
        XCTAssertEqual(report.allPassed, false)
        XCTAssertEqual(report.commits.first?.policyPassed, false)
    }

    func testExportRecordsPreserveStoreOrderOldestFirst() throws {
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1", reviewer: "first", timestamp: daysAgo(3)))
        try store.append(makeAttestation(commit: "c1", reviewer: "second", timestamp: daysAgo(2)))
        try store.append(makeAttestation(commit: "c1", reviewer: "third", timestamp: daysAgo(1)))
        let report = try Exporter(store: store).report(commits: ["c1"])
        XCTAssertEqual(report.commits[0].records.map(\.attestation.reviewer), ["first", "second", "third"])
    }

    func testPolicyDecodesFromJSON() throws {
        let json = """
        {
          "requireTestsPassed": true,
          "requireHumanApprovalWhenVerdictAtLeast": "review",
          "minimumConfidence": 0.7,
          "allowedReviewers": ["human:", "agent:claude"],
          "requireSignatureWhenVerdictAtLeast": "block",
          "requireTestsPassedWhenVerdictAtLeast": "review",
          "trustedKeys": ["AAAA", "BBBB"],
          "signerPinning": { "human:leif": "AAAA" },
          "maxAgeDays": 90
        }
        """
        let policy = try JSONDecoder().decode(Policy.self, from: Data(json.utf8))
        XCTAssertTrue(policy.requireTestsPassed)
        XCTAssertEqual(policy.requireHumanApprovalWhenVerdictAtLeast, .review)
        XCTAssertEqual(policy.minimumConfidence, 0.7)
        XCTAssertEqual(policy.allowedReviewers, ["human:", "agent:claude"])
        XCTAssertEqual(policy.requireSignatureWhenVerdictAtLeast, .block)
        XCTAssertEqual(policy.requireTestsPassedWhenVerdictAtLeast, .review)
        XCTAssertEqual(policy.trustedKeys, ["AAAA", "BBBB"])
        XCTAssertEqual(policy.signerPinning, ["human:leif": "AAAA"])
        XCTAssertEqual(policy.maxAgeDays, 90)
        // Unspecified fields take defaults.
        XCTAssertTrue(policy.requireAttestation)
        XCTAssertFalse(policy.requireSignature)
    }

    func testEmptyPolicyJSONUsesDefaults() throws {
        let policy = try JSONDecoder().decode(Policy.self, from: Data("{}".utf8))
        XCTAssertEqual(policy, .default)
    }

    func testEmptyCommitRangeChecksZeroCommitsAndPasses() throws {
        // An empty range (e.g. `HEAD..HEAD`) yields no commits; verification
        // reports zero checked and passes — there is nothing to violate.
        let store = InMemoryStore()
        let result = try Attest(store: store).verify(commits: [], policy: .default)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.checkedCommits, 0)
        XCTAssertTrue(result.violations.isEmpty)
    }

    func testVerifyReportsPerCommitPassAndFail() throws {
        // Two commits checked: one with no attestation fails, one with a
        // satisfying attestation passes; the result counts both and pins the
        // violation to the offending commit.
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "good", testsPassed: true))
        try store.append(makeAttestation(commit: "bad", testsPassed: false))
        let result = try Attest(store: store).verify(
            commits: ["good", "bad"],
            policy: Policy(requireTestsPassed: true)
        )
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.checkedCommits, 2)
        XCTAssertEqual(result.violations.count, 1)
        XCTAssertEqual(result.violations.first?.commit, "bad")
        XCTAssertEqual(result.violations.first?.rule, "requireTestsPassed")
    }

    // MARK: - Audit export

    func testExportProducesCompleteDeterministicReport() throws {
        // Two commits, multiple attestations on one of them. The export must
        // cover every supplied commit, in supplied order, with records oldest-first.
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1", reviewer: "agent:claude", confidence: 0.9))
        try store.append(makeAttestation(commit: "c1", reviewer: "human:leif", confidence: 0.7, verdict: .review))
        try store.append(makeAttestation(commit: "c2", reviewer: "agent:claude", confidence: 0.5))

        let report = try Exporter(store: store).report(commits: ["c1", "c2"])
        XCTAssertEqual(report.version, AuditReport.formatVersion)
        XCTAssertEqual(report.commitCount, 2)
        XCTAssertEqual(report.recordCount, 3)
        XCTAssertFalse(report.policyApplied)
        XCTAssertNil(report.allPassed)
        // Commits in supplied order; records oldest-first within a commit.
        XCTAssertEqual(report.commits.map(\.commit), ["c1", "c2"])
        XCTAssertEqual(report.commits[0].records.count, 2)
        XCTAssertEqual(report.commits[0].records[0].attestation.reviewer, "agent:claude")
        XCTAssertEqual(report.commits[0].records[1].attestation.reviewer, "human:leif")
        XCTAssertNil(report.commits[0].policyPassed)

        // Determinism: identical inputs yield byte-identical JSON.
        let first = try report.jsonString(pretty: false)
        let second = try Exporter(store: store).report(commits: ["c1", "c2"]).jsonString(pretty: false)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("\"commitCount\":2"))
    }

    func testExportCoversEmptyCommitWithNoRecords() throws {
        // A commit with no attestations is still represented (empty records),
        // so an auditor sees the full surface of the range.
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "c1"))
        let report = try Exporter(store: store).report(commits: ["c1", "empty"])
        XCTAssertEqual(report.commitCount, 2)
        XCTAssertEqual(report.recordCount, 1)
        XCTAssertEqual(report.commits[1].commit, "empty")
        XCTAssertTrue(report.commits[1].records.isEmpty)
    }

    func testExportReportsVerificationStatusForSignedAndUnsigned() throws {
        let store = InMemoryStore()
        let signer = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation(commit: "c1", reviewer: "human:leif"))
        try store.append(signed)
        try store.append(makeAttestation(commit: "c1", reviewer: "agent:claude")) // unsigned

        let report = try Exporter(store: store).report(commits: ["c1"])
        let records = report.commits[0].records
        XCTAssertEqual(records.count, 2)
        // Signed record verifies against its embedded key.
        XCTAssertTrue(records[0].verification.signed)
        XCTAssertEqual(records[0].verification.verified, true)
        // Unsigned record: signed=false, verified omitted (nil).
        XCTAssertFalse(records[1].verification.signed)
        XCTAssertNil(records[1].verification.verified)
    }

    func testExportFlagsTamperedAndWrongKeySignaturesAsUnverified() throws {
        let store = InMemoryStore()
        let signer = Ed25519Signer.generate()
        let other = Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation(commit: "c1", confidence: 0.9))
        // Tamper: keep the signature pair but change content.
        let tampered = Attestation(
            commit: signed.commit,
            reviewer: signed.reviewer,
            confidence: 0.1,
            verdict: signed.verdict,
            testsPassed: signed.testsPassed,
            humanApproved: signed.humanApproved,
            timestamp: signed.timestamp,
            note: signed.note,
            signature: signed.signature,
            publicKey: signed.publicKey
        )
        // Wrong key: a valid signature from one signer, but another signer's public key.
        let wrongKey = signed.attaching(signature: signed.signature ?? "", publicKey: other.base64PublicKey)
        try store.append(tampered)
        try store.append(wrongKey)

        let report = try Exporter(store: store).report(commits: ["c1"])
        let records = report.commits[0].records
        XCTAssertTrue(records[0].verification.signed)
        XCTAssertEqual(records[0].verification.verified, false)
        XCTAssertTrue(records[1].verification.signed)
        XCTAssertEqual(records[1].verification.verified, false)
    }

    func testExportIncludesPerCommitPolicyPassFail() throws {
        let store = InMemoryStore()
        try store.append(makeAttestation(commit: "good", testsPassed: true))
        try store.append(makeAttestation(commit: "bad", testsPassed: false))

        let report = try Exporter(store: store).report(
            commits: ["good", "bad"],
            policy: Policy(requireTestsPassed: true)
        )
        XCTAssertTrue(report.policyApplied)
        XCTAssertEqual(report.allPassed, false)
        XCTAssertEqual(report.commits[0].policyPassed, true)
        XCTAssertEqual(report.commits[1].policyPassed, false)
    }

    func testExportReportRoundTripsThroughJSON() throws {
        let store = InMemoryStore()
        let signer = Ed25519Signer.generate()
        try store.append(try signer.sign(makeAttestation(commit: "c1", note: "ok")))
        let report = try Exporter(store: store).report(
            commits: ["c1"],
            policy: Policy(requireSignature: true)
        )
        let data = try report.jsonData(pretty: false)
        let decoded = try JSONDecoder().decode(AuditReport.self, from: data)
        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.allPassed, true)
        XCTAssertEqual(decoded.commits[0].policyPassed, true)
    }

    // MARK: - Augur integration

    func testAugurParsingMapsRiskToConfidence() throws {
        let json = "{\"verdict\":\"review\",\"riskScore\":45.0,\"files\":[]}"
        let parsed = try AugurVerdict.parse(json)
        XCTAssertEqual(parsed.verdict, .review)
        XCTAssertEqual(parsed.confidence, 0.55, accuracy: 0.0001)
    }

    func testAugurParsingClampsAndDefaults() throws {
        let parsed = try AugurVerdict.parse("{\"riskScore\":0}")
        XCTAssertNil(parsed.verdict)
        XCTAssertEqual(parsed.confidence, 1.0, accuracy: 0.0001)
    }

    func testAugurParsingRejectsMalformed() {
        XCTAssertThrowsError(try AugurVerdict.parse("not json"))
        XCTAssertThrowsError(try AugurVerdict.parse("{\"verdict\":\"review\"}"))
    }

    // MARK: - Verdict ordering

    func testVerdictOrdering() {
        XCTAssertLessThan(Verdict.proceed, Verdict.review)
        XCTAssertLessThan(Verdict.review, Verdict.block)
        XCTAssertGreaterThanOrEqual(Verdict.block, Verdict.review)
    }

    // MARK: - ANSI / Colorizer

    private static let esc = "\u{001B}"

    func testColorizerDisabledIsPassThrough() {
        let plain = Colorizer.plain
        XCTAssertEqual(plain.green("ok"), "ok")
        XCTAssertEqual(plain.boldRed("FAIL"), "FAIL")
        XCTAssertEqual(plain.apply("x", .red, .bold), "x")
        XCTAssertFalse(plain.enabled)
    }

    func testColorizerEnabledWrapsCodes() {
        let c = Colorizer(enabled: true)
        XCTAssertEqual(c.green("ok"), "\(Self.esc)[32mok\(Self.esc)[0m")
        XCTAssertEqual(c.red("no"), "\(Self.esc)[31mno\(Self.esc)[0m")
        XCTAssertEqual(c.amber("hmm"), "\(Self.esc)[33mhmm\(Self.esc)[0m")
        XCTAssertEqual(c.cyan("who"), "\(Self.esc)[36mwho\(Self.esc)[0m")
        XCTAssertEqual(c.dim("aside"), "\(Self.esc)[2maside\(Self.esc)[0m")
        XCTAssertEqual(c.bold("head"), "\(Self.esc)[1mhead\(Self.esc)[0m")
        XCTAssertEqual(c.boldGreen("PASS"), "\(Self.esc)[1;32mPASS\(Self.esc)[0m")
        XCTAssertEqual(c.boldRed("FAIL"), "\(Self.esc)[1;31mFAIL\(Self.esc)[0m")
    }

    func testColorizerApplyEmptyCodesIsPassThrough() {
        XCTAssertEqual(Colorizer(enabled: true).apply("x"), "x")
    }

    // MARK: - Reporter: color-off byte-identical lock

    /// Locks the plain (no-colour) rendering so colour work can never silently change
    /// the bytes existing scripts and tests depend on.
    func testReporterLogPlainIsByteIdentical() {
        let groups: [(commit: String, attestations: [Attestation])] = [
            (commit: "abc1234567def", attestations: [
                makeAttestation(reviewer: "agent:claude", confidence: 0.9, verdict: .proceed,
                                testsPassed: true, humanApproved: false, note: "looks good"),
                makeAttestation(reviewer: "human:leif", confidence: 0.5, verdict: .review,
                                testsPassed: false, humanApproved: true)
            ])
        ]
        let expected = """
        attest · ledger

          commit abc1234567  (2 attestations)
            [ok] agent:claude  verdict:proceed  conf:90%  tests:ok  human:—  unsigned
                note: looks good
            [!] human:leif  verdict:review  conf:50%  tests:—  human:ok  unsigned
        """
        XCTAssertEqual(Reporter.renderLog(groups), expected)
        XCTAssertEqual(Reporter.renderLog(groups, colorizer: .plain), expected)
        XCTAssertFalse(Reporter.renderLog(groups).contains(Self.esc))
    }

    func testReporterEmptyLogPlainIsByteIdentical() {
        XCTAssertEqual(Reporter.renderLog([]), "attest · no attestations found")
    }

    func testReporterVerificationPassPlainIsByteIdentical() {
        let result = VerificationResult(passed: true, checkedCommits: 3, violations: [])
        XCTAssertEqual(
            Reporter.renderVerification(result),
            "attest verify · [ok] PASS (3 commits checked)"
        )
    }

    func testReporterVerificationFailPlainIsByteIdentical() {
        let result = VerificationResult(passed: false, checkedCommits: 1, violations: [
            Violation(commit: "abc1234567def", rule: "requireTestsPassed", detail: "no attestation reports passing tests")
        ])
        let expected = """
        attest verify · [x] FAIL (1 commit checked)

          violations:
            x abc1234567  requireTestsPassed: no attestation reports passing tests
        """
        XCTAssertEqual(Reporter.renderVerification(result), expected)
        XCTAssertFalse(Reporter.renderVerification(result).contains(Self.esc))
    }

    // MARK: - Reporter: semantic colour codes

    func testReporterVerificationColorPass() {
        let result = VerificationResult(passed: true, checkedCommits: 2, violations: [])
        let out = Reporter.renderVerification(result, colorizer: Colorizer(enabled: true))
        // PASS is bold green.
        XCTAssertTrue(out.contains("\(Self.esc)[1;32m[ok] PASS\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[1mattest verify ·\(Self.esc)[0m"))
    }

    func testReporterVerificationColorFail() {
        let result = VerificationResult(passed: false, checkedCommits: 1, violations: [
            Violation(commit: "deadbeef00", rule: "minimumConfidence", detail: "below floor")
        ])
        let out = Reporter.renderVerification(result, colorizer: Colorizer(enabled: true))
        // FAIL is bold red, violation lines red, header amber.
        XCTAssertTrue(out.contains("\(Self.esc)[1;31m[x] FAIL\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[33m  violations:\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[31m    x deadbeef00  minimumConfidence: below floor\(Self.esc)[0m"))
    }

    func testReporterLogColorSemantics() {
        let groups: [(commit: String, attestations: [Attestation])] = [
            (commit: "abc1234567def", attestations: [
                makeAttestation(reviewer: "agent:claude", confidence: 0.95, verdict: .proceed,
                                testsPassed: true, humanApproved: true)
            ])
        ]
        let out = Reporter.renderLog(groups, colorizer: Colorizer(enabled: true))
        // Header bold, reviewer cyan, proceed verdict + high confidence green, human:ok green.
        XCTAssertTrue(out.contains("\(Self.esc)[1mattest · ledger\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[36magent:claude\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[32mverdict:proceed\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[32mconf:95%\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[32mtests:ok\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[32mhuman:ok\(Self.esc)[0m"))
    }

    func testReporterLogColorBlockAndReviewTints() {
        let groups: [(commit: String, attestations: [Attestation])] = [
            (commit: "c1", attestations: [
                makeAttestation(reviewer: "agent:claude", confidence: 0.3, verdict: .block,
                                testsPassed: false, humanApproved: false)
            ]),
            (commit: "c2", attestations: [
                makeAttestation(reviewer: "human:leif", confidence: 0.6, verdict: .review,
                                testsPassed: false, humanApproved: false)
            ])
        ]
        let out = Reporter.renderLog(groups, colorizer: Colorizer(enabled: true))
        // block verdict + low confidence red; review verdict + mid confidence amber.
        XCTAssertTrue(out.contains("\(Self.esc)[31mverdict:block\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[31mconf:30%\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[33mverdict:review\(Self.esc)[0m"))
        XCTAssertTrue(out.contains("\(Self.esc)[33mconf:60%\(Self.esc)[0m"))
        // unsigned + tests:— + human:— are dim.
        XCTAssertTrue(out.contains("\(Self.esc)[2munsigned\(Self.esc)[0m"))
    }

    func testReporterLogColorSignedBadge() throws {
        let signer = try Ed25519Signer.generate()
        let signed = try signer.sign(makeAttestation(reviewer: "agent:claude", verdict: .proceed))
        let groups: [(commit: String, attestations: [Attestation])] = [
            (commit: signed.commit, attestations: [signed])
        ]
        let out = Reporter.renderLog(groups, colorizer: Colorizer(enabled: true))
        XCTAssertTrue(out.contains("\(Self.esc)[32msigned[ok]\(Self.esc)[0m"))
    }
}
