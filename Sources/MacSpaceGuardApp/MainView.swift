import Charts
import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SnapshotRecord.timestamp) private var storedSnapshots: [SnapshotRecord]
    @State private var selection: SidebarSection? = .overview
    @State private var showCleanupConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("MacSpace Guard")
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .findings: FindingsView()
            case .cleanup: CleanupQueueView(showConfirmation: $showCleanupConfirmation)
            case .quarantine: QuarantineView()
            case .settings: SettingsView()
            }
        }
        .alert("MacSpace Guard", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Move selected items to recoverable storage?", isPresented: $showCleanupConfirmation) {
            Button("Clean \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))") {
                Task { await model.cleanSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("User items go to Trash. System items require an administrator password and go to the seven-day quarantine.")
        }
        .task(id: model.snapshot?.id) { persistLatestSnapshot() }
    }

    private func persistLatestSnapshot() {
        model.history = storedSnapshots.map(\.snapshot)
        guard let snapshot = model.snapshot else { return }
        if let last = storedSnapshots.last, snapshot.timestamp.timeIntervalSince(last.timestamp) < 3_600 { return }
        modelContext.insert(SnapshotRecord(snapshot: snapshot))
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        for record in storedSnapshots where record.timestamp < cutoff { modelContext.delete(record) }
        try? modelContext.save()
        model.history = (storedSnapshots.map(\.snapshot) + [snapshot]).filter { $0.timestamp >= cutoff }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview, findings, cleanup, quarantine, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .findings: "Scan Results"
        case .cleanup: "Cleanup Queue"
        case .quarantine: "Quarantine"
        case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .findings: "magnifyingglass"
        case .cleanup: "trash"
        case .quarantine: "archivebox"
        case .settings: "gearshape"
        }
    }
}

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 28) {
                    capacityRing
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.isLowSpace ? "Low disk space" : "Storage looks healthy")
                            .font(.title.bold())
                            .foregroundStyle(model.isLowSpace ? .orange : .primary)
                        if let snapshot = model.snapshot {
                            Text("\(format(snapshot.availableBytes)) available of \(format(snapshot.totalBytes))")
                            Text("Updated \(snapshot.timestamp.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        if model.deepScanSuggested {
                            Label("Storage changed by more than 2 GB. A deep scan is recommended.", systemImage: "waveform.path.ecg")
                                .foregroundStyle(.orange)
                        }
                        scanControls
                    }
                    Spacer()
                }
                GroupBox("30-day available space") {
                    if model.history.isEmpty {
                        ContentUnavailableView("No history yet", systemImage: "chart.xyaxis.line", description: Text("One snapshot is saved every hour."))
                            .frame(height: 220)
                    } else {
                        Chart(model.history) { point in
                            AreaMark(x: .value("Time", point.timestamp), y: .value("Available", point.availableBytes))
                                .foregroundStyle(.blue.opacity(0.2))
                            LineMark(x: .value("Time", point.timestamp), y: .value("Available", point.availableBytes))
                                .foregroundStyle(.blue)
                        }
                        .chartYAxis { AxisMarks(format: ByteCountFormatStyle(style: .file)) }
                        .frame(height: 240)
                        .padding()
                    }
                }
                if let result = model.cleanupResult { CleanupSummary(result: result) }
            }
            .padding(28)
        }
        .navigationTitle("Overview")
    }

    private var capacityRing: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.18), lineWidth: 18)
            Circle().trim(from: 0, to: model.snapshot?.usedFraction ?? 0)
                .stroke(model.isLowSpace ? .orange : .blue, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack { Text(model.snapshot.map { String(format: "%.0f%%", $0.usedFraction * 100) } ?? "—").font(.title.bold()); Text("used").foregroundStyle(.secondary) }
        }
        .frame(width: 160, height: 160)
    }

    private var scanControls: some View {
        HStack {
            if model.isScanning {
                Button("Cancel Scan", role: .destructive) { model.cancelScan() }
                if let progress = model.scanProgress { ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total))).frame(width: 180) }
            } else {
                Button("Scan Now") { model.startScan() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct FindingsView: View {
    @Environment(AppModel.self) private var model
    @State private var category: FindingCategory?

    private var filtered: [ScanFinding] { category.map { value in model.findings.filter { $0.category == value } } ?? model.findings }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Category", selection: $category) {
                    Text("All").tag(FindingCategory?.none)
                    ForEach(FindingCategory.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }.frame(width: 260)
                Spacer()
                if model.isScanning { ProgressView() }
                Button(model.isScanning ? "Cancel" : "Scan Now") { model.isScanning ? model.cancelScan() : model.startScan() }
            }.padding()
            Table(filtered) {
                TableColumn("") { finding in
                    Toggle("", isOn: Binding(get: { model.selectedFindingIDs.contains(finding.id) }, set: { _ in model.toggleSelection(finding) }))
                        .labelsHidden().disabled(!finding.isCleanable)
                }.width(28)
                TableColumn("Name") { Text(URL(fileURLWithPath: $0.path).lastPathComponent).help($0.path) }
                TableColumn("Size") { Text(ByteCountFormatter.string(fromByteCount: $0.sizeBytes, countStyle: .file)) }.width(90)
                TableColumn("Category") { Text($0.category.title) }.width(170)
                TableColumn("Risk") { RiskBadge(level: $0.risk) }.width(85)
                TableColumn("Impact") { Text($0.impact).lineLimit(2) }
            }
            if model.findings.isEmpty && !model.isScanning {
                ContentUnavailableView("No scan results", systemImage: "externaldrive.badge.magnifyingglass", description: Text("Run a deep scan to identify cleanup candidates."))
            }
        }.navigationTitle("Scan Results")
    }
}

