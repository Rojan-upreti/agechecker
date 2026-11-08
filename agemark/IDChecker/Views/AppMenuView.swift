import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case about = "About"
    case contact = "Contact"
    case privacy = "Privacy Policy"
    case pricing = "Pricing"
    case terms = "Terms & Conditions"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .about: "info.circle.fill"
        case .contact: "envelope.fill"
        case .privacy: "hand.raised.fill"
        case .pricing: "creditcard.fill"
        case .terms: "doc.text.fill"
        }
    }
}

struct SideNavigationView: View {
    @Binding var selectedSection: AppSection
    @Binding var isPresented: Bool
    let settingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image("AgeMarkLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AgeMark")
                        .font(.title2.bold())
                    Text("Taxcurb LLC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { isPresented = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Close navigation menu")
            }
            .padding(.bottom, 16)

            Text("NAVIGATION")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            ForEach(AppSection.allCases) { section in
                NavigationMenuRow(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                    withAnimation(.snappy) { isPresented = false }
                }
            }

            Divider()
                .padding(.vertical, 8)

            Button(action: settingsAction) {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.primary)
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Private by design")
                    .font(.caption.bold())
                Text("ID information stays on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
        }
        .padding(20)
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
        }
    }
}

private struct NavigationMenuRow: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: section.systemImage)
                    .frame(width: 24)
                Text(section.rawValue)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 14)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? AgeMarkPalette.teal : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct InformationPageView: View {
    let section: AppSection
    let closeAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHero(section: section)
                    switch section {
                    case .about: AboutContent()
                    case .contact: ContactContent()
                    case .privacy: PrivacyContent()
                    case .pricing: PricingContent()
                    case .terms: TermsContent()
                    case .home: EmptyView()
                    }
                }
                .padding(22)
            }
            .background(Color(.systemBackground))
            .navigationTitle(section.rawValue)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: closeAction) {
                        Label("Menu", systemImage: "line.3.horizontal")
                    }
                }
            }
        }
    }
}

private struct PageHero: View {
    let section: AppSection

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: section.systemImage)
                .font(.largeTitle)
                .foregroundStyle(AgeMarkPalette.teal)
                .frame(width: 64, height: 64)
                .background(AgeMarkPalette.teal.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 5) {
                Text(section.rawValue).font(.largeTitle.bold())
                Text("AgeMark • Taxcurb LLC").foregroundStyle(.secondary)
            }
        }
    }
}

private struct AboutContent: View {
    var body: some View {
        LegalSection(title: "About AgeMark") {
            Text("AgeMark is an offline-first age-verification aid designed for bars, restaurants, liquor stores, and other age-restricted businesses. It reads supported US driver-license and identification-card data using on-device Apple technologies.")
            Text("AgeMark is owned and operated by Taxcurb LLC. Taxcurb LLC develops privacy-conscious software that helps businesses complete routine checks quickly and consistently.")
            Text("AgeMark does not authenticate an ID, determine whether an ID is genuine, or replace staff judgment. Staff must always compare the person to the ID photo and inspect physical security features.")
        }
    }
}

private struct ContactContent: View {
    var body: some View {
        LegalSection(title: "Contact Taxcurb LLC") {
            Text("For product support, billing questions, privacy requests, or legal notices, contact:")
            Link(destination: URL(string: "mailto:rojan@taxcurb.net")!) {
                Label("rojan@taxcurb.net", systemImage: "envelope.fill")
                    .font(.headline)
                    .foregroundStyle(AgeMarkPalette.teal)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }
            Text("Please do not email photographs of IDs, license numbers, dates of birth, or other sensitive identification information.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrivacyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LegalSection(title: "Privacy Policy") {
                Text("Effective date: November 7, 2026")
                Text("AgeMark is designed to perform age-verification processing on the device. Taxcurb LLC does not operate an AgeMark account system and the app does not upload scanned ID images or extracted ID details to Taxcurb LLC.")
            }
            LegalSection(title: "Information Processed") {
                Text("During a scan, AgeMark may temporarily process an ID image, barcode data, name, date of birth, expiration date, and license number in memory. This information is used only to calculate an age-verification result and compare the front and back of the ID.")
            }
            LegalSection(title: "Information Stored") {
                Text("AgeMark does not store ID photos, names, dates of birth, addresses, or license numbers. If privacy logging is enabled, the app stores only a one-way SHA-256 hash of the license number, an age bracket, the verdict, and a timestamp. Logs automatically expire according to the selected retention setting.")
            }
            LegalSection(title: "Purchases") {
                Text("Subscriptions are processed by Apple through StoreKit. Apple may process purchase, billing, and account information under Apple’s own privacy policy. Taxcurb LLC receives subscription status but does not receive full payment-card details.")
            }
            LegalSection(title: "Sharing and Tracking") {
                Text("AgeMark contains no advertising SDK, third-party analytics SDK, or sale of personal information. Taxcurb LLC does not use scanned identification information for tracking, profiling, or marketing.")
            }
            LegalSection(title: "Your Choices") {
                Text("You can clear the privacy log in Settings, change the retention period, or delete the app to remove locally stored AgeMark settings and logs. For privacy questions, contact rojan@taxcurb.net.")
            }
            LegalSection(title: "Security and Changes") {
                Text("AgeMark minimizes retained data and relies on iOS application protections. No security method is absolute. Taxcurb LLC may update this policy as the product changes; material revisions will be reflected in the app with a new effective date.")
            }
        }
    }
}

