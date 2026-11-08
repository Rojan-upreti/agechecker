import Observation
import StoreKit

@MainActor
@Observable
final class StoreManager {
    static let productID = "net.taxcurb.idchecker.monthly"
    var product: Product?
    var isSubscribed = false
    var errorMessage: String?

    init() {
        Task {
            await load()
            await refreshEntitlements()
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            }
        }
    }

    func load() async {
        do { product = try await Product.products(for: [Self.productID]).first }
        catch { errorMessage = error.localizedDescription }
    }

    func purchase() async {
        guard let product else { return }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified(_, let error)):
                errorMessage = error.localizedDescription
            case .pending, .userCancelled: break
            @unknown default: break
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refreshEntitlements() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                subscribed = true
            }
        }
        isSubscribed = subscribed
    }
}
