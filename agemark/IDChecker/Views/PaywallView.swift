import StoreKit
import SwiftUI

struct PaywallView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 80))
                .foregroundStyle(AgeMarkPalette.teal)
            Text("Premium Verification")
                .font(.largeTitle.bold())
            Text("A verified Premium entitlement is required for advanced face verification. Signing in alone does not activate Premium.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                if let product = model.store.product {
                    Text(product.displayPrice)
                        .font(.system(size: 48, weight: .bold))
                    Text("per month")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading subscription details…")
                }
            }
            Button("Continue") {
                Task {
                    await model.store.purchase()
                    if model.store.isSubscribed {
                        model.beginScan(tier: .premium)
                    }
                }
            }
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
            .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
            .disabled(model.store.product == nil)
            Button("Restore Purchase") {
                Task {
                    await model.store.restore()
                    if model.store.isSubscribed {
                        model.beginScan(tier: .premium)
                    }
                }
            }
            .frame(minHeight: 56)
            if let error = model.store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Not Now") { model.screen = .home }
            Text("Payment is processed by Apple. Available products, prices, and subscription terms are shown in Apple’s purchase sheet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(28)
    }
}
