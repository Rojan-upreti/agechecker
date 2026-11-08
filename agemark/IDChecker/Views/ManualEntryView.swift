import SwiftUI

struct ManualEntryView: View {
    let model: AppModel
    @State private var name = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -21, to: .now) ?? .now
    @State private var expirationDate = Calendar.current.date(byAdding: .year, value: 4, to: .now) ?? .now
    @State private var licenseNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("ID details") {
                    TextField("Full name", text: $name).textInputAutocapitalization(.characters)
                    DatePicker("Date of birth", selection: $dateOfBirth, displayedComponents: .date)
                    DatePicker("Expiration", selection: $expirationDate, displayedComponents: .date)
                    TextField("License number", text: $licenseNumber).textInputAutocapitalization(.characters)
                }
                Section {
                    Button("Verify Manually") {
                        model.submitManual(name: name, dob: dateOfBirth, expiry: expirationDate, license: licenseNumber)
                    }
                    .disabled(name.isEmpty || licenseNumber.isEmpty)
                }
                Text("Manual results are labeled MANUAL and do not confirm document authenticity.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Manual Entry")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { model.screen = .home } } }
        }
    }
}
