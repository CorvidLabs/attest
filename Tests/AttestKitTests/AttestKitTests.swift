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

    func testPolicyDecodesFromJSON() throws {
        let json = """
        { "requireTestsPassed": true, "requireHumanApprovalWhenVerdictAtLeast": "review", "minimumConfidence": 0.7 }
        """
        let policy = try JSONDecoder().decode(Policy.self, from: Data(json.utf8))
        XCTAssertTrue(policy.requireTestsPassed)
        XCTAssertEqual(policy.requireHumanApprovalWhenVerdictAtLeast, .review)
        XCTAssertEqual(policy.minimumConfidence, 0.7)
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
}
