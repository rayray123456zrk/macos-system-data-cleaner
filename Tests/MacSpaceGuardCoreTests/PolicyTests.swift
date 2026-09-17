import Foundation
import Testing
@testable import MacSpaceGuardCore

@Test func alertPolicyUsesEitherThreshold() {
    let policy = AlertPolicy(minimumFreeFraction: 0.15, minimumFreeBytes: 20 * 1_073_741_824)
    #expect(policy.isLowSpace(DiskSnapshot(totalBytes: 100, availableBytes: 14)))
    #expect(policy.isLowSpace(DiskSnapshot(totalBytes: 1_000_000_000_000, availableBytes: 10_000_000_000)))
    #expect(!policy.isLowSpace(DiskSnapshot(totalBytes: 100_000_000_000, availableBytes: 30_000_000_000)))
}

@Test func alertGateOnlyNotifiesOnTransition() async {
    let gate = AlertGate()
    #expect(await gate.shouldNotify(isLowSpace: true))
    #expect(!(await gate.shouldNotify(isLowSpace: true)))
    #expect(!(await gate.shouldNotify(isLowSpace: false)))
    #expect(await gate.shouldNotify(isLowSpace: true))
}

@Test func classificationProtectsUserData() {
    let policy = StoragePolicy()
    let chat = policy.classify(path: "/Users/test/Library/Containers/chat/Data/Documents/msg/video")
    #expect(chat.0 == .userData)
    #expect(chat.1 == .protected)
    #expect(chat.3 == false)

    let cache = policy.classify(path: "/Users/test/Library/Caches/Homebrew")
    #expect(cache.0 == .lowRiskCache)
    #expect(cache.3)

    let model = policy.classify(path: "/Users/test/.cache/huggingface/model.bin")
    #expect(model.0 == .redownloadable)
}

@Test func systemAllowlistRejectsBroadAndUnknownPaths() throws {
    let policy = StoragePolicy()
    #expect(throws: StoragePolicy.PolicyError.forbiddenRoot) { try policy.validateSystemPath("/Library") }
    #expect(throws: StoragePolicy.PolicyError.outsideAllowlist) { try policy.validateSystemPath("/Library/Keychains") }
    #expect(try policy.validateSystemPath("/Library/Updates") == "/Library/Updates")
}

@Test func stableFindingIDIsDeterministic() {
    let lhs = ScanFinding(path: "/tmp/cache", sizeBytes: 1, category: .lowRiskCache, risk: .low, impact: "", isCleanable: true)
    let rhs = ScanFinding(path: "/tmp/../tmp/cache", sizeBytes: 2, category: .lowRiskCache, risk: .low, impact: "", isCleanable: true)
    #expect(lhs.id == rhs.id)
}