struct CleanupQueueView: View {
    @Environment(AppModel.self) private var model
    @Binding var showConfirmation: Bool
    var body: some View {
        VStack {
            List(model.selectedFindings) { finding in
                HStack { RiskBadge(level: finding.risk); VStack(alignment: .leading) { Text(URL(fileURLWithPath: finding.path).lastPathComponent); Text(finding.path).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(ByteCountFormatter.string(fromByteCount: finding.sizeBytes, countStyle: .file)); Button { model.toggleSelection(finding) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain) }
            }
            HStack { Text("Selected: \(model.selectedFindings.count) items · \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))").font(.headline); Spacer(); Button("Review and Clean") { showConfirmation = true }.buttonStyle(.borderedProminent).disabled(model.selectedFindings.isEmpty) }.padding()
        }.navigationTitle("Cleanup Queue")
    }
}

struct QuarantineView: View {
    @Environment(AppModel.self) private var model
    @State private var purgeCandidate: QuarantineRecord?
    var body: some View {
        List(model.quarantineRecords) { record in
            HStack {
                VStack(alignment: .leading) { Text(URL(fileURLWithPath: record.originalPath).lastPathComponent); Text(record.originalPath).font(.caption).foregroundStyle(.secondary); Text(record.isExpired ? "Ready for permanent removal" : "Expires \(record.expiresAt.formatted())").font(.caption).foregroundStyle(record.isExpired ? .orange : .secondary) }
                Spacer()
                Button("Restore") { Task { await model.restore(record) } }
                Button("Delete Permanently", role: .destructive) { purgeCandidate = record }
            }
        }
        .overlay { if model.quarantineRecords.isEmpty { ContentUnavailableView("Quarantine is empty", systemImage: "archivebox") } }
        .navigationTitle("System Quarantine")
        .confirmationDialog("Permanently delete this quarantined item?", isPresented: Binding(get: { purgeCandidate != nil }, set: { if !$0 { purgeCandidate = nil } })) {
            Button("Delete Permanently", role: .destructive) { if let record = purgeCandidate { Task { await model.purge(record) } }; purgeCandidate = nil }
            Button("Cancel", role: .cancel) { purgeCandidate = nil }
        }
    }
}

struct CleanupSummary: View {
    let result: CleanupResult
    var body: some View {
        GroupBox("Last cleanup") {
            HStack { Label("\(result.items.filter { $0.status == .succeeded }.count) succeeded", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Label("\(result.items.filter { $0.status == .failed }.count) failed", systemImage: "xmark.circle.fill").foregroundStyle(.red); Label("\(result.items.filter { $0.status == .skipped }.count) skipped", systemImage: "forward.circle.fill").foregroundStyle(.secondary); Spacer() }.padding()
        }
    }
}

struct RiskBadge: View {
    let level: RiskLevel
    var color: Color { switch level { case .low: .green; case .medium: .yellow; case .high: .orange; case .protected: .red } }
    var body: some View { Text(String(describing: level).capitalized).font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.16), in: Capsule()).foregroundStyle(color) }
}
