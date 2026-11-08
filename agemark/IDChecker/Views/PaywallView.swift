import StoreKit
import SwiftUI

struct PaywallView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "infinity.circle.fill").font(.system(size: 80)).foregroundStyle(.blue)
            Text("Unlimited ID Scans").font(.largeTitle.bold())
            Text("Scan without monthly limits. Includes a 7-day free trial for eligible new subscribers.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(model.store.product?.displayPrice ?? "$10.00").font(.system(size: 48, weight: .bold))
                Text("per month").foregroundStyle(.secondary)
            }
            Button("Start Free Trial") { Task { await model.store.purchase(); if model.store.isSubscribed { model.screen = .home } } }
                .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 64).buttonStyle(PrimaryButtonStyle(color: .blue))
            Button("Restore Purchase") { Task { await model.store.restore(); if model.store.isSubscribed { model.screen = .home } } }
                .frame(minHeight: 56)
            if let error = model.store.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Not Now") { model.screen = .home }
            Text("Payment is charged through your Apple ID. Subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }.padding(28)
    }
}
