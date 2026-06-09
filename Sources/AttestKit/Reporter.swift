@preconcurrency import Foundation

/// Renders attestations and verification results as human-readable terminal text.
///
/// Every renderer takes an optional `colorizer`. It defaults to ``Colorizer/plain`` so
/// existing call sites and tests produce byte-identical, unstyled output; pass an
/// `enabled` colorizer (the CLI decides, based on TTY / `NO_COLOR`) to add semantic ANSI
/// colour. Colour is *semantic*: green/amber/red mean pass/review/fail — it is not a
/// brand colour and deliberately is not all one hue.
public enum Reporter {
    // MARK: - Log

    /// Renders the attestations grouped by commit, newest commit first.
    /// - Parameters:
    ///   - groups: Commits paired with their attestations, newest commit first.
    ///   - colorizer: Styling gate; defaults to plain (no ANSI codes).
    /// - Returns: The human-readable ledger listing.
    public static func renderLog(
        _ groups: [(commit: String, attestations: [Attestation])],
        colorizer: Colorizer = .plain
    ) -> String {
        guard !groups.isEmpty else {
            return colorizer.dim("attest · no attestations found")
        }
        var lines: [String] = []
        lines.append(colorizer.bold("attest · ledger"))
        for group in groups {
            lines.append("")
            let count = group.attestations.count
            let header = "  commit \(shortSHA(group.commit))  (\(count) attestation\(count == 1 ? "" : "s"))"
            lines.append(colorizer.dim(header))
            for attestation in group.attestations {
                lines.append("    " + renderRow(attestation, colorizer: colorizer))
                if let note = attestation.note, !note.isEmpty {
                    lines.append(colorizer.dim("        note: \(note)"))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderRow(_ attestation: Attestation, colorizer: Colorizer) -> String {
        let verdictRaw = attestation.verdict.map { $0.rawValue } ?? "—"
        let verdict = colorize(verdict: attestation.verdict, text: "verdict:\(verdictRaw)", colorizer: colorizer)

        let confidenceValue = Int((attestation.confidence * 100).rounded())
        let confidence = colorize(confidence: attestation.confidence, text: "conf:\(confidenceValue)%", colorizer: colorizer)

        let tests = attestation.testsPassed
            ? colorizer.green("tests:ok")
            : colorizer.dim("tests:—")
        let human = attestation.humanApproved
            ? colorizer.green("human:ok")
            : colorizer.dim("human:—")
        let signed = signatureBadge(attestation, colorizer: colorizer)
        let badge = colorize(verdict: attestation.verdict, text: badge(attestation.verdict), colorizer: colorizer)
        let reviewer = colorizer.cyan(attestation.reviewer)
        return "\(badge) \(reviewer)  \(verdict)  \(confidence)  \(tests)  \(human)  \(signed)"
    }

    private static func signatureBadge(_ attestation: Attestation, colorizer: Colorizer) -> String {
        guard attestation.isSigned else {
            return colorizer.dim("unsigned")
        }
        return Ed25519Verifier.isValid(attestation)
            ? colorizer.green("signed[ok]")
            : colorizer.boldRed("signed[BAD]")
    }

    private static func badge(_ verdict: Verdict?) -> String {
        switch verdict {
        case .proceed: return "[ok]"
        case .review: return "[!]"
        case .block: return "[x]"
        case nil: return "[·]"
        }
    }

    /// Tints `text` by verdict severity: proceed → green, review → amber, block → red.
    private static func colorize(verdict: Verdict?, text: String, colorizer: Colorizer) -> String {
        switch verdict {
        case .proceed: return colorizer.green(text)
        case .review: return colorizer.amber(text)
        case .block: return colorizer.red(text)
        case nil: return colorizer.dim(text)
        }
    }

    /// Tints `text` by confidence: high → green, moderate → amber, low → red.
    private static func colorize(confidence: Double, text: String, colorizer: Colorizer) -> String {
        switch confidence {
        case 0.8...: return colorizer.green(text)
        case 0.5..<0.8: return colorizer.amber(text)
        default: return colorizer.red(text)
        }
    }

    // MARK: - Verification

    /// Renders a `VerificationResult` for terminal output.
    /// - Parameters:
    ///   - result: The verification outcome to render.
    ///   - colorizer: Styling gate; defaults to plain (no ANSI codes).
    /// - Returns: The human-readable verification summary.
    public static func renderVerification(
        _ result: VerificationResult,
        colorizer: Colorizer = .plain
    ) -> String {
        var lines: [String] = []
        let badge = result.passed
            ? colorizer.boldGreen("[ok] PASS")
            : colorizer.boldRed("[x] FAIL")
        let count = result.checkedCommits
        let suffix = colorizer.dim("(\(count) commit\(count == 1 ? "" : "s") checked)")
        lines.append("\(colorizer.bold("attest verify ·")) \(badge) \(suffix)")
        if !result.violations.isEmpty {
            lines.append("")
            lines.append(colorizer.amber("  violations:"))
            for violation in result.violations {
                let detail = "    x \(shortSHA(violation.commit))  \(violation.rule): \(violation.detail)"
                lines.append(colorizer.red(detail))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func shortSHA(_ sha: String) -> String {
        sha.count > 10 ? String(sha.prefix(10)) : sha
    }
}
