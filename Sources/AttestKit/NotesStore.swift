@preconcurrency import Foundation

// MARK: - Git Notes Store

/// An `AttestationStore` backed by git notes under a dedicated ref.
///
/// Attestations live in `refs/notes/attest`, keyed by commit SHA, stored as
/// JSON Lines (one attestation per line) so multiple attestations can accrue on
/// the same commit. Git notes are portable across every git host, travel with
/// `git push origin "refs/notes/*"`, and never touch the working tree.
public struct NotesStore: AttestationStore {
    /// The notes ref name passed to `git notes --ref=<ref>`.
    public static let ref = "attest"

    private let path: String

    public init(path: String = ".") {
        self.path = path
    }

    /// Confirms `path` is inside a git work tree, throwing otherwise.
    public func validate() throws {
        let output = try run(["rev-parse", "--is-inside-work-tree"], allowFailure: true)
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw AttestError.notARepository(path)
        }
    }

    // MARK: - AttestationStore

    public func append(_ attestation: Attestation) throws {
        let existing = try noteBody(for: attestation.commit)
        let line = try AttestationCodec.encodeLine(attestation)
        let body: String
        if let existing, !existing.isEmpty {
            body = existing.trimmingCharacters(in: .newlines) + "\n" + line
        } else {
            body = line
        }
        // `add -f` overwrites the whole note; we rewrite the accumulated body so
        // multiple attestations per commit append cleanly.
        try run(["notes", "--ref=\(Self.ref)", "add", "-f", "-m", body, attestation.commit])
    }

    public func attestations(for commit: String) throws -> [Attestation] {
        guard let body = try noteBody(for: commit), !body.isEmpty else { return [] }
        return try AttestationCodec.decodeLines(body)
    }

    public func attestedCommits() throws -> [String] {
        let output = try run(["notes", "--ref=\(Self.ref)", "list"], allowFailure: true)
        var commits: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            // `git notes list` prints "<note-object-sha> <annotated-commit-sha>".
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count == 2 {
                commits.append(String(fields[1]))
            }
        }
        return commits
    }

    // MARK: - Helpers

    /// The raw note body for a commit, or `nil` if no note exists.
    private func noteBody(for commit: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path, "notes", "--ref=\(Self.ref)", "show", commit]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // A missing note exits non-zero; treat that as "no attestations".
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Resolves a revision (e.g. `HEAD`, a tag, a short SHA) to a full SHA.
    public func resolve(revision: String) throws -> String {
        let output = try run(["rev-parse", "--verify", "\(revision)^{commit}"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The commit SHAs in a range (e.g. `main..HEAD`), oldest first.
    public func commits(inRange range: String) throws -> [String] {
        let output = try run(["rev-list", "--reverse", range])
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Process

    @discardableResult
    private func run(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path] + arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice  // avoid pipe-buffer deadlock
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowFailure || process.terminationStatus == 0 else {
            throw AttestError.git(command: arguments.joined(separator: " "), status: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
