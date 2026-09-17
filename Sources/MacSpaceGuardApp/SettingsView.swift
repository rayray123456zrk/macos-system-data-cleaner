import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newExclusion = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Low-space alert") {
                HStack { Text("Free space percentage"); Slider(value: $model.settings.minimumFreeFraction, in: 0.05...0.30, step: 0.01); Text(model.settings.minimumFreeFraction, format: .percent) }
                HStack { Text("Minimum free space"); Slider(value: Binding(get: { Double(model.settings.minimumFreeBytes) / 1_073_741_824 }, set: { model.settings.minimumFreeBytes = Int64($0 * 1_073_741_824) }), in: 5...100, step: 5); Text("\(model.settings.minimumFreeBytes / 1_073_741_824) GB") }
                Toggle("System notifications", isOn: $model.settings.notificationsEnabled)
            }
            Section("Background") { Toggle("Launch at login", isOn: $model.settings.launchAtLogin) }
            Section("Excluded paths") {
                ForEach(model.settings.excludedPaths, id: \.self) { path in HStack { Text(path).lineLimit(1); Spacer(); Button { model.settings.excludedPaths.removeAll { $0 == path } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) } }
                HStack { TextField("/absolute/path", text: $newExclusion); Button("Add") { let path = URL(fileURLWithPath: newExclusion).standardizedFileURL.path; if path.hasPrefix("/") && !model.settings.excludedPaths.contains(path) { model.settings.excludedPaths.append(path) }; newExclusion = "" }.disabled(newExclusion.isEmpty) }
            }
            HStack { Spacer(); Button("Save Settings") { model.saveSettings() }.buttonStyle(.borderedProminent) }
        }
        .formStyle(.grouped)
        .padding()
    }
}
