import Foundation

enum PremiumEntitlementState: Equatable, Sendable {
    case checking
    case notEntitled
    case entitled
}

enum FeatureAccessState: Equatable, Sendable {
    case guest
    case authenticatedWithoutPremium
    case premiumEntitled
}

enum RequestedAuthenticatedAction: Equatable, Sendable {
    case regularScan
    case premiumVerification
    case accountManagement
}

@MainActor
enum FeatureAccessManager {
    static func state(
        isAuthenticated: Bool,
        entitlement: PremiumEntitlementState
    ) -> FeatureAccessState {
        guard isAuthenticated else { return .guest }
        return entitlement == .entitled ? .premiumEntitled : .authenticatedWithoutPremium
    }

    static func premiumEntitlement(from store: StoreManager) -> PremiumEntitlementState {
        if store.isLoadingEntitlements { return .checking }
        return store.isSubscribed ? .entitled : .notEntitled
    }
}