private struct PricingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LegalSection(title: "Simple Pricing") {
                Text("The first 10 scans each month are free. A paid subscription unlocks unlimited scans while the subscription is active.")
            }
            PriceCard(
                title: "Monthly",
                price: "$10",
                detail: "per month, billed monthly",
                badge: "Flexible"
            )
            PriceCard(
                title: "Annual",
                price: "$96",
                detail: "$8 per month, billed annually as $96",
                badge: "Best Value"
            )
            Text("Actual products, introductory offers, taxes, and localized prices shown during purchase are controlled by App Store Connect and Apple’s purchase sheet. Subscriptions renew automatically unless canceled at least 24 hours before renewal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PriceCard: View {
    let title: LocalizedStringResource
    let price: LocalizedStringResource
    let detail: LocalizedStringResource
    let badge: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Text(badge).font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6).background(AgeMarkPalette.teal).clipShape(Capsule())
            }
            Text(price).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(detail).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct TermsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LegalSection(title: "Terms & Conditions") {
                Text("Effective date: November 7, 2026")
                Text("These Terms govern use of AgeMark, provided by Taxcurb LLC. By using AgeMark, you agree to these Terms. If you use AgeMark for an organization, you represent that you have authority to accept these Terms for that organization.")
            }
            LegalSection(title: "Age-Verification Aid") {
                Text("AgeMark provides an informational calculation based on scanned or manually entered data. It does not certify that an ID is genuine, confirm a person’s identity, perform face matching, or guarantee compliance with any law. You remain responsible for training staff, inspecting IDs, following applicable law, and deciding whether to complete a transaction.")
            }
            LegalSection(title: "Permitted Use") {
                Text("You may use AgeMark only for lawful age-verification activities. You may not use it to harass, discriminate, conduct unauthorized surveillance, retain identification data unlawfully, reverse engineer the app except where law permits, interfere with app security, or misrepresent an AgeMark result as government certification.")
            }
            LegalSection(title: "Subscriptions") {
                Text("Paid subscriptions are purchased through Apple. Prices and trial eligibility appear in Apple’s purchase sheet. Subscriptions automatically renew unless canceled through Apple at least 24 hours before the current period ends. Refund requests are handled under Apple’s policies.")
            }
            LegalSection(title: "Availability and Updates") {
                Text("Taxcurb LLC may update, improve, suspend, or discontinue features. Device capabilities, ID formats, lighting, damage, and barcode quality can affect results. You are responsible for maintaining compatible hardware and current software.")
            }
            LegalSection(title: "Disclaimer") {
                Text("TO THE MAXIMUM EXTENT PERMITTED BY LAW, AGEMARK IS PROVIDED “AS IS” AND “AS AVAILABLE,” WITHOUT WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, ACCURACY, NON-INFRINGEMENT, OR UNINTERRUPTED OPERATION.")
            }
            LegalSection(title: "Limitation of Liability") {
                Text("TO THE MAXIMUM EXTENT PERMITTED BY LAW, TAXCURB LLC WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, LOST PROFITS, LOST DATA, DENIED OR IMPROPER SALES, REGULATORY PENALTIES, OR RELIANCE ON AN AGEMARK RESULT. TAXCURB LLC’S TOTAL LIABILITY WILL NOT EXCEED THE AMOUNT YOU PAID FOR AGEMARK DURING THE 12 MONTHS BEFORE THE CLAIM.")
            }
            LegalSection(title: "Responsibility and Indemnity") {
                Text("You are responsible for your use of AgeMark and for compliance with privacy, alcohol, tobacco, employment, and age-restricted-sales laws. To the extent permitted by law, you agree to defend and indemnify Taxcurb LLC from claims arising from unlawful use, misuse of scanned information, or violation of these Terms.")
            }
            LegalSection(title: "General Terms") {
                Text("If a provision is unenforceable, the remaining provisions remain effective. Failure to enforce a provision is not a waiver. These Terms constitute the agreement concerning AgeMark, together with Apple’s applicable App Store terms. Questions or legal notices may be sent to rojan@taxcurb.net.")
            }
        }
    }
}

struct LegalSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    init(title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            content
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
