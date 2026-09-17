import Foundation

public struct AlertPolicy: Sendable, Equatable {
    public var minimumFreeFraction: Double
    public var minimumFreeBytes: Int64

    public init(minimumFreeFraction: Double = 0.15, minimumFreeBytes: Int64 = 20 * 1_073_741_824) {
        self.minimumFreeFraction = minimumFreeFraction
        self.minimumFreeBytes = minimumFreeBytes
    }

    public func isLowSpace(_ snapshot: DiskSnapshot) -> Bool {
        guard snapshot.totalBytes > 0 else { return false }
        return Double(snapshot.availableBytes) / Double(snapshot.totalBytes) < minimumFreeFraction
            || snapshot.availableBytes < minimumFreeBytes
    }
}

public actor AlertGate {
    private var alertActive = false

    public init() {}

    public func shouldNotify(isLowSpace: Bool) -> Bool {
        if !isLowSpace {
            alertActive = false
            return false
        }
        guard !alertActive else { return false }
        alertActive = true
        return true
    }
}

public struct DiskReader: Sendable {
    public init() {}

    public func read(path: String = "/System/Volumes/Data") throws -> DiskSnapshot {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        guard let total = values.volumeTotalCapacity else { throw DiskError.capacityUnavailable }
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskSnapshot(totalBytes: Int64(total), availableBytes: available)
    }

    public enum DiskError: Error { case capacityUnavailable }
}

public actor SnapshotHistory {
    private let fileURL: URL
    private let retention: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL, retentionDays: Int = 30) {
        self.fileURL = fileURL
        self.retention = TimeInterval(retentionDays * 86_400)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load(now: Date = .now) -> [DiskSnapshot] {
        guard let data = try? Data(contentsOf: fileURL), let snapshots = try? decoder.decode([DiskSnapshot].self, from: data) else { return [] }
        return snapshots.filter { now.timeIntervalSince($0.timestamp) <= retention }.sorted { $0.timestamp < $1.timestamp }
    }

    @discardableResult
    public func appendHourly(_ snapshot: DiskSnapshot, now: Date = .now) throws -> [DiskSnapshot] {
        var snapshots = load(now: now)
        if let last = snapshots.last, snapshot.timestamp.timeIntervalSince(last.timestamp) < 3_600 {
            return snapshots
        }
        snapshots.append(snapshot)
        snapshots = snapshots.filter { now.timeIntervalSince($0.timestamp) <= retention }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshots).write(to: fileURL, options: .atomic)
        return snapshots
    }
}
