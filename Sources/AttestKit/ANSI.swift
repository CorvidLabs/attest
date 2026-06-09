@preconcurrency import Foundation

// MARK: - ANSIColor

/// A small, dependency-free set of ANSI SGR (Select Graphic Rendition) codes used to
/// style terminal output.
///
/// `attest` keeps `AttestKit` limited to Apple packages, so colour is implemented as
/// plain Foundation strings rather than a third-party library. The palette here is the
/// *semantic* terminal palette: green/amber/red carry meaning (pass/review/fail) and are
/// independent of the website's brand colour.
public enum ANSIColor: String, Sendable {
    /// Reset all styling back to the terminal default.
    case reset = "0"
    /// Bold / increased intensity.
    case bold = "1"
    /// Dim / decreased intensity, for secondary text.
    case dim = "2"
    /// Red — failure, blocking verdicts, violations.
    case red = "31"
    /// Amber (rendered as yellow) — "review" verdicts and soft warnings.
    case amber = "33"
    /// Green — passing checks, "proceed" verdicts, valid signatures.
    case green = "32"
    /// Cyan — reviewer identities and informational accents.
    case cyan = "36"
}

// MARK: - Colorizer

/// Wraps strings in ANSI SGR escape codes when colour is enabled.
///
/// A `Colorizer` is gated by a single `enabled` flag decided by the caller (typically the
/// CLI, based on whether stdout is a TTY and `NO_COLOR` is unset). When `enabled` is
/// `false`, every method returns its input unchanged, so non-TTY, piped, and `--json`
/// output stays byte-identical to the plain rendering.
public struct Colorizer: Sendable {
    /// Whether styling is applied. When `false`, all methods are pass-throughs.
    public let enabled: Bool

    /// The ANSI Control Sequence Introducer.
    private static let csi = "\u{001B}["

    /// Creates a colorizer.
    /// - Parameter enabled: When `false`, every styling method returns its input unchanged.
    public init(enabled: Bool) {
        self.enabled = enabled
    }

    /// A colorizer that never emits escape codes.
    public static let plain = Colorizer(enabled: false)

    // MARK: - Core

    /// Wraps `text` in the given SGR codes, resetting afterwards.
    /// - Parameters:
    ///   - text: The string to style.
    ///   - codes: One or more SGR codes to apply.
    /// - Returns: The styled string, or `text` unchanged when styling is disabled.
    public func apply(_ text: String, _ codes: ANSIColor...) -> String {
        guard enabled, !codes.isEmpty else { return text }
        let sequence = codes.map(\.rawValue).joined(separator: ";")
        return "\(Self.csi)\(sequence)m\(text)\(Self.csi)\(ANSIColor.reset.rawValue)m"
    }

    // MARK: - Semantic helpers

    /// Styles `text` in red.
    public func red(_ text: String) -> String { apply(text, .red) }

    /// Styles `text` in amber.
    public func amber(_ text: String) -> String { apply(text, .amber) }

    /// Styles `text` in green.
    public func green(_ text: String) -> String { apply(text, .green) }

    /// Styles `text` in cyan.
    public func cyan(_ text: String) -> String { apply(text, .cyan) }

    /// Renders `text` dim, for secondary detail.
    public func dim(_ text: String) -> String { apply(text, .dim) }

    /// Renders `text` bold, for headers and headline verdicts.
    public func bold(_ text: String) -> String { apply(text, .bold) }

    /// Renders `text` bold and green, for emphatic success (e.g. `PASS`).
    public func boldGreen(_ text: String) -> String { apply(text, .bold, .green) }

    /// Renders `text` bold and red, for emphatic failure (e.g. `FAIL`).
    public func boldRed(_ text: String) -> String { apply(text, .bold, .red) }
}
