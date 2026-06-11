@preconcurrency import Foundation
import XCTest
@testable import AttestKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// End-to-end test for the cross-commit signature replay defense.
///
/// This drives the built `attest` binary against a throwaway git repo: it signs a record
/// for commit A, then copies A's note blob verbatim onto commit B (exactly what an attacker
/// with write access to `refs/notes/attest` can do) and proves the relocated record no longer
/// satisfies a strict policy on B. The signature still validates over A's unchanged bytes, but
/// the verifier binds each record to the note key it is filed under, so the transplanted record
/// is not evidence for B. The test skips cleanly when the binary or `git` is unavailable.
final class CrossCommitReplayTests: XCTestCase {
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

    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    @discardableResult
    private func git(_ arguments: [String], cwd: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: gitURL.path) else {
            throw XCTSkip("git not available")
        }
        let result = try run(gitURL, arguments, cwd: cwd)
        if result.status != 0 {
            throw XCTSkip("git \(arguments.joined(separator: " ")) failed: \(result.stderr)")
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testReplayedSignedAttestationFailsStrictPolicyOnTargetCommit() throws {
        guard FileManager.default.fileExists(atPath: attestBinary.path) else {
            throw XCTSkip("attest binary not built at \(attestBinary.path)")
        }

        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("attest-replay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        try git(["init", "-q"], cwd: repo)
        try git(["config", "user.email", "t@t.t"], cwd: repo)
        try git(["config", "user.name", "t"], cwd: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "commit A"], cwd: repo)
        let commitA = try git(["rev-parse", "HEAD"], cwd: repo)
        try git(["commit", "-q", "--allow-empty", "-m", "commit B"], cwd: repo)
        let commitB = try git(["rev-parse", "HEAD"], cwd: repo)

        // Generate a key in an isolated config dir so the test never touches a real key.
        let configHome = repo.appendingPathComponent("xdg-config")
        try FileManager.default.createDirectory(at: configHome, withIntermediateDirectories: true)
        var env = ProcessInfo.processInfo.environment
        env["XDG_CONFIG_HOME"] = configHome.path
        let keygen = try runWithEnv(attestBinary, ["keygen", "--force"], env: env)
        XCTAssertEqual(keygen.status, 0, "keygen should succeed: \(keygen.stderr)")
        let pub = keygen.stdout
            .split(separator: "\n")
            .first { $0.hasPrefix("public key: ") }
            .map { $0.replacingOccurrences(of: "public key: ", with: "") }
        let publicKey = try XCTUnwrap(pub, "keygen must print a public key")

        // A strict policy: require a signed, trusted, high-confidence attestation.
        let policy = """
        { "requireAttestation": true, "requireSignature": true, "minimumConfidence": 0.9, \
        "trustedKeys": ["\(publicKey)"] }
        """
        let policyURL = repo.appendingPathComponent(".attest.json")
        try Data(policy.utf8).write(to: policyURL)

        // Sign a genuine attestation for commit A.
        let sign = try runWithEnv(
            attestBinary,
            ["sign", "-C", repo.path, "--commit", commitA, "--reviewer", "human:leif",
             "--confidence", "0.95", "--verdict", "review", "--sign"],
            env: env
        )
        XCTAssertEqual(sign.status, 0, "sign should succeed: \(sign.stderr)")

        // Commit A passes the strict policy.
        let verifyA = try run(attestBinary, ["verify", "-C", repo.path, "--commit", commitA, "--policy", policyURL.path])
        XCTAssertEqual(verifyA.status, 0, "commit A should pass: \(verifyA.stdout)\(verifyA.stderr)")

        // Replay: copy A's note blob verbatim onto commit B.
        let listing = try git(["notes", "--ref=attest", "list", commitA], cwd: repo)
        let blob = try XCTUnwrap(listing.split(separator: " ").first.map(String.init), "could not read note blob for A")
        try git(["notes", "--ref=attest", "add", "-f", "-C", blob, commitB], cwd: repo)

        // Commit B must now FAIL the strict policy (exit 1): the relocated record is discarded.
        let verifyB = try run(attestBinary, ["verify", "-C", repo.path, "--commit", commitB, "--policy", policyURL.path])
        XCTAssertEqual(verifyB.status, 1, "replayed record must not let commit B pass: \(verifyB.stdout)")
        XCTAssertTrue(verifyB.stdout.contains("FAIL"), "verify B should render FAIL")

        // `attest log` marks the relocated record as commit-mismatch, warns on stderr, exits 1.
        let logB = try run(attestBinary, ["log", "-C", repo.path, "--commit", commitB])
        XCTAssertEqual(logB.status, 1, "log must exit non-zero on a mismatched record")
        XCTAssertTrue(logB.stdout.contains("commit-mismatch"), "log should mark the relocated record")
        XCTAssertFalse(logB.stdout.contains("signed[ok]"), "a relocated record must not render as signed[ok]")
        XCTAssertTrue(logB.stderr.contains("cross-commit mismatch"), "log should warn on stderr")
    }

    @discardableResult
    private func runWithEnv(
        _ executable: URL,
        _ arguments: [String],
        env: [String: String]
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

        let execPath = executable.path
        let spawnArgv = [executable.path] + arguments

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
            env.map { strdup("\($0.key)=\($0.value)") } + [nil]
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
}
