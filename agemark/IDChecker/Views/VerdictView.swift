import SwiftUI

struct VerdictView: View {
    let model: AppModel
    @State private var showsDetails = false

    var body: some View {
        if let result = model.scanResult {
            ScrollView {
                VStack(spacing: 16) {
                    VerdictHeader(
                        duplicateMessage: model.duplicateMessage,
                        isManual: result.isManual,
                        isBarcodeOnly: model.fastMode && !result.isManual
                    )

                    if !model.fastMode && !result.isManual {
                        IDPhotoView(image: result.frontImage)
                    }

                    VerdictCard(result: result, threshold: model.threshold)

                    if model.fastMode && !result.isManual {
                        BarcodeOnlyConfirmation()
                    } else if let comparison = result.comparison {
                        ComparisonSection(
                            comparison: comparison,
                            front: result.ocr,
                            back: result.barcode
                        )
                    }

                    if !result.verification.reasons.isEmpty {
                        VerificationNotes(reasons: result.verification.reasons)
                    }

                    VerdictActions(
                        scanNext: { model.beginScan() },
                        manualEntry: { model.screen = .manual },
                        home: { model.screen = .home },
                        toggleDetails: { showsDetails.toggle() },
                        showsDetails: showsDetails
                    )

                    if showsDetails {
                        BarcodeDetails(data: result.barcode)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("Age verification aid. Does not guarantee an ID is genuine. Always check photo and physical security features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
    }
}

private struct VerdictHeader: View {
    let duplicateMessage: String?
    let isManual: Bool
    let isBarcodeOnly: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Verification result")
                    .font(.title2.bold())
                Spacer()
                if isManual {
                    StatusBadge(title: "MANUAL", systemImage: "square.and.pencil", color: AgeMarkPalette.amber)
                } else if isBarcodeOnly {
                    StatusBadge(title: "BARCODE ONLY", systemImage: "barcode.viewfinder", color: AgeMarkPalette.teal)
                }
            }

            if let duplicateMessage {
                Label(duplicateMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AgeMarkPalette.amber, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private struct StatusBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(color, in: Capsule())
    }
}

private struct IDPhotoView: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .clipped()
                .accessibilityLabel("Captured front of ID for visual photo comparison")
        } else {
            Label("Front image unavailable — compare the physical ID", systemImage: "person.crop.rectangle.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AgeMarkPalette.amber)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct VerdictCard: View {
    let result: ScanResult
    let threshold: Int

    private var color: Color {
        switch result.verification.verdict {
        case .over21:
            AgeMarkPalette.teal
        case .under21, .expired:
            AgeMarkPalette.coral
        case .checkManually:
            AgeMarkPalette.amber
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: verdictIcon)
                .font(.system(size: 38, weight: .bold))
            Text(verdictTitle)
                .font(.system(size: 58, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.52)
                .lineLimit(1)
            if let age = result.verification.age {
                Text("Age \(age)")
                    .font(.largeTitle.bold())
            }
            Text(result.barcode.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            ViewThatFits {
                HStack(spacing: 18) {
                    dateLabels
                }
                VStack(spacing: 5) {
                    dateLabels
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.76))
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(AgeMarkPalette.navy, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(color.opacity(0.45), lineWidth: 1)
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var dateLabels: some View {
        if let dob = result.barcode.dateOfBirth {
            Text("DOB: \(dob, format: .dateTime.month().day().year())")
        }
        if let expiry = result.barcode.expirationDate {
            Text("Expires: \(expiry, format: .dateTime.month().day().year())")
        }
    }

    private var verdictTitle: String {
        switch result.verification.verdict {
        case .over21: "OVER \(threshold)"
        case .under21: "UNDER \(threshold)"
        case .expired: "EXPIRED"
        case .checkManually: "CHECK MANUALLY"
        }
    }

    private var verdictIcon: String {
        switch result.verification.verdict {
        case .over21: "checkmark.seal.fill"
        case .under21: "xmark.octagon.fill"
        case .expired: "calendar.badge.exclamationmark"
        case .checkManually: "exclamationmark.triangle.fill"
        }
    }
}

private struct BarcodeOnlyConfirmation: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "barcode")
                .font(.title2)
                .foregroundStyle(AgeMarkPalette.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Barcode verification complete")
                    .font(.headline)
                Text("Front OCR was intentionally skipped in Back Only mode. Compare the photo and physical security features by hand.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ComparisonSection: View {
    let comparison: ComparisonResult
    let front: OCRData?
    let back: AAMVAData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Front and back comparison")
                .font(.headline)
            Text("AgeMark compares only the dates read from both sides. Always verify the name, photo, and license number yourself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                MatchRow(
                    title: "Date of birth",
                    status: comparison.dateOfBirth,
                    frontValue: formatted(front?.dateOfBirth),
                    backValue: formatted(back.dateOfBirth)
                )
                Divider().padding(.leading, 16)
                MatchRow(
                    title: "Expiration date",
                    status: comparison.expirationDate,
                    frontValue: formatted(front?.expirationDate),
                    backValue: formatted(back.expirationDate)
                )
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .numeric, time: .omitted) ?? "Unclear"
    }
}

private struct MatchRow: View {
    let title: String
    let status: FieldMatch
    let frontValue: String
    let backValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                Label(status.rawValue, systemImage: icon)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(color.opacity(0.12), in: Capsule())
            }

            if status != .match {
                HStack(spacing: 10) {
                    ComparisonValueCard(label: "FRONT OCR", value: frontValue)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ComparisonValueCard(label: "BACK BARCODE", value: backValue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }

    private var icon: String {
        switch status {
        case .match: "checkmark.circle.fill"
        case .mismatch: "xmark.circle.fill"
        case .unclear: "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .match: AgeMarkPalette.teal
        case .mismatch: AgeMarkPalette.coral
        case .unclear: AgeMarkPalette.amber
        }
    }
}

private struct ComparisonValueCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct VerificationNotes: View {
    let reasons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Review needed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(reasons, id: \.self) { reason in
                Text(reason)
                    .font(.subheadline)
            }
        }
        .foregroundStyle(AgeMarkPalette.amber)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgeMarkPalette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct VerdictActions: View {
    let scanNext: () -> Void
    let manualEntry: () -> Void
    let home: () -> Void
    let toggleDetails: () -> Void
    let showsDetails: Bool

    var body: some View {
        VStack(spacing: 12) {
            Button(action: scanNext) {
                Label("Scan Next ID", systemImage: "viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))

            ViewThatFits {
                HStack(spacing: 12) {
                    secondaryActions
                }
                VStack(spacing: 12) {
                    secondaryActions
                }
            }
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        Button(action: manualEntry) {
            Label("Manual Entry", systemImage: "square.and.pencil")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(PrimaryButtonStyle(color: Color(.secondarySystemBackground)))

        Button(action: toggleDetails) {
            Label(showsDetails ? "Hide Details" : "View Details", systemImage: "list.bullet.rectangle")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(PrimaryButtonStyle(color: Color(.secondarySystemBackground)))

        Button(action: home) {
            Label("Home", systemImage: "house.fill")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(PrimaryButtonStyle(color: Color(.secondarySystemBackground)))
    }
}

private struct BarcodeDetails: View {
    let data: AAMVAData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Barcode details")
                .font(.headline)
            DetailRow(label: "License", value: data.licenseNumber)
            DetailRow(label: "State", value: data.state)
            DetailRow(label: "Issue date", date: data.issueDate)
            DetailRow(label: "Expiration", date: data.expirationDate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String?
    let date: Date?

    init(label: String, value: String?) {
        self.label = label
        self.value = value
        self.date = nil
    }

    init(label: String, date: Date?) {
        self.label = label
        self.value = nil
        self.date = date
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if let value, !value.isEmpty {
                Text(value)
                    .multilineTextAlignment(.trailing)
            } else if let date {
                Text(date, format: .dateTime.month().day().year())
            } else {
                Text("Not provided")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}
