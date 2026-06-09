@preconcurrency import Foundation
import XCTest

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
        Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }?
            .bundleURL.deletingLastPathComponent()
            ?? Bundle.main.bundleURL
    }

    private var attestBinary: URL {
        productsDirectory.appendingPathComponent("attest")
    }

    @discardableResult
    private func run(
        _ executable: URL,
        _ arguments: [String],
        cwd: URL? = nil
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
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
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }
}
