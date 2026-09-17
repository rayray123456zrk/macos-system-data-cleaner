import Darwin
import Foundation

public actor CleanupService {
    private let fileManager: FileManager
    private let policy: StoragePolicy
    private let trashRoot: URL

    public init(
        fileManager: FileManager = .default,
        policy: StoragePolicy = StoragePolicy(),
        trashRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
    ) {
        self.fileManager = fileManager
        self.policy = policy
        self.trashRoot = trashRoot
    }

    public func execute(_ plan: CleanupPlan) async -> CleanupResult {
        var results: [CleanupItemResult] = []
        let archive = trashRoot.appending(path: "MacSpaceGuard-\(Self.archiveTimestamp())", directoryHint: .isDirectory)

        if plan.method == .trash {
            do { try fileManager.createDirectory(at: archive, withIntermediateDirectories: true) }
            catch {
                return CleanupResult(items: plan.findings.map {
                    CleanupItemResult(sourcePath: $0.path, status: .failed, message: "Cannot create Trash archive: \(error.localizedDescription)")
                })
            }
        }

        for finding in plan.findings {
            if Task.isCancelled {
                results.append(CleanupItemResult(sourcePath: finding.path, status: .skipped, message: "Cleanup cancelled."))
                continue
            }
            guard finding.isCleanable else {
                results.append(CleanupItemResult(sourcePath: finding.path, status: .skipped, message: "Item is protected by policy."))
                continue
            }
            do {
                let currentIdentity = try identity(at: finding.path)
                if let expected = finding.identity, currentIdentity != expected {
                    throw CleanupError.fileChanged
                }
                if plan.method == .quarantine || finding.category == .systemItem {
                    results.append(CleanupItemResult(sourcePath: finding.path, status: .skipped, message: "Administrator authorization is required for system quarantine."))
                    continue
                }
                let destination = uniqueDestination(in: archive, named: URL(fileURLWithPath: finding.path).lastPathComponent)
                try fileManager.moveItem(atPath: finding.path, toPath: destination.path)
                results.append(CleanupItemResult(sourcePath: finding.path, destinationPath: destination.path, status: .succeeded, message: "Moved to Trash archive."))
            } catch {
                results.append(CleanupItemResult(sourcePath: finding.path, status: .failed, message: error.localizedDescription))
            }
        }
        return CleanupResult(items: results)
    }

    public func uniqueDestination(in directory: URL, named name: String) -> URL {
        var candidate = directory.appending(path: name)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(name)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private func identity(at path: String) throws -> FileIdentity {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        guard let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            throw CleanupError.identityUnavailable
        }
        return FileIdentity(device: device, inode: inode)
    }

    private static func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: .now)
    }

    public enum CleanupError: LocalizedError {
        case fileChanged
        case identityUnavailable

        public var errorDescription: String? {
            switch self {
            case .fileChanged: "The item changed after scanning; it was not moved."
            case .identityUnavailable: "The item identity could not be verified."
            }
        }
    }
}

public struct QuarantineStore: Sendable {
    public static let root = URL(fileURLWithPath: "/Library/Application Support/MacSpaceGuard/Quarantine", isDirectory: true)
    public static let recordsURL = root.appending(path: "records.json")
    public static let retention: TimeInterval = 7 * 86_400

    public init() {}
}
