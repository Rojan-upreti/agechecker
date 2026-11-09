import SwiftUI

struct SignInView: View {
    let authentication: AuthenticationManager
    let purpose: RequestedAuthenticatedAction
    let closeAction: () -> Void
    let completionAction: () -> Void

    var body: some View {
        ZStack {
            AgeMarkPalette.navy.ignoresSafeArea()
            VStack(spacing: 24) {
                AuthenticationCloseButton(action: closeAction)
                Spacer()
                AuthenticationMessage(purpose: purpose)
                if let message = authentication.errorMessage {
                    AuthenticationErrorMessage(message: message)
                }
                AuthenticationActions(
                    authentication: authentication,
                    purpose: purpose,
                    completionAction: completionAction
                )
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}

private struct AuthenticationCloseButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Not now")
            Spacer()
        }
    }
}

private struct AuthenticationMessage: View {
    let purpose: RequestedAuthenticatedAction

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 62))
                .foregroundStyle(AgeMarkPalette.teal)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var title: LocalizedStringResource {
        switch purpose {
        case .regularScan: "Continue Verifying Identities"
        case .premiumVerification: "Secure Identity Verification"
        case .accountManagement: "Your Account"
        }
    }

    private var message: LocalizedStringResource {
        switch purpose {
        case .regularScan:
            "You’ve used your 5 free scans for today. Create an account or sign in to continue scanning."
        case .premiumVerification:
            "Sign in or create an account to check eligibility for advanced face verification and identity matching."
        case .accountManagement:
            "Sign in or create an account using the secure system browser."
        }
    }
}

private struct AuthenticationErrorMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .padding()
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct AuthenticationActions: View {
    let authentication: AuthenticationManager
    let purpose: RequestedAuthenticatedAction
    let completionAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button {
                authenticate(intent: primaryIntent)
            } label: {
                AuthenticationButtonLabel(
                    title: primaryTitle,
                    isLoading: authentication.status == .signingIn
                )
            }
            .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
            .disabled(authentication.status == .signingIn)

            Button(secondaryTitle) {
                authenticate(intent: secondaryIntent)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .buttonStyle(.bordered)
            .disabled(authentication.status == .signingIn)

            Text("Authentication opens in the system browser. This app never collects your password.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Account creation is available only when enabled by your organization’s Cognito configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var primaryTitle: LocalizedStringResource {
        purpose == .regularScan ? "Create Account" : "Continue with Account"
    }

    private var secondaryTitle: LocalizedStringResource {
        purpose == .regularScan ? "Sign In" : "Create Account"
    }

    private var primaryIntent: AuthenticationIntent {
        purpose == .regularScan ? .createAccount : .signIn
    }

    private var secondaryIntent: AuthenticationIntent {
        purpose == .regularScan ? .signIn : .createAccount
    }

    private func authenticate(intent: AuthenticationIntent) {
        Task {
            await authentication.signIn(intent: intent)
            if authentication.isAuthenticated {
                completionAction()
            }
        }
    }
}

private struct AuthenticationButtonLabel: View {
    let title: LocalizedStringResource
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .accessibilityLabel("Signing in")
        } else {
            Label(title, systemImage: "lock.shield.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 58)
        }
    }
}

struct GuestScanLimitView: View {
    let createAccountAction: () -> Void
    let signInAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 66))
                    .foregroundStyle(AgeMarkPalette.teal)
                    .accessibilityHidden(true)
                Text("Continue Verifying Identities")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("You’ve used your 5 free scans for today. Create an account or sign in to continue scanning.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Create Account", action: createAccountAction)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
                Button("Sign In", action: signInAction)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .buttonStyle(.bordered)
                Text("Your free guest scans reset daily at 00:00 UTC.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not Now", action: closeAction)
                }
            }
        }
    }
}

struct AccountView: View {
    let authentication: AuthenticationManager
    let accessState: FeatureAccessState
    let historyRetentionHours: Int
    let closeAction: () -> Void

    var body: some View {
        NavigationStack {
            AccountContent(
                authentication: authentication,
                accessState: accessState,
                historyRetentionHours: historyRetentionHours
            )
            .padding(24)
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: closeAction)
                }
            }
        }
    }
}

private struct AccountContent: View {
    let authentication: AuthenticationManager
    let accessState: FeatureAccessState
    let historyRetentionHours: Int

    var body: some View {
        switch authentication.status {
        case .restoring:
            ProgressView("Restoring secure session…")
        case .signingIn:
            ProgressView("Signing in…")
        case .signedOut:
            SignedOutAccountContent(authentication: authentication)
        case .authenticated(let user):
            AuthenticatedAccountContent(
                authentication: authentication,
                user: user,
                accessState: accessState,
                historyRetentionHours: historyRetentionHours
            )
        }
    }
}

private struct SignedOutAccountContent: View {
    let authentication: AuthenticationManager

    var body: some View {
        ContentUnavailableView {
            Label("Guest Access", systemImage: "person.crop.circle")
        } description: {
            Text("Sign in to continue regular scanning after the daily guest allowance and to check Premium eligibility.")
        } actions: {
            Button("Sign In") {
                Task { await authentication.signIn(intent: .signIn) }
            }
            .buttonStyle(.borderedProminent)
            .tint(AgeMarkPalette.teal)

            Button("Create Account") {
                Task { await authentication.signIn(intent: .createAccount) }
            }
        }
    }
}

private struct AuthenticatedAccountContent: View {
    let authentication: AuthenticationManager
    let user: AuthorizedUser
    let accessState: FeatureAccessState
    let historyRetentionHours: Int

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 70))
                .foregroundStyle(AgeMarkPalette.teal)
            Text(user.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let email = user.email {
                Text(email).foregroundStyle(.secondary)
            }
            Label(accessLabel, systemImage: accessImage)
                .foregroundStyle(AgeMarkPalette.teal)
            Text("Organization permissions and verification access remain controlled by the service.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink("Scan History") {
                ScanHistoryView(retentionHours: historyRetentionHours)
            }
            .buttonStyle(.bordered)
            Spacer()
            Button("Sign Out", role: .destructive) {
                Task { await authentication.signOut() }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .buttonStyle(.bordered)
        }
    }

    private var accessLabel: LocalizedStringResource {
        accessState == .premiumEntitled
            ? "Premium Entitlement Active"
            : "Signed In — Premium Not Active"
    }

    private var accessImage: String {
        accessState == .premiumEntitled ? "checkmark.shield.fill" : "person.badge.shield.checkmark"
    }
}

private struct ScanHistoryView: View {
    let retentionHours: Int
    @State private var entries: [ScanLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Scan History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed signed-in scans will appear here.")
                )
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.verdict.rawValue)
                            .font(.headline)
                        Text(entry.ageBracket == "OVER" ? "Over threshold" : "Under threshold")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(
                            entry.timestamp,
                            format: .dateTime.month().day().year().hour().minute()
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Scan History")
        .task {
            entries = ScanLogger.shared.load(
                retentionHours: retentionHours,
                isAuthenticated: true
            )
        }
    }
}
