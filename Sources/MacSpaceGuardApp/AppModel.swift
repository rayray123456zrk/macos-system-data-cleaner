import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftData
import UserNotifications

@MainActor
@Observable
final class AppModel {
    var snapshot: DiskSnapshot?
    var history: [DiskSnapshot] = []
    var findings: [ScanFinding] = []
    var selectedFindingIDs = Set<String>()
    var quarantineRecords: [QuarantineRecord] = []
    var scanProgress: ScanProgress?
    var isScanning = false
    var lastScanDate: Date?
    var cleanupResult: CleanupResult?
    var errorMessage: String?
    var deepScanSuggested = false

    @ObservationIgnored private let diskReader = DiskReader()
    @ObservationIgnored private let alertGate = AlertGate()
    @ObservationIgnored private let scanner = StorageScanner()
    @ObservationIgnored private let cleanupService = CleanupService()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var previousAvailableBytes: Int64?
    @ObservationIgnored private var lastHourlySave: Date?

    var settings = AppSettings.load()

    var alertPolicy: AlertPolicy {
        AlertPolicy(minimumFreeFraction: settings.minimumFreeFraction, minimumFreeBytes: settings.minimumFreeBytes)
    }

    var isLowSpace: Bool { snapshot.map(alertPolicy.isLowSpace) ?? false }
    var menuTitle: String { snapshot.map { ByteCountFormatter.string(fromByteCount: $0.availableBytes, countStyle: .file) } ?? "—" }
    var selectedFindings: [ScanFinding] { findings.filter { selectedFindingIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.sizeBytes } }

    func start() async {
        guard monitorTask == nil else { return }
        await refreshDisk()
        await requestNotificationPermissionIfNeeded()
        loadQuarantineRecords()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refreshDisk()
            }
        }
    }

    func refreshDisk() async {
        do {
            let newSnapshot = try await Task.detached { try DiskReader().read() }.value
            if let previousAvailableBytes, abs(newSnapshot.availableBytes - previousAvailableBytes) > 2 * 1_073_741_824 {
                deepScanSuggested = true
            }
            previousAvailableBytes = newSnapshot.availableBytes
            snapshot = newSnapshot
            if lastHourlySave == nil || newSnapshot.timestamp.timeIntervalSince(lastHourlySave!) >= 3_600 {
                history.append(newSnapshot)
                history = history.filter { Date.now.timeIntervalSince($0.timestamp) <= 30 * 86_400 }
                lastHourlySave = newSnapshot.timestamp
            }
            let low = alertPolicy.isLowSpace(newSnapshot)
            if await alertGate.shouldNotify(isLowSpace: low) { await sendLowSpaceNotification(newSnapshot) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        deepScanSuggested = false
        errorMessage = nil
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let exclusions = Set(settings.excludedPaths)
                let results = try await scanner.scan(excludedPaths: exclusions) { progress in
                    await MainActor.run { self.scanProgress = progress }
                }
                findings = results
                selectedFindingIDs.formIntersection(Set(results.map(\.id)))
                lastScanDate = .now
            } catch is CancellationError {
                errorMessage = "Scan cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            scanProgress = nil
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    func toggleSelection(_ finding: ScanFinding) {
        guard finding.isCleanable else { return }
        if selectedFindingIDs.contains(finding.id) { selectedFindingIDs.remove(finding.id) }
        else { selectedFindingIDs.insert(finding.id) }
    }

    func cleanSelected() async {
        let userItems = selectedFindings.filter { $0.category != .systemItem }
        let systemItems = selectedFindings.filter { $0.category == .systemItem }
        var allResults: [CleanupItemResult] = []
        if !userItems.isEmpty {
            let result = await cleanupService.execute(CleanupPlan(findings: userItems, method: .trash))
            allResults.append(contentsOf: result.items)
        }
        for item in systemItems {
            allResults.append(await quarantineSystemItem(item))
        }
        cleanupResult = CleanupResult(items: allResults)
        selectedFindingIDs.removeAll()
        loadQuarantineRecords()
        await refreshDisk()
    }

    func restore(_ record: QuarantineRecord) async {
        do {
            _ = try await PrivilegedHelperClient().run(action: "restore", arguments: [record.quarantinedPath, record.originalPath])
            loadQuarantineRecords()
        } catch { errorMessage = error.localizedDescription }
    }

    func purge(_ record: QuarantineRecord) async {
        do {
            _ = try await PrivilegedHelperClient().run(action: "purge", arguments: [record.quarantinedPath])
            loadQuarantineRecords()
            await refreshDisk()
        } catch { errorMessage = error.localizedDescription }
    }

    func saveSettings() {
        settings.save()
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { errorMessage = error.localizedDescription }
    }

    private func quarantineSystemItem(_ finding: ScanFinding) async -> CleanupItemResult {
        do {
            guard let identity = finding.identity else { throw CleanupService.CleanupError.identityUnavailable }
            let output = try await PrivilegedHelperClient().run(
                action: "quarantine",
                arguments: [finding.path, String(identity.device), String(identity.inode), String(finding.sizeBytes)]
            )
            let destination = (try? JSONDecoder().decode(QuarantineRecord.self, from: Data(output.utf8)))?.quarantinedPath
            return CleanupItemResult(sourcePath: finding.path, destinationPath: destination, status: .succeeded, message: "Moved to the seven-day system quarantine.")
        } catch {
            return CleanupItemResult(sourcePath: finding.path, status: .failed, message: error.localizedDescription)
        }
    }

    private func loadQuarantineRecords() {
        guard let data = try? Data(contentsOf: QuarantineStore.recordsURL),
              let records = try? JSONDecoder().decode([QuarantineRecord].self, from: data) else {
            quarantineRecords = []
            return
        }
        quarantineRecords = records.sorted { $0.createdAt > $1.createdAt }
    }

    private func requestNotificationPermissionIfNeeded() async {
        guard settings.notificationsEnabled else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func sendLowSpaceNotification(_ snapshot: DiskSnapshot) async {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "MacSpace Guard"
        content.body = "Only \(ByteCountFormatter.string(fromByteCount: snapshot.availableBytes, countStyle: .file)) remains."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-space", content: content, trigger: nil))
    }
}

struct AppSettings: Codable, Equatable {
    var minimumFreeFraction = 0.15
    var minimumFreeBytes: Int64 = 20 * 1_073_741_824
    var launchAtLogin = false
    var notificationsEnabled = true
    var excludedPaths: [String] = []

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "MacSpaceGuard.settings"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "MacSpaceGuard.settings") }
    }
}
