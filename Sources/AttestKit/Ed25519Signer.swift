@preconcurrency import Foundation
@preconcurrency import Crypto

// MARK: - Signer

/// Ed25519 signing and verification for attestations, backed by swift-crypto.
///
/// Signing is optional throughout `attest`: a record without a signature is
/// still valid provenance. When used, the signer produces a detached base64
/// signature over an attestation's `canonicalData()` and embeds the signer's
/// base64 public key on the record so any party can verify it later.
public struct Ed25519Signer: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    /// Wraps an existing private key.
    public init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    /// Loads a signer from a base64-encoded 32-byte private key.
    public init(base64PrivateKey: String) throws {
        guard let raw = Data(base64Encoded: base64PrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AttestError.invalidKey("private key is not valid base64")
        }
        do {
            self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } catch {
            throw AttestError.invalidKey("private key is not a valid Ed25519 key")
        }
    }

    /// Generates a fresh keypair.
    public static func generate() -> Ed25519Signer {
        Ed25519Signer(privateKey: Curve25519.Signing.PrivateKey())
    }

    /// The base64-encoded raw private key (32 bytes). Keep this secret.
    public var base64PrivateKey: String {
        privateKey.rawRepresentation.base64EncodedString()
    }

    /// The base64-encoded raw public key (32 bytes).
    public var base64PublicKey: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// Signs an attestation's canonical bytes, returning a copy with the
    /// signature and public key attached.
    public func sign(_ attestation: Attestation) throws -> Attestation {
        let bytes = try attestation.canonicalData()
        let signature = try privateKey.signature(for: bytes)
        return attestation.attaching(
            signature: signature.base64EncodedString(),
            publicKey: base64PublicKey
        )
    }
}

// MARK: - Verifier

/// Stateless Ed25519 signature verification for attestations.
public enum Ed25519Verifier {
    /// Verifies an attestation's embedded signature against its embedded public
    /// key (and, when provided, against an expected public key).
    ///
    /// - Parameters:
    ///   - attestation: The record to verify; must carry `signature` and `publicKey`.
    ///   - expectedPublicKey: Optional base64 public key the record must match.
    /// - Throws: `AttestError.signatureMissing` if unsigned;
    ///   `AttestError.verificationFailed` if the key mismatches or the signature
    ///   does not validate over the canonical bytes.
    public static func verify(_ attestation: Attestation, expectedPublicKey: String? = nil) throws {
        guard
            let signatureBase64 = attestation.signature,
            let publicKeyBase64 = attestation.publicKey
        else {
            throw AttestError.signatureMissing
        }
        if let expected = expectedPublicKey, expected != publicKeyBase64 {
            throw AttestError.verificationFailed(reason: "public key does not match the expected signer")
        }
        guard
            let signature = Data(base64Encoded: signatureBase64),
            let publicKeyRaw = Data(base64Encoded: publicKeyBase64)
        else {
            throw AttestError.verificationFailed(reason: "signature or public key is not valid base64")
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw)
        } catch {
            throw AttestError.verificationFailed(reason: "public key is not a valid Ed25519 key")
        }
        let bytes = try attestation.canonicalData()
        guard publicKey.isValidSignature(signature, for: bytes) else {
            throw AttestError.verificationFailed(reason: "signature does not match the canonical attestation bytes")
        }
    }

    /// A non-throwing convenience returning whether verification succeeds.
    public static func isValid(_ attestation: Attestation, expectedPublicKey: String? = nil) -> Bool {
        do {
            try verify(attestation, expectedPublicKey: expectedPublicKey)
            return true
        } catch {
            return false
        }
    }
}
