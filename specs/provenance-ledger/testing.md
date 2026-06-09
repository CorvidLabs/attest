# Testing — Provenance Ledger

## Strategy

The engine is tested through an in-memory `InMemoryStore` conforming to `AttestationStore`,
so recording, reading, and policy evaluation are verified without invoking `git`.
Cryptographic round-trips use freshly generated keypairs; `timestamp` is fixed for
deterministic canonical bytes.

## Coverage (Tests/AttestKitTests/AttestKitTests.swift)

| Test | Asserts |
|------|---------|
| `testCanonicalSerializationIsDeterministic` | Repeated canonicalization is byte-identical with sorted keys. |
| `testCanonicalExcludesSignatureFields` | Signed and unsigned copies share canonical bytes; no signature/publicKey in them. |
| `testConfidenceIsClamped` | `confidence` is clamped to `0...1`. |
| `testSignVerifyRoundTrip` | A signed attestation verifies and embeds the signer's public key. |
| `testVerifyFailsOnTamperedContent` | Mutating a signed field fails verification. |
| `testVerifyFailsOnUnexpectedPublicKey` | A mismatched expected key fails verification. |
| `testVerifyUnsignedThrowsSignatureMissing` | Verifying an unsigned record throws `signatureMissing`. |
| `testSignerRoundTripsThroughBase64Key` | A signer reloaded from its base64 key signs verifiably. |
| `testCodecRoundTrip` / `testCodecRejectsMalformedLine` | JSON-Lines note encode/decode and malformed-line rejection. |
| `testInMemoryStoreAppendsMultiplePerCommit` | Multiple attestations accrue on one commit. |
| `testRecordWithSignerStoresSignedRecord` | `Attest.record` signs when given a signer. |
| `testDefaultPolicyRequiresAttestation` | The default policy fails a commit with no attestations. |
| `testPolicyPassesWithSatisfyingAttestation` | A satisfying attestation passes the policy. |
| `testPolicyRequireTestsPassedFails` | `requireTestsPassed` fails without a passing-tests record. |
| `testHumanApprovalRequiredWhenVerdictAtLeastReview` | Conditional human-approval rule fires only at/above the threshold. |
| `testRequireSignaturePolicy` | `requireSignature` passes only with a valid signed record. |
| `testCommitBindingAttestationOnItsOwnCommitStillPasses` | A signed record on the commit it names still passes a strict policy. |
| `testCommitBindingRejectsSignedRecordReplayedOntoAnotherCommit` | A signed record relocated onto another commit is discarded; `requireAttestation`/`requireSignature`/`minimumConfidence` all fail. |
| `testCommitBindingMismatchedRecordDoesNotSatisfyPinningOrTrustedKeys` | A relocated record cannot satisfy `signerPinning`/`trustedKeys`/`requireSignatureWhenVerdictAtLeast`. |
| `testCommitBindingExporterMarksMismatchAndDoesNotReportVerified` | The exporter marks a relocated record `commitMatches: false` / `verified: false`, commit fails policy. |
| `testCommitBindingReporterRendersCommitMismatchBadge` | `attest log` renders a relocated record as `commit-mismatch`, not `signed[ok]`. |
| `testMinimumConfidencePolicy` | `minimumConfidence` gates on the strongest attestation. |
| `testPolicyDecodesFromJSON` / `testEmptyPolicyJSONUsesDefaults` | Policy JSON decoding and permissive defaults. |
| `testAugurParsingMapsRiskToConfidence` | augur `riskScore` 45 → confidence 0.55, verdict copied. |
| `testAugurParsingClampsAndDefaults` | Missing verdict is `nil`; risk 0 → confidence 1.0. |
| `testAugurParsingRejectsMalformed` | Non-object / missing `riskScore` input throws. |
| `testVerdictOrdering` | `proceed < review < block`. |

## End-to-end (Tests/AttestKitTests/CrossCommitReplayTests.swift)

| Test | Asserts |
|------|---------|
| `testReplayedSignedAttestationFailsStrictPolicyOnTargetCommit` | Against a temp repo: a signed record for commit A, copied verbatim onto commit B's note, no longer passes B's strict policy (`attest verify` exits 1); `attest log` renders `commit-mismatch` with a stderr warning and exit 1; the record on its own commit A still passes. |

## Manual / dogfood

- `examples/01-basic-attestation.sh` — init a scratch repo, sign, log.
- `examples/02-augur-integration.sh` — `augur check --json | attest sign --from-augur -`.
- `examples/03-policy-gate.sh` — `.attest.json` showing a passing and a failing `verify`.
