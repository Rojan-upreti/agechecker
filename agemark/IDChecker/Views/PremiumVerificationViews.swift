import SwiftUI

struct PremiumIntroductionView: View {
    let model: AppModel
    @State private var consented = false

    var body: some View {
        ZStack {
            AgeMarkPalette.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PremiumNavigationHeader(title: "AI identity verification") {
                        model.cancelPremium()
                    }
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(AgeMarkPalette.teal)
                        .accessibilityHidden(true)
                    Text("Verify the person and their ID")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AgeMarkPalette.navy)
                    Text("You’ll scan both sides of the ID, then follow a short camera check. Images stay in memory for this attempt and are not written to the photo library.")
                        .font(.title3)
                        .foregroundStyle(AgeMarkPalette.slate)
                    PremiumFeatureRow(
                        icon: "rectangle.on.rectangle.angled",
                        title: "Check the document",
                        detail: "Read the barcode and compare key details."
                    )
                    PremiumFeatureRow(
                        icon: "faceid",
                        title: "Capture a live face",
                        detail: "Use guided, randomized head movements."
                    )
                    PremiumFeatureRow(
                        icon: "lock.shield",
                        title: "Fail safely",
                        detail: "Verification cannot pass when required security providers are unavailable."
                    )
                    Toggle(isOn: $consented) {
                        Text("I have the ID holder’s consent to process facial images for identity verification.")
                            .font(.body)
                    }
                    .tint(AgeMarkPalette.teal)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        model.confirmPremiumConsent()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
                    .disabled(!consented)
                    .opacity(consented ? 1 : 0.5)

                    Text("This build has no verification backend or licensed biometric and anti-spoofing models. It will capture and assess quality, but it cannot return Verified.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
    }
}

private struct PremiumNavigationHeader: View {
    let title: LocalizedStringResource
    let closeAction: () -> Void

    var body: some View {
        HStack {
            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .frame(width: 48, height: 48)
                    .background(AgeMarkPalette.navy.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Cancel verification")
            Text(title)
                .font(.headline)
                .foregroundStyle(AgeMarkPalette.navy)
            Spacer()
        }
    }
}

private struct PremiumFeatureRow: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AgeMarkPalette.teal)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AgeMarkPalette.navy)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AgeMarkPalette.slate)
            }
        }
    }
}

struct PremiumDocumentReviewView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            AgeMarkPalette.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PremiumNavigationHeader(title: "Review document") {
                        model.cancelPremium()
                    }
                    Text("Document captured")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AgeMarkPalette.navy)
                    Text("Confirm the ID is readable before continuing to the face check.")
                        .foregroundStyle(AgeMarkPalette.slate)

                    if let image = model.frontImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Captured front of ID")
                    }

                    if let result = model.scanResult {
                        PremiumDocumentSummary(
                            name: result.barcode.displayName,
                            license: result.barcode.licenseNumber,
                            comparison: result.comparison
                        )
                    }

                    if model.isPreparingPortrait {
                        HStack {
                            ProgressView()
                            Text("Finding the portrait on the ID")
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    } else if let message = model.premiumPreparationError {
                        Text(message)
                            .foregroundStyle(AgeMarkPalette.coral)
                            .font(.callout.bold())
                    }

                    Button("Continue to face check") {
                        model.showFaceCapture()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
                    .disabled(model.idPortrait == nil || model.isPreparingPortrait)
                    .opacity(model.idPortrait == nil || model.isPreparingPortrait ? 0.5 : 1)
                }
                .padding(24)
            }
        }
    }
}

private struct PremiumDocumentSummary: View {
    let name: String
    let license: String?
    let comparison: ComparisonResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(name.isEmpty ? "Name unavailable" : name, systemImage: "person.text.rectangle")
            if let license {
                Label(license, systemImage: "number")
            }
            Label(
                comparison?.hasMismatch == true ? "Document details need review" : "Document details captured",
                systemImage: comparison?.hasMismatch == true ? "exclamationmark.triangle" : "checkmark.circle"
            )
        }
        .font(.headline)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct FaceCaptureView: View {
    let model: AppModel
    @State private var coordinator: PremiumVerificationCoordinator

    init(model: AppModel, portrait: UIImage) {
        self.model = model
        _coordinator = State(initialValue: PremiumVerificationCoordinator(
            portrait: portrait,
            initialEvidence: model.premiumEvidence,
            session: model.premiumSession
        ) { decision in
            model.finishPremium(decision)
        })
    }

    var body: some View {
        ZStack {
            CameraPreview(session: coordinator.camera.session)
                .ignoresSafeArea()
            Color.black.opacity(0.16).ignoresSafeArea()
            FaceGuideOverlay(
                stage: coordinator.stage,
                feedback: coordinator.feedback,
                progress: coordinator.progress,
                currentStep: coordinator.currentStep,
                totalSteps: coordinator.totalSteps,
                cancelAction: {
                    coordinator.cancel()
                    model.cancelPremium()
                },
                retryAction: coordinator.retry
            )
        }
        .preferredColorScheme(.dark)
        .onAppear { coordinator.start() }
        .onDisappear { coordinator.cancel() }
    }
}

