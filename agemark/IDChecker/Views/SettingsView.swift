import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("App appearance", selection: Bindable(model).theme) {
                        Label("Day", systemImage: "sun.max.fill")
                            .tag(AppTheme.day)
                        Label("Night", systemImage: "moon.stars.fill")
                            .tag(AppTheme.night)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.theme) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: "preferredAppTheme")
                    }
                }

                Section("Verification") {
                    Picker("Age threshold", selection: Bindable(model).threshold) {
                        Text("21 or older").tag(21)
                        Text("28 or older").tag(28)
                    }
                    .onChange(of: model.threshold) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "preferredAgeThreshold")
                    }
                    Toggle("Barcode-only fast mode", isOn: Bindable(model).fastMode)
                        .onChange(of: model.fastMode) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "preferredFastMode")
                        }
                }
                Section("Feedback") {
                    Toggle("Sound", isOn: Bindable(model).soundEnabled)
                    Toggle("Haptic", isOn: Bindable(model).hapticEnabled)
                }
                Section("Privacy Log") {
                    Picker("Auto-delete", selection: Bindable(model).logRetentionHours) {
                        Text("24 hours").tag(24)
                        Text("7 days").tag(168)
                        Text("30 days").tag(720)
                    }
                    Button("Clear privacy log", role: .destructive) { ScanLogger.shared.clear() }
                    Text("Logs contain only a SHA-256 hash, age bracket, verdict, and timestamp. ID photos and personal details are never saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Testing") {
                    Button("Reset free scans") { model.scanCount = 0 }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { model.screen = .home } } }
        }
    }
}
