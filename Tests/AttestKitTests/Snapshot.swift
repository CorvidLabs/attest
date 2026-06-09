@preconcurrency import Foundation
import XCTest

/// A tiny, dependency-free golden-file snapshot harness.
///
/// `attest` keeps its test target free of third-party packages (no
/// `swift-snapshot-testing`), so snapshots are plain files on disk next to the
/// tests. Each snapshot lives at `__snapshots__/<name>.snap`, resolved relative
/// to the calling source file.
///
/// Behaviour:
/// - If the golden file is missing, or the `RECORD_SNAPSHOTS` environment
///   variable is set, the actual value is written to disk and the assertion
///   fails with a "recorded" message (so a recording run is never silently
///   green).
/// - Otherwise the golden file is read and compared with `XCTAssertEqual`.
///
/// Raw ANSI escapes are stored verbatim in the golden files, so colored output
/// round-trips byte-for-byte.
internal enum Snapshot {
    /// The directory holding golden files, alongside the calling test source.
    /// - Parameter file: The source file requesting the snapshot.
    /// - Returns: The `__snapshots__` directory URL.
    fileprivate static func directory(for file: StaticString) -> URL {
        let sourcePath = "\(file)"
        let sourceURL = URL(fileURLWithPath: sourcePath)
        return sourceURL.deletingLastPathComponent().appendingPathComponent("__snapshots__")
    }
}

/// Asserts that `actual` matches the golden file named `name`.
///
/// On a missing golden file or when `RECORD_SNAPSHOTS` is set, the value is
/// recorded to disk and the test fails with a recorded notice; otherwise the
/// stored golden is compared against `actual`.
///
/// - Parameters:
///   - actual: The rendered string to snapshot (ANSI escapes are stored as-is).
///   - name: The golden file's base name (without the `.snap` extension).
///   - file: The calling source file; used to locate `__snapshots__`.
///   - line: The calling line, for failure attribution.
internal func assertSnapshot(
    _ actual: String,
    _ name: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let directory = Snapshot.directory(for: file)
    let snapshotURL = directory.appendingPathComponent("\(name).snap")
    let fileManager = FileManager.default
    let exists = fileManager.fileExists(atPath: snapshotURL.path)

    if !exists || ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(actual.utf8).write(to: snapshotURL)
        } catch {
            XCTFail("failed to record snapshot \(name): \(error)", file: file, line: line)
            return
        }
        XCTFail(
            "recorded snapshot \(name) at \(snapshotURL.path); re-run without RECORD_SNAPSHOTS to verify",
            file: file,
            line: line
        )
        return
    }

    guard let data = try? Data(contentsOf: snapshotURL), let expected = String(data: data, encoding: .utf8) else {
        XCTFail("failed to read snapshot \(name) at \(snapshotURL.path)", file: file, line: line)
        return
    }
    XCTAssertEqual(actual, expected, "snapshot \(name) mismatch", file: file, line: line)
}
