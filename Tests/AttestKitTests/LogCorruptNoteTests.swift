@preconcurrency import Foundation
import XCTest
@testable import AttestKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// End-to-end tests for `attest log` against a corrupt git note.
///
/// These drive the built `attest` binary so the CLI's stderr-warning and exit-code
/// contract is exercised for real, not just the library decode path. They locate the
/// product next to the test bundle (the standard SwiftPM layout) and skip cleanly when
/// the binary or `git` is unavailable, so they never block a library-only run.
final class LogCorruptNoteTests: XCTestCase {
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

    func testLogSurfacesCorruptNoteOnStderrAndExitsNonZero() throws {
        guard FileManager.default.fileExists(atPath: attestBinary.path) else {
            throw XCTSkip("attest binary not built at \(attestBinary.path)")
        }

        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("attest-log-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        try git(["init", "-q"], cwd: repo)
        try git(["config", "user.email", "t@t.t"], cwd: repo)
        try git(["config", "user.name", "t"], cwd: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "c1"], cwd: repo)

        let sha = try run(URL(fileURLWithPath: "/usr/bin/git"), ["rev-parse", "HEAD"], cwd: repo)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // A valid attestation first, then a corrupt line appended to the same note.
        let signed = try run(
            attestBinary,
            ["sign", "-C", repo.path, "--commit", sha, "--reviewer", "agent:claude",
             "--confidence", "0.9", "--verdict", "proceed"]
        )
        XCTAssertEqual(signed.status, 0, "sign should succeed: \(signed.stderr)")

        try git(["notes", "--ref=attest", "append", "-m", "{ not json }", sha], cwd: repo)

        // Human-readable log: clean stderr warning, non-zero exit, and the valid
        // record from the same note still prints — one bad line must not hide it.
        let logResult = try run(attestBinary, ["log", "-C", repo.path])
        XCTAssertEqual(logResult.status, 1, "corrupt note must force a non-zero exit")
        XCTAssertTrue(
            logResult.stderr.contains("skipped 1 malformed record line"),
            "stderr should carry the clean skipped-line warning, got: \(logResult.stderr)"
        )
        XCTAssertFalse(logResult.stderr.contains("DecodingError"), "must not leak Swift error internals")
        XCTAssertFalse(logResult.stdout.contains("DecodingError"), "stdout must stay clean")
        XCTAssertTrue(
            logResult.stdout.contains("agent:claude"),
            "the valid record next to the corrupt line must still be listed, got: \(logResult.stdout)"
        )

        // JSON mode stays valid, includes the readable record, and exits non-zero.
        let jsonResult = try run(attestBinary, ["log", "-C", repo.path, "--json"])
        XCTAssertEqual(jsonResult.status, 1)
        XCTAssertTrue(
            jsonResult.stdout.contains("\"reviewer\":\"agent:claude\""),
            "JSON output should include the readable record, got: \(jsonResult.stdout)"
        )
        XCTAssertFalse(jsonResult.stderr.contains("DecodingError"))
    }
}
