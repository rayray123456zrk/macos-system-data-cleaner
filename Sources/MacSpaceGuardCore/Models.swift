import Foundation

public struct DiskSnapshot: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let totalBytes: Int64
    public let availableBytes: Int64

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public init(id: UUID = UUID(), timestamp: Date = .now, totalBytes: Int64, availableBytes: Int64) {
        self.id = id
        self.timestamp = timestamp
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

public enum FindingCategory: String, Codable, CaseIterable, Sendable {
    case lowRiskCache
    case redownloadable
    case userData
    case systemItem

    public var title: String {
        switch self {
        case .lowRiskCache: "Low-risk cache"
        case .redownloadable: "Large downloadable resource"
        case .userData: "User or application data"
        case .systemItem: "System item"
        }
    }
}

public enum RiskLevel: Int, Codable, CaseIterable, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case protected = 3

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct FileIdentity: Codable, Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public struct ScanFinding: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let path: String
    public let sizeBytes: Int64
    public let category: FindingCategory
    public let risk: RiskLevel
    public let impact: String
    public let isCleanable: Bool
    public let identity: FileIdentity?

    public init(
        path: String,
        sizeBytes: Int64,
        category: FindingCategory,
        risk: RiskLevel,
        impact: String,
        isCleanable: Bool,
        identity: FileIdentity? = nil
    ) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.id = Self.stableID(for: self.path)
        self.sizeBytes = sizeBytes
        self.category = category
        self.risk = risk
        self.impact = impact
        self.isCleanable = isCleanable
        self.identity = identity
    }

    private static func stableID(for path: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}

public enum CleanupMethod: String, Codable, Sendable {
    case trash
    case quarantine
}

public struct CleanupPlan: Codable, Sendable, Equatable {
    public let findings: [ScanFinding]
    public let method: CleanupMethod
    public var estimatedBytes: Int64 { findings.reduce(0) { $0 + $1.sizeBytes } }

    public init(findings: [ScanFinding], method: CleanupMethod) {
        self.findings = findings
        self.method = method
    }
}

public enum CleanupStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case skipped
}

public struct CleanupItemResult: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sourcePath: String
    public let destinationPath: String?
    public let status: CleanupStatus
    public let message: String

    public init(id: UUID = UUID(), sourcePath: String, destinationPath: String? = nil, status: CleanupStatus, message: String) {
        self.id = id
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.status = status
        self.message = message
    }
}

public struct CleanupResult: Codable, Sendable, Equatable {
    public let completedAt: Date
    public let items: [CleanupItemResult]

    public init(completedAt: Date = .now, items: [CleanupItemResult]) {
        self.completedAt = completedAt
        self.items = items
    }
}

public struct QuarantineRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let originalPath: String
    public let quarantinedPath: String
    public let sizeBytes: Int64
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: UUID = UUID(), originalPath: String, quarantinedPath: String, sizeBytes: Int64, createdAt: Date = .now, expiresAt: Date) {
        self.id = id
        self.originalPath = originalPath
        self.quarantinedPath = quarantinedPath
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { expiresAt <= .now }
}

public struct ScanProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let currentPath: String

    public init(completed: Int, total: Int, currentPath: String) {
        self.completed = completed
        self.total = total
        self.currentPath = currentPath
    }
}
