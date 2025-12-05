// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import Observation
import OSLog
import StoreKit
import SwiftData

@MainActor
@Observable
final class LevelPackStore {
    enum StoreError: LocalizedError {
        case productUnavailable
        case failedVerification(Error?)
        case productRequestFailed(Error)
        case purchaseFailed(Error)
        case restoreFailed(Error)

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                String(localized: .settingsLevelPackErrorUnavailable)
            case .failedVerification:
                String(localized: .settingsLevelPackErrorVerification)
            case .productRequestFailed:
                String(localized: .settingsLevelPackErrorRequest)
            case .purchaseFailed:
                String(localized: .settingsLevelPackErrorPurchase)
            case .restoreFailed:
                String(localized: .settingsLevelPackErrorRestore)
            }
        }
    }

    private(set) var availableProducts: [String: Product] = [:] // keyed by productID
    private(set) var purchasedPackIDs: Set<String> = []
    private(set) var isLoading: Bool = false
    private(set) var purchaseInProgress: Bool = false
    var purchaseError: StoreError?

    @ObservationIgnored
    private let logger = Logger(subsystem: "PotatoGame", category: "LevelPackStore")

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?
    @ObservationIgnored
    private var configurationTask: Task<Void, Never>?
    @ObservationIgnored
    private var modelContext: ModelContext?
    @ObservationIgnored
    private weak var account: Account?

    init() {
        if ProcessInfo.isRunningPreviews {
            updatesTask = nil
        } else {
            updatesTask = Task { await observeTransactions() }
        }
    }

    deinit {
        updatesTask?.cancel()
        configurationTask?.cancel()
    }

    var primaryPack: LevelPackDefinition? {
        LevelPackRegistry.primaryPack
    }

    var isPrimaryPackUnlocked: Bool {
        guard let primaryPack else { return false }
        return purchasedPackIDs.contains(primaryPack.id)
    }

    func configure(with context: ModelContext, account: Account?) {
        modelContext = context
        self.account = account
        purchasedPackIDs = account?.ownedLevelPackIDs ?? []

        guard ProcessInfo.isRunningPreviews == false else { return }

        configurationTask?.cancel()
        configurationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await loadProductsIfNeeded()
            } catch {
                if let storeError = error as? StoreError {
                    purchaseError = storeError
                } else {
                    purchaseError = .productRequestFailed(error)
                }
            }
            await refreshEntitlements()
        }
    }

    func product(for pack: LevelPackDefinition) -> Product? {
        availableProducts[pack.productID]
    }

    func purchasePrimaryPack() async {
        guard let pack = primaryPack else {
            purchaseError = .productUnavailable
            return
        }
        await purchase(pack: pack)
    }

    func purchase(pack: LevelPackDefinition) async {
        do {
            try await loadProductsIfNeeded()
            guard let product = product(for: pack) else {
                throw StoreError.productUnavailable
            }
            purchaseInProgress = true
            defer { purchaseInProgress = false }

            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await applyPurchase(from: transaction)
                await transaction.finish()
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            if let storeError = error as? StoreError {
                purchaseError = storeError
            } else {
                purchaseError = .purchaseFailed(error)
            }
        }
    }

    func restorePurchases() async {
        do {
            isLoading = true
            defer { isLoading = false }
            try await AppStore.sync()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            purchaseError = .restoreFailed(error)
        }
    }
}

private extension LevelPackStore {
    func loadProductsIfNeeded() async throws {
        let knownProductIDs = Set(availableProducts.keys)
        let requestedIDs = Set(LevelPackRegistry.productIDs())
        let missingIDs = requestedIDs.subtracting(knownProductIDs)
        guard missingIDs.isEmpty == false else { return }
        isLoading = true
        defer { isLoading = false }
        let products = try await Product.products(for: Array(missingIDs))
        for product in products {
            availableProducts[product.id] = product
        }
    }

    func refreshEntitlements() async {
        var ownedPackIDs: Set<String> = []
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if let pack = LevelPackRegistry.definition(forProductID: transaction.productID) {
                    ownedPackIDs.insert(pack.id)
                    await applyPurchase(from: transaction)
                }
            } catch {
                logger.error("Failed to verify entitlement: \(error.localizedDescription, privacy: .public)")
                purchaseError = .failedVerification(error)
            }
        }

        updateOwnership(for: ownedPackIDs)

        if let account {
            account.purchasedLevelPackIDs = ownedPackIDs.sorted()
            do {
                try modelContext?.save()
            } catch {
                logger.error("Failed to persist entitlement refresh: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func observeTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)
                guard LevelPackRegistry.definition(forProductID: transaction.productID) != nil else {
                    await transaction.finish()
                    continue
                }
                await applyPurchase(from: transaction)
                await transaction.finish()
            } catch {
                logger.error("Transaction verification failed: \(error.localizedDescription, privacy: .public)")
                purchaseError = .failedVerification(error)
            }
        }
    }

    func applyPurchase(from transaction: Transaction) async {
        guard let pack = LevelPackRegistry.definition(forProductID: transaction.productID) else { return }
        var updated = purchasedPackIDs
        updated.insert(pack.id)
        updateOwnership(for: updated)
        account?.registerPurchase(for: transaction.productID)
        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to persist Level Pack purchase: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateOwnership(for packIDs: Set<String>) {
        guard purchasedPackIDs != packIDs else { return }
        purchasedPackIDs = packIDs
    }

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(transaction):
            return transaction
        case let .unverified(_, error):
            throw StoreError.failedVerification(error)
        }
    }
}

extension LevelPackStore {
    /// Lightweight configuration used by SwiftUI previews to avoid StoreKit/entitlement work.
    func configureForPreviews(purchasedPackIDs: Set<String> = []) {
        guard ProcessInfo.isRunningPreviews else { return }
        self.purchasedPackIDs = purchasedPackIDs
        availableProducts = [:]
        isLoading = false
        purchaseInProgress = false
        purchaseError = nil
    }
}
