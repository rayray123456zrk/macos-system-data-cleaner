import SwiftData
import SwiftUI

@main
struct MacSpaceGuardApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacSpace Guard", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 620)
                .task { await model.start() }
        }
        .modelContainer(for: SnapshotRecord.self)
        .defaultSize(width: 1_040, height: 720)

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Label(model.menuTitle, systemImage: model.isLowSpace ? "externaldrive.fill.badge.exclamationmark" : "externaldrive.fill")
        }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 520, height: 390)
        }
    }
}
