import Foundation

public actor StorageScanner {
    public typealias ProgressHandler = @Sendable (ScanProgress) async -> Void

    private let fileManager: FileManager
    private let policy: StoragePolicy

    public init(fileManager: FileManager = .default, policy: StoragePolicy = StoragePolicy()) {
        self.fileManager = fileManager
        self.policy = policy
    }

    public static func defaultRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let home = homeDirectory.path
        return [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Application Support",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Developer",
            "\(home)/.cache",
            "\(home)/.npm",
            "/private/var/folders",
            "/Library/Updates",
            "/Library/Caches"
        ].map(URL.init(fileURLWithPath:))
    }

    public func scan(
        roots: [URL] = StorageScanner.defaultRoots(),
        excludedPaths: Set<String> = [],
        minimumSize: Int64 = 10 * 1_048_576,
        progress: ProgressHandler? = nil
    ) async throws -> [ScanFinding] {
        let normalizedExclusions = Set(excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let uniqueRoots = deduplicatedRoots(roots, exclusions: normalizedExclusions)
        var findings: [ScanFinding] = []

        for (index, root) in uniqueRoots.enumerated() {
            try Task.checkCancellation()
            await progress?(ScanProgress(completed: index, total: uniqueRoots.count, currentPath: root.path))
            guard fileManager.fileExists(atPath: root.path) else { continue }

            let children = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let rootVolume = try? root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            for child in children {
                try Task.checkCancellation()
                let childPath = child.standardizedFileURL.path
                guard !isExcluded(childPath, exclusions: normalizedExclusions) else { continue }
                let size = try await allocatedSize(of: child, rootVolumeIdentifier: rootVolume)
                guard size >= minimumSize else { continue }
                let classification = policy.classify(path: childPath)
                findings.append(ScanFinding(
                    path: childPath,
                    sizeBytes: size,
                    category: classification.0,
                    risk: classification.1,
                    impact: classification.2,
                    isCleanable: classification.3,
                    identity: fileIdentity(at: childPath)
                ))
            }
        }

        await progress?(ScanProgress(completed: uniqueRoots.count, total: uniqueRoots.count, currentPath: ""))
        return removeNestedDuplicates(findings).sorted { lhs, rhs in
            lhs.sizeBytes == rhs.sizeBytes ? lhs.path < rhs.path : lhs.sizeBytes > rhs.sizeBytes
        }
    }

    private func allocatedSize(of root: URL, rootVolumeIdentifier: Any?) async throws -> Int64 {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey])
        if values.isSymbolicLink == true { return 0 }
        if let rootVolumeIdentifier, let itemVolume = values.volumeIdentifier,
           String(describing: rootVolumeIdentifier) != String(describing: itemVolume) { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }

        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var counter = 0
        while let item = enumerator.nextObject() as? URL {
            counter += 1
            if counter.isMultiple(of: 256) { try Task.checkCancellation() }
            guard let itemValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey]) else { continue }
            if itemValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if let rootVolumeIdentifier, let itemVolume = itemValues.volumeIdentifier,
               String(describing: rootVolumeIdentifier) != String(describing: itemVolume) {
                enumerator.skipDescendants()
                continue
            }
            if itemValues.isDirectory != true {
                total += Int64(itemValues.totalFileAllocatedSize ?? itemValues.fileSize ?? 0)
            }
        }
        return total
    }

    private func fileIdentity(at path: String) -> FileIdentity? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return FileIdentity(device: device, inode: inode)
    }

    private func deduplicatedRoots(_ roots: [URL], exclusions: Set<String>) -> [URL] {
        let paths = Set(roots.map { $0.standardizedFileURL.path })
            .filter { !isExcluded($0, exclusions: exclusions) }
            .sorted { $0.count < $1.count }
        var accepted: [String] = []
        for path in paths where !accepted.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            accepted.append(path)
        }
        return accepted.map(URL.init(fileURLWithPath:))
    }

    private func removeNestedDuplicates(_ findings: [ScanFinding]) -> [ScanFinding] {
        let sorted = findings.sorted { $0.path.count < $1.path.count }
        var accepted: [ScanFinding] = []
        for finding in sorted where !accepted.contains(where: { finding.path.hasPrefix($0.path + "/") }) {
            accepted.append(finding)
        }
        return accepted
    }

    private func isExcluded(_ path: String, exclusions: Set<String>) -> Bool {
        exclusions.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
