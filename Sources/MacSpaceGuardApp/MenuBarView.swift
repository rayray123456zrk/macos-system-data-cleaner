import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MacSpace Guard").font(.headline)
            if let snapshot = model.snapshot {
                Text("\(ByteCountFormatter.string(fromByteCount: snapshot.availableBytes, countStyle: .file)) available")
                ProgressView(value: snapshot.usedFraction).tint(model.isLowSpace ? .orange : .blue)
            } else { ProgressView() }
            if model.isLowSpace { Label("Low disk space", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Divider()
            Button(model.isScanning ? "Cancel Scan" : "Scan Now") { model.isScanning ? model.cancelScan() : model.startScan() }
            Button("Open MacSpace Guard") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(10)
        .frame(width: 260)
    }
}
