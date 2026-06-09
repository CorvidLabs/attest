@preconcurrency import Foundation

// MARK: - Key Store

/// Loads and persists the Ed25519 signing key on disk.
///
/// The private key is written as base64 to `~/.config/attest/key` with `0600`
/// permissions. Signing is optional, so a missing key is an expected, recoverable
/// condition (`AttestError.keyNotFound`) rather than a fatal error.
public struct KeyStore: Sendable {
    private let keyPath: String

    /// The default key path: `$XDG_CONFIG_HOME/attest/key` or `~/.config/attest/key`.
    public static func defaultPath() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return (xdg as NSString).appendingPathComponent("attest/key")
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".config/attest/key")
    }

    public init(keyPath: String = KeyStore.defaultPath()) {
        self.keyPath = keyPath
    }

    /// The resolved key path.
    public var path: String { keyPath }

    /// Whether a key file currently exists.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: keyPath)
    }

    /// Loads the signer from disk.
    /// - Throws: `AttestError.keyNotFound` if no key exists.
    public func load() throws -> Ed25519Signer {
        guard exists else { throw AttestError.keyNotFound(keyPath) }
        let contents = try String(contentsOfFile: keyPath, encoding: .utf8)
        return try Ed25519Signer(base64PrivateKey: contents)
    }

    /// Generates a new keypair, writes the private key with `0600` permissions,
    /// and returns the signer.
    /// - Parameter force: Overwrite an existing key when `true`.
    /// - Throws: `AttestError.keyAlreadyExists` if a key exists and `force` is `false`.
    @discardableResult
    public func generate(force: Bool) throws -> Ed25519Signer {
        if exists, !force {
            throw AttestError.keyAlreadyExists(keyPath)
        }
        let directory = (keyPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let signer = Ed25519Signer.generate()
        let data = Data(signer.base64PrivateKey.utf8)
        // Create the file with restrictive permissions from the outset.
        FileManager.default.createFile(
            atPath: keyPath,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        // Re-assert permissions in case the file already existed under --force.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)
        return signer
    }
}