private struct FaceGuideOverlay: View {
    let stage: FaceCaptureStage
    let feedback: String
    let progress: Double
    let currentStep: Int
    let totalSteps: Int
    let cancelAction: () -> Void
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: cancelAction) {
                    Image(systemName: "xmark")
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Cancel facial verification")
                Spacer()
                Text("Face check")
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 48, height: 48)
            }
            .padding(.horizontal)

            FaceCaptureProgressView(
                currentStep: currentStep,
                totalSteps: totalSteps,
                progress: progress
            )
            .padding(.horizontal)

            Spacer()

            Ellipse()
                .strokeBorder(guideColor, style: StrokeStyle(lineWidth: 4, dash: [12, 7]))
                .frame(maxWidth: 300, maxHeight: 410)
                .aspectRatio(0.73, contentMode: .fit)
                .shadow(color: guideColor.opacity(0.5), radius: 12)
                .accessibilityHidden(true)

            Spacer()

            VStack(spacing: 12) {
                FaceDirectionHint(stage: stage)
                Text(stage.instruction)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(feedback)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                if case .failed = stage {
                    Button("Try Again", action: retryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(AgeMarkPalette.teal)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.25), value: stage)
    }

    private var guideColor: Color {
        switch stage {
        case .analyzing, .complete: AgeMarkPalette.teal
        case .failed: AgeMarkPalette.coral
        default: .white
        }
    }
}

private struct FaceCaptureProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    let progress: Double

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.subheadline.bold())
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit().bold())
            }

            ProgressView(value: progress)
                .tint(AgeMarkPalette.teal)
                .scaleEffect(y: 1.6)

            HStack(spacing: 6) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? AgeMarkPalette.teal : Color.white.opacity(0.3))
                        .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Face capture step \(currentStep) of \(totalSteps)")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct FaceDirectionHint: View {
    let stage: FaceCaptureStage

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.largeTitle.bold())
                .foregroundStyle(AgeMarkPalette.teal)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String? {
        switch stage {
        case .turnLeft: "arrow.left.circle.fill"
        case .turnRight: "arrow.right.circle.fill"
        case .returnToCenter: "scope"
        case .analyzing: "checkmark.circle.fill"
        default: nil
        }
    }
}

struct PremiumResultView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            AgeMarkPalette.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: icon)
                        .font(.system(size: 64))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(AgeMarkPalette.navy)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(AgeMarkPalette.slate)
                        .multilineTextAlignment(.center)

                    if let decision = model.premiumDecision {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(decision.reasons, id: \.self) { reason in
                                Label(reason, systemImage: "info.circle")
                                    .font(.callout)
                            }
                            Text("Policy: \(decision.policyVersion)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }

                    Button("Done") { model.cancelPremium() }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.navy))
                }
                .padding(24)
            }
        }
    }

    private var outcome: PremiumVerificationOutcome {
        model.premiumDecision?.outcome ?? .verificationUnavailable
    }

    private var title: LocalizedStringResource {
        switch outcome {
        case .verified: "Identity verified"
        case .retryRequired: "Try the capture again"
        case .manualReviewRequired: "Manual review required"
        case .verificationUnavailable: "Verification unavailable"
        case .rejected: "Verification not approved"
        }
    }

    private var message: LocalizedStringResource {
        switch outcome {
        case .verified: "All required checks passed and the server confirmed the result."
        case .retryRequired: "The capture did not provide enough clear evidence."
        case .manualReviewRequired: "The evidence needs a trained reviewer."
        case .verificationUnavailable: "A required secure verification component is not configured."
        case .rejected: "Strong evidence did not meet the documented verification policy."
        }
    }

    private var icon: String {
        outcome == .verified ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var color: Color {
        outcome == .verified ? AgeMarkPalette.teal : AgeMarkPalette.amber
    }
}
