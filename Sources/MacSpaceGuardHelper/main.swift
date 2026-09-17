import Foundation
#if SWIFT_PACKAGE
import MacSpaceGuardCore
#endif

enum HelperAction: String { case quarantine, restore, purge }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, let action = HelperAction(rawValue: arguments[0]) else {
    fail("Usage: macspaceguard-helper quarantine <path> <device> <inode> <size> | restore <quarantine-path> <destination> | purge <quarantine-path>")
}

let fileManager = FileManager.default
let policy = StoragePolicy()

@MainActor func loadRecords() -> [QuarantineRecord] {
    guard let data = try? Data(contentsOf: QuarantineStore.recordsURL),
          let records = try? JSONDecoder().decode([QuarantineRecord].self, from: data) else { return [] }
    return records
}

@MainActor func saveRecords(_ records: [QuarantineRecord]) throws {
    try fileManager.createDirectory(at: QuarantineStore.root, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(records).write(to: QuarantineStore.recordsURL, options: .atomic)
}

switch action {
case .quarantine:
    guard arguments.count == 5,
          let expectedDevice = UInt64(arguments[2]),
          let expectedInode = UInt64(arguments[3]),
          let expectedSize = Int64(arguments[4]) else { fail("Quarantine requires path, expected device, inode, and size.") }
    let source: String
    do { source = try policy.validateSystemPath(arguments[1]) }
    catch { fail(error.localizedDescription) }
    guard fileManager.fileExists(atPath: source) else { fail("Source does not exist.") }
    guard let attributes = try? fileManager.attributesOfItem(atPath: source),
          let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
          let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
          device == expectedDevice,
          inode == expectedInode else { fail("Source identity changed after scanning; no files were moved.") }
    do {
        try fileManager.createDirectory(at: QuarantineStore.root, withIntermediateDirectories: true)
        let destination = QuarantineStore.root.appending(path: UUID().uuidString + "-" + URL(fileURLWithPath: source).lastPathComponent)
        try fileManager.moveItem(atPath: source, toPath: destination.path)
        let record = QuarantineRecord(originalPath: source, quarantinedPath: destination.path, sizeBytes: expectedSize, expiresAt: .now.addingTimeInterval(QuarantineStore.retention))
        var records = loadRecords()
        records.append(record)
        try saveRecords(records)
        print(String(data: try JSONEncoder().encode(record), encoding: .utf8) ?? "{}")
    } catch { fail(error.localizedDescription) }

case .restore:
    guard arguments.count == 3 else { fail("Restore requires quarantine path and original destination.") }
    let quarantined = URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
    guard quarantined.hasPrefix(QuarantineStore.root.path + "/") else { fail("Invalid quarantine path.") }
    let destination: String
    do { destination = try policy.validateSystemPath(arguments[2]) }
    catch { fail(error.localizedDescription) }
    guard !fileManager.fileExists(atPath: destination) else { fail("Restore destination already exists.") }
    do {
        try fileManager.moveItem(atPath: quarantined, toPath: destination)
        try saveRecords(loadRecords().filter { $0.quarantinedPath != quarantined })
    }
    catch { fail(error.localizedDescription) }

case .purge:
    let quarantined = URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
    guard quarantined.hasPrefix(QuarantineStore.root.path + "/") else { fail("Invalid quarantine path.") }
    do {
        try fileManager.removeItem(atPath: quarantined)
        try saveRecords(loadRecords().filter { $0.quarantinedPath != quarantined })
    }
    catch { fail(error.localizedDescription) }
}
