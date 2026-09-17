import Foundation
import SwiftData

@Model
final class SnapshotRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var totalBytes: Int64
    var availableBytes: Int64

    init(snapshot: DiskSnapshot) {
        id = snapshot.id
        timestamp = snapshot.timestamp
        totalBytes = snapshot.totalBytes
        availableBytes = snapshot.availableBytes
    }

    var snapshot: DiskSnapshot {
        DiskSnapshot(id: id, timestamp: timestamp, totalBytes: totalBytes, availableBytes: availableBytes)
    }
}
