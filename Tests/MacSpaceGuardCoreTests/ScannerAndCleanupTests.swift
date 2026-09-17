import Foundation
import Testing
@testable import MacSpaceGuardCore

@Test func scannerHonorsExclusionsAndAvoidsNestedRoots() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cache = root.appending(path: "Library/Caches/Demo", directoryHint: .isDirectory)
    let excluded = root.appending(path: "Library/Caches/Excluded", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4_096).write(to: cache.appending(path: "cache.bin"))
    try Data(repeating: 1, count: 4_096).write(to: excluded.appending(path: "cache.bin"))
    defer { try? FileManager.default.removeItem(at: root) }

    let results = try await StorageScanner().scan(
        roots: [root.appending(path: "Library/Caches"), cache],
        excludedPaths: [excluded.path],
        minimumSize: 1
    )
    #expect(results.contains { $0.path == cache.path })
    #expect(!results.contains { $0.path == excluded.path })
}

@Test func cleanupMovesToTrashAndUsesUniqueNames() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source/cache.bin")
    let trash = root.appending(path: "trash")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("cache".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }

    let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
    let identity = FileIdentity(
        device: (attributes[.systemNumber] as! NSNumber).uint64Value,
        inode: (attributes[.systemFileNumber] as! NSNumber).uint64Value
    )
    let finding = ScanFinding(path: source.path, sizeBytes: 5, category: .lowRiskCache, risk: .low, impact: "", isCleanable: true, identity: identity)
    let result = await CleanupService(trashRoot: trash).execute(CleanupPlan(findings: [finding], method: .trash))
    #expect(result.items.first?.status == .succeeded)
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(result.items.first?.destinationPath.map(FileManager.default.fileExists(atPath:)) == true)
}

@Test func cleanupRefusesChangedIdentity() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "cache.bin")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("cache".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }

    let wrong = FileIdentity(device: 0, inode: 0)
    let finding = ScanFinding(path: source.path, sizeBytes: 5, category: .lowRiskCache, risk: .low, impact: "", isCleanable: true, identity: wrong)
    let result = await CleanupService(trashRoot: root.appending(path: "trash")).execute(CleanupPlan(findings: [finding], method: .trash))
    #expect(result.items.first?.status == .failed)
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test func historyPrunesAndSamplesHourly() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SnapshotHistory(fileURL: root.appending(path: "history.json"), retentionDays: 30)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    _ = try await store.appendHourly(DiskSnapshot(timestamp: now.addingTimeInterval(-100), totalBytes: 100, availableBytes: 50), now: now)
    let second = try await store.appendHourly(DiskSnapshot(timestamp: now, totalBytes: 100, availableBytes: 40), now: now)
    #expect(second.count == 1)
}
