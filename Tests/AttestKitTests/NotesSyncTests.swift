@preconcurrency import Foundation
import XCTest
@testable import AttestKit

internal final class NotesSyncTests: XCTestCase {
    internal func testFetchMergesDivergentLedgersAndCleansTemporaryRef() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("attest-notes-sync-\(UUID().uuidString)")
        let remote = root.appendingPathComponent("remote.git")
        let firstClone = root.appendingPathComponent("first")
        let secondClone = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try git(["init", "-q", "--bare", remote.path])
        try git(["init", "-q", firstClone.path])
        try git(["-C", firstClone.path, "checkout", "-q", "-b", "main"])
        try configureUser(in: firstClone)
        try git(["-C", firstClone.path, "commit", "-q", "--allow-empty", "-m", "initial"])
        try git(["-C", firstClone.path, "remote", "add", "origin", remote.path])
        try git(["-C", firstClone.path, "push", "-q", "-u", "origin", "main"])

        let firstStore = NotesStore(path: firstClone.path)
        let commit = try firstStore.resolve(revision: "HEAD")
        XCTAssertFalse(try firstStore.fetch())
        XCTAssertThrowsError(try firstStore.push()) { error in
            XCTAssertEqual(
                error as? AttestError,
                .git(
                    command: "push",
                    status: 1,
                    message: "Local attestation ledger 'refs/notes/attest' does not exist. Record an attestation first."
                )
            )
        }
        try firstStore.append(attestation(commit: commit, reviewer: "agent:first", timestamp: 1))
        try firstStore.push()

        try git(["clone", "-q", "--branch", "main", remote.path, secondClone.path])
        try configureUser(in: secondClone)
        let secondStore = NotesStore(path: secondClone.path)
        try secondStore.fetch()
        try secondStore.append(attestation(commit: commit, reviewer: "agent:second", timestamp: 2))

        try firstStore.append(attestation(commit: commit, reviewer: "human:third", timestamp: 3))
        try firstStore.push()
        try secondStore.fetch()

        let reviewers = try secondStore.attestations(for: commit).map(\.reviewer)
        XCTAssertEqual(Set(reviewers), Set(["agent:first", "agent:second", "human:third"]))

        let temporaryRefs = try git([
            "-C",
            secondClone.path,
            "for-each-ref",
            "--format=%(refname)",
            "refs/notes/attest-fetch-",
        ])
        XCTAssertTrue(temporaryRefs.isEmpty)
    }

    private func attestation(commit: String, reviewer: String, timestamp: Int) -> Attestation {
        Attestation(
            commit: commit,
            reviewer: reviewer,
            confidence: 0.9,
            verdict: .proceed,
            timestamp: timestamp
        )
    }

    private func configureUser(in repository: URL) throws {
        _ = try git(["-C", repository.path, "config", "user.email", "test@example.com"])
        _ = try git(["-C", repository.path, "config", "user.name", "Test"])
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let result = try ProcessRunner.run(["git"] + arguments)
        guard result.status == 0 else {
            throw AttestError.git(
                command: arguments.joined(separator: " "),
                status: result.status,
                message: result.errorOutput
            )
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
