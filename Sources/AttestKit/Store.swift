@preconcurrency import Foundation

// MARK: - Store Protocol

/// Append-only storage for attestations, keyed by commit SHA.
///
/// Abstracted so the engine can be tested against an in-memory fake without
/// shelling out to git, mirroring how `augur` abstracts repository access behind
/// `RepositoryProbe`. Multiple attestations per commit are allowed.
public protocol AttestationStore: Sendable {
    /// Appends an attestation to the record for its commit.
    func append(_ attestation: Attestation) throws

    /// All attestations recorded for a commit, oldest first. Empty if none.
    func attestations(for commit: String) throws -> [Attestation]

    /// All commit SHAs that have at least one attestation.
    func attestedCommits() throws -> [String]
}

// MARK: - Encoding Helpers

/// Encodes/decodes the JSON-lines payload stored in a single git note.
///
/// Each note holds one attestation per line (JSON Lines), which makes appending
/// a matter of concatenating a line and keeps records individually parseable.
public enum AttestationCodec {
    /// Decodes a JSON-lines note body into attestations, skipping blank lines.
    public static func decodeLines(_ body: String) throws -> [Attestation] {
        let decoder = JSONDecoder()
        var result: [Attestation] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else {
                throw AttestError.malformedRecord("line is not valid UTF-8")
            }
            do {
                result.append(try decoder.decode(Attestation.self, from: data))
            } catch {
                // Surface a clean, stable message rather than leaking raw
                // DecodingError internals into user output.
                throw AttestError.malformedRecord("invalid JSON")
            }
        }
        return result
    }

    /// Encodes a single attestation as one canonical JSON line (no newline).
    public static func encodeLine(_ attestation: Attestation) throws -> String {
        try attestation.jsonString()
    }
}

// MARK: - In-Memory Store

/// A thread-safe in-memory `AttestationStore` for tests and dry runs.
public final class InMemoryStore: AttestationStore, @unchecked Sendable {
    // Justification for @unchecked: all mutable state is guarded by `lock`.
    private var storage: [String: [Attestation]] = [:]
    private let lock = NSLock()

    public init() {}

    public func append(_ attestation: Attestation) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[attestation.commit, default: []].append(attestation)
    }

    public func attestations(for commit: String) throws -> [Attestation] {
        lock.lock()
        defer { lock.unlock() }
        return storage[commit] ?? []
    }

    public func attestedCommits() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.keys).sorted()
    }
}
