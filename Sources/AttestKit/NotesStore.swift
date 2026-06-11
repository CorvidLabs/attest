@preconcurrency import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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

    /// Like `attestations(for:)`, but tolerant of note corruption: malformed
    /// lines are skipped and counted instead of failing the whole note, so one
    /// bad line cannot hide the valid records stored next to it.
    public func lenientAttestations(for commit: String) throws -> (attestations: [Attestation], malformedLines: Int) {
        guard let body = try noteBody(for: commit), !body.isEmpty else { return ([], 0) }
        return AttestationCodec.decodeLinesLeniently(body)
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
        guard commits.count > 1 else { return commits }
        // `git notes list` orders by SHA, which is meaningless to a reader.
        // Re-order into history order (newest first) without walking ancestry:
        // `--no-walk=sorted` shows exactly the given commits in reverse
        // chronological order, so attested commits on any branch are covered.
        let sorted = try run(["rev-list", "--no-walk=sorted"] + commits, allowFailure: true)
        let ordered = sorted
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Fall back to the unsorted listing if rev-list could not cover them all.
        return ordered.count == commits.count ? ordered : commits
    }

    // MARK: - Helpers

    /// The raw note body for a commit, or `nil` if no note exists.
    private func noteBody(for commit: String) throws -> String? {
        let result = try ProcessRunner.run(
            ["git", "-C", path, "notes", "--ref=\(Self.ref)", "show", commit]
        )
        // A missing note exits non-zero; treat that as "no attestations".
        guard result.status == 0 else { return nil }
        return result.output
    }

    /// Resolves a revision (e.g. `HEAD`, a tag, a short SHA) to a full SHA.
    /// - Throws: `AttestError.unknownRevision` when the revision does not name
    ///   a commit, rather than leaking git plumbing details.
    public func resolve(revision: String) throws -> String {
        let result = try ProcessRunner.run(
            ["git", "-C", path, "rev-parse", "--verify", "\(revision)^{commit}"]
        )
        guard result.status == 0 else {
            throw AttestError.unknownRevision(revision)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let result = try ProcessRunner.run(["git", "-C", path] + arguments)
        guard allowFailure || result.status == 0 else {
            throw AttestError.git(
                command: arguments.joined(separator: " "),
                status: result.status,
                message: Self.gitMessage(from: result.errorOutput)
            )
        }
        return result.output
    }

    /// The first line of git's stderr, with the `fatal:`/`error:` prefix
    /// stripped, so the user sees git's own explanation (e.g. "ambiguous
    /// argument 'x': unknown revision...") instead of bare plumbing details.
    private static func gitMessage(from stderr: String) -> String {
        guard let firstLine = stderr
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
        else { return "" }
        var message = firstLine.trimmingCharacters(in: .whitespaces)
        for prefix in ["fatal: ", "error: "] where message.hasPrefix(prefix) {
            message.removeFirst(prefix.count)
        }
        return message
    }
}

// MARK: - Process Runner

/// Spawns a child process via `posix_spawn` and reaps it with a synchronous
/// `waitpid`, capturing stdout and stderr through temporary files.
///
/// This deliberately avoids `Foundation.Process`. On Linux, `Foundation.Process`
/// monitors child termination asynchronously and can miss a fast-exiting child
/// (e.g. `git notes show`), leaving `waitUntilExit()` blocked forever; the
/// failure surfaces most often when the tool is driven from within a test
/// process. A synchronous `waitpid` reaps the child itself, so it cannot miss
/// the exit, and the behaviour is identical on macOS and Linux.
internal enum ProcessRunner {
    internal struct Result: Sendable {
        internal let status: Int32
        internal let output: String
        internal let errorOutput: String
    }

    internal static func run(_ argv: [String]) throws -> Result {
        let outputPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("attest-git-\(UUID().uuidString)")
        let errorPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("attest-git-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outputPath, contents: nil)
        FileManager.default.createFile(atPath: errorPath, contents: nil)
        defer {
            try? FileManager.default.removeItem(atPath: outputPath)
            try? FileManager.default.removeItem(atPath: errorPath)
        }

        let executable = "/usr/bin/env"
        let fullArgv = [executable] + argv

        // `posix_spawn_file_actions_t` is a struct on Glibc but an opaque
        // pointer on Darwin, so it must be declared differently per platform;
        // both are allocated by `posix_spawn_file_actions_init`.
        #if canImport(Darwin)
        var fileActions: posix_spawn_file_actions_t?
        #else
        var fileActions = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 1, outputPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&fileActions, 2, errorPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        let cArgs: [UnsafeMutablePointer<CChar>?] = fullArgv.map { strdup($0) } + [nil]
        defer { for case let arg? in cArgs { free(arg) } }

        // Pass the current environment (so `/usr/bin/env` finds git on PATH),
        // built from ProcessInfo to stay clear of the `environ` global, which
        // Swift does not expose uniformly across Darwin and Linux.
        let cEnv: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for case let entry? in cEnv { free(entry) } }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &fileActions, nil, cArgs, cEnv)
        guard spawnResult == 0 else {
            throw AttestError.git(
                command: argv.joined(separator: " "),
                status: spawnResult,
                message: "could not spawn the process"
            )
        }

        var rawStatus: Int32 = 0
        while waitpid(pid, &rawStatus, 0) == -1 && errno == EINTR { continue }
        let status: Int32 = (rawStatus & 0x7f) == 0 ? (rawStatus >> 8) & 0xff : rawStatus & 0x7f

        let data = (try? Data(contentsOf: URL(fileURLWithPath: outputPath))) ?? Data()
        let errorData = (try? Data(contentsOf: URL(fileURLWithPath: errorPath))) ?? Data()
        return Result(
            status: status,
            output: String(decoding: data, as: UTF8.self),
            errorOutput: String(decoding: errorData, as: UTF8.self)
        )
    }
}
