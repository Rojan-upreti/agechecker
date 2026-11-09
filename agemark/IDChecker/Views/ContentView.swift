import SwiftUI

enum AgeMarkPalette {
    static let cream = Color(red: 0.965, green: 0.941, blue: 0.890)
    static let navy = Color(red: 0.075, green: 0.145, blue: 0.235)
    static let teal = Color(red: 0.145, green: 0.475, blue: 0.455)
    static let amber = Color(red: 0.835, green: 0.565, blue: 0.180)
    static let coral = Color(red: 0.760, green: 0.255, blue: 0.225)
    static let slate = Color(red: 0.285, green: 0.345, blue: 0.390)
}

private enum LaunchPhase {
    case splash
    case onboarding
    case app
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    @State private var launchPhase: LaunchPhase = .splash
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredFastMode") private var preferredFastMode = false
    @AppStorage("preferredAgeThreshold") private var preferredAgeThreshold = 21
    @AppStorage("preferredVerificationTier") private var preferredVerificationTier = VerificationTier.base.rawValue

    var body: some View {
        ZStack {
            switch launchPhase {
            case .splash:
                AgeMarkSplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView(
                    initialFastMode: preferredFastMode,
                    initialThreshold: preferredAgeThreshold,
                    initialTier: VerificationTier(rawValue: preferredVerificationTier) ?? .base
                ) { fastMode, threshold, tier in
                    preferredFastMode = fastMode
                    preferredAgeThreshold = threshold
                    preferredVerificationTier = tier.rawValue
                    hasCompletedOnboarding = true
                    model.fastMode = fastMode
                    model.threshold = threshold
                    model.verificationTier = tier
                    withAnimation(.easeInOut(duration: 0.45)) {
                        launchPhase = .app
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
            case .app:
                MainAppView(model: model)
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.scanUsage.refresh() }
        }
        .task {
            await model.authentication.restoreSession()
            guard launchPhase == .splash else { return }
            try? await Task.sleep(for: .seconds(3))
            model.fastMode = preferredFastMode
            model.threshold = preferredAgeThreshold
            model.verificationTier = VerificationTier(rawValue: preferredVerificationTier) ?? .base
            withAnimation(.easeInOut(duration: 0.55)) {
                launchPhase = hasCompletedOnboarding ? .app : .onboarding
            }
        }
    }
}

private struct MainAppView: View {
    let model: AppModel
    @State private var selectedSection: AppSection = .home
    @State private var isMenuPresented = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color(.systemBackground).ignoresSafeArea()

            switch model.screen {
            case .home:
                if selectedSection == .home {
                    HomeView(
                        model: model,
                        menuAction: { withAnimation(.snappy) { isMenuPresented = true } }
                    )
                } else {
                    InformationPageView(
                        section: selectedSection,
                        closeAction: { withAnimation(.snappy) { isMenuPresented = true } }
                    )
                }
            case .front:
                ScanFrontView(model: model)
            case .back:
                ScanBackView(model: model)
            case .verdict:
                VerdictView(model: model)
            case .manual:
                ManualEntryView(model: model)
            case .settings:
                SettingsView(model: model)
            case .paywall:
                PaywallView(model: model)
            case .premiumIntroduction:
                PremiumIntroductionView(model: model)
            case .premiumDocumentReview:
                PremiumDocumentReviewView(model: model)
            case .faceCapture:
                if let portrait = model.idPortrait {
                    FaceCaptureView(model: model, portrait: portrait)
                } else {
                    PremiumDocumentReviewView(model: model)
                }
            case .premiumResult:
                PremiumResultView(model: model)
            case .signIn:
                SignInView(
                    authentication: model.authentication,
                    purpose: model.requestedAuthenticatedAction,
                    closeAction: { model.cancelAuthentication() },
                    completionAction: { model.authenticationCompleted() }
                )
            case .account:
                AccountView(
                    authentication: model.authentication,
                    accessState: FeatureAccessManager.state(
                        isAuthenticated: model.authentication.isAuthenticated,
                        entitlement: FeatureAccessManager.premiumEntitlement(from: model.store)
                    ),
                    historyRetentionHours: model.logRetentionHours,
                    closeAction: { model.screen = .home }
                )
            case .guestScanLimit:
                GuestScanLimitView(
                    createAccountAction: {
                        Task {
                            await model.authentication.signIn(intent: .createAccount)
                            model.authenticationCompleted()
                        }
                    },
                    signInAction: {
                        Task {
                            await model.authentication.signIn(intent: .signIn)
                            model.authenticationCompleted()
                        }
                    },
                    closeAction: { model.screen = .home }
                )
            }

            if isMenuPresented, model.screen == .home {
                AgeMarkPalette.navy.opacity(0.58)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.snappy) { isMenuPresented = false }
                    }
                    .transition(.opacity)

                SideNavigationView(
                    selectedSection: $selectedSection,
                    isPresented: $isMenuPresented,
                    settingsAction: {
                        isMenuPresented = false
                        model.screen = .settings
                    }
                )
                .transition(.move(edge: .leading))
            }
        }
        .preferredColorScheme(model.theme.colorScheme)
    }
}

