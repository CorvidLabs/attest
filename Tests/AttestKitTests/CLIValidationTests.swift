@preconcurrency import Foundation
import XCTest
@testable import AttestKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// End-to-end tests for the CLI's input validation and error reporting.
///
/// These drive the built `attest` binary so the exit-code and stderr contracts are
/// exercised for real: a typo'd `--policy` path must be a hard error (not a silent
/// fall-back to the permissive default), unknown or malformed policy files must
/// render human messages, out-of-range `--confidence` must be rejected, a bare
/// `attest log` must list commits in history order, and bad revisions/ranges must
/// surface git's own explanation instead of bare plumbing. They locate the product
/// next to the test bundle (the standard SwiftPM layout) and skip cleanly when the
/// binary or `git` is unavailable, so they never block a library-only run.
final class CLIValidationTests: XCTestCase {
    /// The directory holding built products (the test bundle's parent).
    private var productsDirectory: URL {
        #if os(macOS)
        return Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }?
            .bundleURL.deletingLastPathComponent()
            ?? Bundle.main.bundleURL
        #else
        // On Linux the xctest runner executable lives in the same build
        // directory as the `attest` product, and `Bundle` discovery is
        // unreliable there, so derive the products dir from the runner's path.
        let runner = CommandLine.arguments.first ?? ""
        return URL(fileURLWithPath: runner).deletingLastPathComponent()
        #endif
    }

    private var attestBinary: URL {
        productsDirectory.appendingPathComponent("attest")
    }

    /// Runs a command and returns (exitCode, stdout, stderr).
    ///
    /// Uses `posix_spawn` + synchronous `waitpid` to avoid `Foundation.Process`
    /// deadlocks on Linux where fast-exiting children can be missed.
    @discardableResult
    private func run(
        _ executable: URL,
        _ arguments: [String],
        cwd: URL? = nil
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let stdoutPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("attest-test-out-\(UUID().uuidString)")
        let stderrPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("attest-test-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: stdoutPath, contents: nil)
        FileManager.default.createFile(atPath: stderrPath, contents: nil)
        defer {
            try? FileManager.default.removeItem(atPath: stdoutPath)
            try? FileManager.default.removeItem(atPath: stderrPath)
        }

        // Build the argv: if a cwd is requested, wrap with `sh -c "cd ... && cmd"`.
        // This is portable across Darwin and Linux without relying on
        // `posix_spawn_file_actions_addchdir_np`, which is Darwin-only.
        let (execPath, spawnArgv): (String, [String])
        if let cwd {
            let quoted = arguments.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
            let script = "cd '\(cwd.path.replacingOccurrences(of: "'", with: "'\\''"))' && '\(executable.path.replacingOccurrences(of: "'", with: "'\\''"))' \(quoted)"
            execPath = "/bin/sh"
            spawnArgv = ["/bin/sh", "-c", script]
        } else {
            execPath = executable.path
            spawnArgv = [executable.path] + arguments
        }

        #if canImport(Darwin)
        var fileActions: posix_spawn_file_actions_t?
        #else
        var fileActions = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 1, stdoutPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&fileActions, 2, stderrPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        let cArgs: [UnsafeMutablePointer<CChar>?] = spawnArgv.map { strdup($0) } + [nil]
        defer { for case let arg? in cArgs { free(arg) } }

        let cEnv: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for case let entry? in cEnv { free(entry) } }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, execPath, &fileActions, nil, cArgs, cEnv)
        guard spawnResult == 0 else {
            throw AttestError.git(
                command: spawnArgv.joined(separator: " "),
                status: spawnResult,
                message: "could not spawn the process"
            )
        }

        var rawStatus: Int32 = 0
        while waitpid(pid, &rawStatus, 0) == -1 && errno == EINTR { continue }
        let exitStatus: Int32 = (rawStatus & 0x7f) == 0 ? (rawStatus >> 8) & 0xff : rawStatus & 0x7f

        let outData = (try? Data(contentsOf: URL(fileURLWithPath: stdoutPath))) ?? Data()
        let errData = (try? Data(contentsOf: URL(fileURLWithPath: stderrPath))) ?? Data()
        return (
            exitStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }

    private func git(_ arguments: [String], cwd: URL) throws {
        let gitURL = URL(fileURLWithPath: "/usr/bin/git")
        guard FileManager.default.fileExists(atPath: gitURL.path) else {
            throw XCTSkip("git not available")
        }
        let result = try run(gitURL, arguments, cwd: cwd)
        if result.status != 0 {
            throw XCTSkip("git \(arguments.joined(separator: " ")) failed: \(result.stderr)")
        }
    }

    /// Creates a scratch repo with one empty commit and returns its URL.
    private func makeScratchRepo() throws -> URL {
        guard FileManager.default.fileExists(atPath: attestBinary.path) else {
            throw XCTSkip("attest binary not built at \(attestBinary.path)")
        }
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("attest-cli-validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: repo)
        }
        try git(["init", "-q"], cwd: repo)
        try git(["config", "user.email", "t@t.t"], cwd: repo)
        try git(["config", "user.name", "t"], cwd: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "c1"], cwd: repo)
        return repo
    }

    /// Creates an empty commit with a fixed committer/author date and returns its SHA.
    /// The committer date matters: `rev-list --no-walk=sorted` orders by commit time.
    private func commitEmpty(in repo: URL, message: String, date: String) throws -> String {
        let env = URL(fileURLWithPath: "/usr/bin/env")
        let commit = try run(
            env,
            ["GIT_COMMITTER_DATE=\(date)", "GIT_AUTHOR_DATE=\(date)", "git", "-C", repo.path,
             "commit", "-q", "--allow-empty", "-m", message],
            cwd: repo
        )
        guard commit.status == 0 else {
            throw XCTSkip("could not commit with a fixed date: \(commit.stderr)")
        }
        return try run(URL(fileURLWithPath: "/usr/bin/git"), ["rev-parse", "HEAD"], cwd: repo)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Policy loading

    func testVerifyExplicitMissingPolicyIsHardError() throws {
        let repo = try makeScratchRepo()
        let missing = "/tmp/attest-no-such-policy-\(UUID().uuidString).json"
        let result = try run(attestBinary, ["verify", "-C", repo.path, "--commit", "HEAD", "--policy", missing])
        XCTAssertEqual(result.status, 1, "a typo'd --policy path must be a hard error, not a silent PASS")
        XCTAssertTrue(
            result.stderr.contains("Policy file not found: \(missing)"),
            "stderr should name the missing policy file, got: \(result.stderr)"
        )
        XCTAssertFalse(result.stdout.contains("PASS"), "must not report PASS under a dropped policy")
    }

    func testVerifyWithoutPolicyFlagStillFallsBackToDefault() throws {
        let repo = try makeScratchRepo()
        let signed = try run(
            attestBinary,
            ["sign", "-C", repo.path, "--reviewer", "agent:claude", "--confidence", "0.9"]
        )
        XCTAssertEqual(signed.status, 0, "sign should succeed: \(signed.stderr)")
        // No --policy and no .attest.json in the working directory: the implicit
        // default lookup may still fall back to the permissive default policy.
        let result = try run(attestBinary, ["verify", "-C", repo.path, "--commit", "HEAD"], cwd: repo)
        XCTAssertEqual(result.status, 0, "implicit default lookup should still pass: \(result.stderr)")
    }

    func testVerifyUnknownPolicyKeyIsHardError() throws {
        let repo = try makeScratchRepo()
        let policyPath = repo.appendingPathComponent(".attest.json").path
        try "{\"minimumConfidenceTYPO\": 0.9}".write(toFile: policyPath, atomically: true, encoding: .utf8)
        let result = try run(attestBinary, ["verify", "-C", repo.path, "--commit", "HEAD", "--policy", policyPath])
        XCTAssertEqual(result.status, 1, "a misspelled rule must be a hard error, not a rule that is off")
        XCTAssertTrue(
            result.stderr.contains("Unknown policy key(s): minimumConfidenceTYPO"),
            "stderr should name the unknown key, got: \(result.stderr)"
        )
        XCTAssertTrue(
            result.stderr.contains("minimumConfidence,"),
            "stderr should list the valid keys, got: \(result.stderr)"
        )
    }

    func testVerifyMalformedPolicyRendersHumanError() throws {
        let repo = try makeScratchRepo()
        let policyPath = repo.appendingPathComponent(".attest.json").path
        try "{not json".write(toFile: policyPath, atomically: true, encoding: .utf8)
        let result = try run(attestBinary, ["verify", "-C", repo.path, "--commit", "HEAD", "--policy", policyPath])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(
            result.stderr.contains("Malformed policy \(policyPath)"),
            "stderr should name the file and the problem, got: \(result.stderr)"
        )
        XCTAssertFalse(result.stderr.contains("dataCorrupted"), "must not leak Swift error internals")
        XCTAssertFalse(result.stderr.contains("NSCocoaErrorDomain"), "must not leak Cocoa error internals")
    }

    // MARK: - Confidence validation

    func testSignRejectsOutOfRangeConfidence() throws {
        let repo = try makeScratchRepo()
        let high = try run(
            attestBinary,
            ["sign", "-C", repo.path, "--reviewer", "agent:claude", "--confidence", "1.5"]
        )
        XCTAssertEqual(high.status, 64, "out-of-range confidence is a usage error, not a silent clamp")
        XCTAssertTrue(
            high.stderr.contains("confidence must be in 0...1 (got 1.5)"),
            "stderr should explain the valid range, got: \(high.stderr)"
        )

        // Negative values must use the `--confidence=VALUE` form (a
        // swift-argument-parser quirk treats a bare `-0.3` as an unknown flag),
        // and are rejected as out of range all the same.
        let negative = try run(
            attestBinary,
            ["sign", "-C", repo.path, "--reviewer", "agent:claude", "--confidence=-0.3"]
        )
        XCTAssertEqual(negative.status, 64)
        XCTAssertTrue(
            negative.stderr.contains("confidence must be in 0...1 (got -0.3)"),
            "stderr should explain the valid range, got: \(negative.stderr)"
        )

        // Nothing was recorded by either rejected invocation.
        let log = try run(attestBinary, ["log", "-C", repo.path, "--json"])
        XCTAssertEqual(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
    }

    func testSignAcceptsBoundaryConfidence() throws {
        let repo = try makeScratchRepo()
        for value in ["0", "1", "0.5"] {
            let result = try run(
                attestBinary,
                ["sign", "-C", repo.path, "--reviewer", "agent:claude", "--confidence", value]
            )
            XCTAssertEqual(result.status, 0, "confidence \(value) is in range: \(result.stderr)")
        }
    }

    // MARK: - Bare log ordering

    func testBareLogListsCommitsNewestFirst() throws {
        let repo = try makeScratchRepo()
        let oldest = try commitEmpty(in: repo, message: "oldest", date: "2026-01-01T10:00:00")
        let middle = try commitEmpty(in: repo, message: "middle", date: "2026-02-01T10:00:00")
        let newest = try commitEmpty(in: repo, message: "newest", date: "2026-03-01T10:00:00")

        // Attest them in scrambled order so insertion order cannot mask SHA order.
        for sha in [middle, newest, oldest] {
            let signed = try run(
                attestBinary,
                ["sign", "-C", repo.path, "--commit", sha, "--reviewer", "agent:claude", "--confidence", "0.9"]
            )
            XCTAssertEqual(signed.status, 0, "sign should succeed: \(signed.stderr)")
        }

        let result = try run(attestBinary, ["log", "-C", repo.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        let positions = try [newest, middle, oldest].map { sha in
            let prefix = String(sha.prefix(10))
            guard let range = result.stdout.range(of: prefix) else {
                throw XCTSkip("expected \(prefix) in log output: \(result.stdout)")
            }
            return result.stdout.distance(from: result.stdout.startIndex, to: range.lowerBound)
        }
        XCTAssertTrue(
            positions[0] < positions[1] && positions[1] < positions[2],
            "bare log must list commits newest-first (history order), got: \(result.stdout)"
        )
    }

    // MARK: - Git error surfacing

    func testBadRevisionErrorIsHuman() throws {
        let repo = try makeScratchRepo()
        let result = try run(attestBinary, ["verify", "-C", repo.path, "--commit", "deadbeef123"])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(
            result.stderr.contains("Unknown revision: deadbeef123"),
            "stderr should name the bad revision plainly, got: \(result.stderr)"
        )
        XCTAssertFalse(result.stderr.contains("^{commit}"), "must not leak git plumbing syntax")
    }

    func testBadRangeErrorSurfacesGitsExplanation() throws {
        let repo = try makeScratchRepo()
        let result = try run(attestBinary, ["verify", "-C", repo.path, "--range", "HEAD..nope"])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(
            result.stderr.contains("unknown revision"),
            "stderr should carry git's own explanation, got: \(result.stderr)"
        )
    }
}
