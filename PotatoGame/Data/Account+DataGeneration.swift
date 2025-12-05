// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "PotatoGame", category: "Account Generation")

extension Account {
    static func generateAccount(modelContext: ModelContext, userID: String) {
        logger.info("Generating/Fetching Account")

        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == userID }
        )
        descriptor.includePendingChanges = true

        let accounts = (try? modelContext.fetch(descriptor)) ?? []

        if let primary = accounts.first {
            if accounts.count > 1 {
                accounts.dropFirst().forEach { modelContext.delete($0) }
                do {
                    try modelContext.save()
                    logger.info("Removed duplicate Account records for id \(userID, privacy: .public)")
                } catch {
                    logger.error("Failed to prune duplicate Account records: \(error.localizedDescription, privacy: .public)")
                }
            }
            logger.info("Account already exists")
            primary.updateWidgetPotatoCount()
            return
        }

        logger.info("Creating Account")
        let account = Account(id: userID)
        modelContext.insert(account)
        account.updateWidgetPotatoCount()
        do {
            try modelContext.save()
        } catch {
            // Handle uniqueness races: re-fetch and continue if it now exists
            logger.error("Failed to save account: \(error.localizedDescription, privacy: .public)")
            let refreshed = (try? modelContext.fetch(descriptor)) ?? []
            if let existing = refreshed.first {
                refreshed.dropFirst().forEach { modelContext.delete($0) }
                existing.updateWidgetPotatoCount()
                do {
                    try modelContext.save()
                    logger.info("Detected existing Account after save conflict; proceeding with existing record")
                } catch {
                    logger.error("Failed to resolve duplicate Account after conflict: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        logger.info("Finished Generating/Fetching Account")
    }
}