private struct HomeView: View {
    let model: AppModel
    let menuAction: () -> Void
    @State private var showingPaste = false
    @State private var pasted = ""

    var body: some View {
        VStack(spacing: 24) {
            HomeHeader(
                menuAction: menuAction,
                accountAction: { model.screen = .account },
                isAuthenticated: model.authentication.isAuthenticated
            )
            Spacer()
            HomeScanActions(
                baseAction: { model.beginScan(tier: .base) },
                premiumAction: { model.beginScan(tier: .premium) }
            )
            Button("Paste Barcode") {
                showingPaste = true
            }
            .frame(minHeight: 56)
            GuestUsageIndicator(
                isAuthenticated: model.authentication.isAuthenticated,
                remaining: model.scanUsage.remainingToday
            )
            Text(model.fastMode ? "Mode: Back barcode only • Age \(model.threshold)+" : "Mode: Both sides • Age \(model.threshold)+")
                .font(.caption.bold())
                .foregroundStyle(AgeMarkPalette.teal)
            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $showingPaste) {
            NavigationStack {
                VStack(spacing: 18) {
                    Text("Paste raw AAMVA PDF417 data below. The data is processed only on this device.")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $pasted)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Button("Parse Barcode") {
                        showingPaste = false
                        model.pasteBarcode(pasted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(PrimaryButtonStyle(color: .blue))
                }
                .padding()
                .navigationTitle("Paste AAMVA Barcode")
            }
            .preferredColorScheme(model.theme.colorScheme)
        }
    }
}

private struct GuestUsageIndicator: View {
    let isAuthenticated: Bool
    let remaining: Int

    var body: some View {
        if isAuthenticated {
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AgeMarkPalette.teal)
        } else {
            Text("\(remaining) of 5 free scans remaining today")
                .font(.footnote.weight(remaining == 1 ? .bold : .medium))
                .foregroundStyle(remaining <= 1 ? AgeMarkPalette.amber : .secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel("\(remaining) of 5 free identity scans remaining today")
        }
    }
}

private struct HomeHeader: View {
    let menuAction: () -> Void
    let accountAction: () -> Void
    let isAuthenticated: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button(action: menuAction) {
                Image(systemName: "line.3.horizontal")
                    .font(.title2.bold())
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Open navigation menu")

            Image("AgeMarkLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("AgeMark").font(.title.bold())
                Text("Fast, private age verification")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: accountAction) {
                Image(systemName: isAuthenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel(isAuthenticated ? "Authorized user account" : "Sign in")
        }
    }
}

private struct HomeScanActions: View {
    let baseAction: () -> Void
    let premiumAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Button(action: baseAction) {
                Label("BASE ID CHECK", systemImage: "viewfinder")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
            .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))

            Button(action: premiumAction) {
                Label("PREMIUM IDENTITY CHECK", systemImage: "person.badge.shield.checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 66)
            }
            .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.navy))

        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
