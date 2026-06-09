@preconcurrency import Foundation

/// Renders attestations and verification results as human-readable terminal text.
public enum Reporter {
    // MARK: - Log

    /// Renders the attestations grouped by commit, newest commit first.
    public static func renderLog(_ groups: [(commit: String, attestations: [Attestation])]) -> String {
        guard !groups.isEmpty else {
            return "attest · no attestations found"
        }
        var lines: [String] = []
        lines.append("attest · ledger")
        for group in groups {
            lines.append("")
            lines.append("  commit \(shortSHA(group.commit))  (\(group.attestations.count) attestation\(group.attestations.count == 1 ? "" : "s"))")
            for attestation in group.attestations {
                lines.append("    " + renderRow(attestation))
                if let note = attestation.note, !note.isEmpty {
                    lines.append("        note: \(note)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderRow(_ attestation: Attestation) -> String {
        let verdict = attestation.verdict.map { $0.rawValue } ?? "—"
        let confidence = Int((attestation.confidence * 100).rounded())
        let tests = attestation.testsPassed ? "tests:ok" : "tests:—"
        let human = attestation.humanApproved ? "human:ok" : "human:—"
        let signed = attestation.isSigned ? signatureBadge(attestation) : "unsigned"
        return "\(badge(attestation.verdict)) \(attestation.reviewer)  verdict:\(verdict)  conf:\(confidence)%  \(tests)  \(human)  \(signed)"
    }

    private static func signatureBadge(_ attestation: Attestation) -> String {
        Ed25519Verifier.isValid(attestation) ? "signed[ok]" : "signed[BAD]"
    }

    private static func badge(_ verdict: Verdict?) -> String {
        switch verdict {
        case .proceed: return "[ok]"
        case .review: return "[!]"
        case .block: return "[x]"
        case nil: return "[·]"
        }
    }

    // MARK: - Verification

    /// Renders a `VerificationResult` for terminal output.
    public static func renderVerification(_ result: VerificationResult) -> String {
        var lines: [String] = []
        let badge = result.passed ? "[ok] PASS" : "[x] FAIL"
        lines.append("attest verify · \(badge) (\(result.checkedCommits) commit\(result.checkedCommits == 1 ? "" : "s") checked)")
        if !result.violations.isEmpty {
            lines.append("")
            lines.append("  violations:")
            for violation in result.violations {
                lines.append("    x \(shortSHA(violation.commit))  \(violation.rule): \(violation.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func shortSHA(_ sha: String) -> String {
        sha.count > 10 ? String(sha.prefix(10)) : sha
    }
}
