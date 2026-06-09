@preconcurrency import Foundation
import XCTest

/// End-to-end tests for `attest log` against a corrupt git note.
///
/// These drive the built `attest` binary so the CLI's stderr-warning and exit-code
/// contract is exercised for real, not just the library decode path. They locate the
/// product next to the test bundle (the standard SwiftPM layout) and skip cleanly when
/// the binary or `git` is unavailable, so they never block a library-only run.
final class LogCorruptNoteTests: XCTestCase {
    /// The directory holding built products (the test bundle's parent).
    private var productsDirectory: URL {
        Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }?
            .bundleURL.deletingLastPathComponent()
            ?? Bundle.main.bundleURL
    }

    private var attestBinary: URL {
        productsDirectory.appendingPathComponent("attest")
    }

    /// Runs a command and returns (exitCode, stdout, stderr).
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

        // Human-readable log: clean stderr warning, non-zero exit, clean stdout.
        let logResult = try run(attestBinary, ["log", "-C", repo.path])
        XCTAssertEqual(logResult.status, 1, "corrupt note must force a non-zero exit")
        XCTAssertTrue(
            logResult.stderr.contains("Malformed attestation record: invalid JSON"),
            "stderr should carry the clean malformed-record message, got: \(logResult.stderr)"
        )
        XCTAssertFalse(logResult.stderr.contains("DecodingError"), "must not leak Swift error internals")
        XCTAssertFalse(logResult.stdout.contains("DecodingError"), "stdout must stay clean")

        // JSON mode stays valid (empty array) and still exits non-zero.
        let jsonResult = try run(attestBinary, ["log", "-C", repo.path, "--json"])
        XCTAssertEqual(jsonResult.status, 1)
        XCTAssertEqual(jsonResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
    }
}
