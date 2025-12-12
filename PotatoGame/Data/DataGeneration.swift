// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Observation
import OSLog
import SwiftData
#if canImport(WidgetKit)
    import WidgetKit
#endif

private let logger = Logger(subsystem: "PotatoGame", category: "DataGeneration")

@Model public class DataGeneration {
    private static let singletonKey = "DataGenerationSingleton"

    public var storageKey: String = DataGeneration.singletonKey
    public var initializationDate: Date?
    public var lastSimulationDate: Date?

    public var requiresInitialDataGeneration: Bool {
        initializationDate == nil
    }

    public init(initializationDate: Date?, lastSimulationDate: Date?) {
        storageKey = Self.singletonKey
        self.initializationDate = initializationDate
        self.lastSimulationDate = lastSimulationDate
    }

    // MARK: - Fast checks / conditional seeding

    public static func needsSeeding(modelContext: ModelContext) -> Bool {
        let instance = instance(with: modelContext)
        return instance.requiresInitialDataGeneration
    }

    public static func generateAllDataIfNeeded(modelContext: ModelContext, userID: String = Account.defaultUserID) {
        let instance = instance(with: modelContext)
        instance.lastSimulationDate = .now
        ensureBaselineData(modelContext: modelContext, userID: userID)
        guard instance.requiresInitialDataGeneration else {
            logger.debug("Seeding skipped; baseline data ensured.")
            return
        }
        logger.info("Generating initial data…")
        instance.generateInitialData(modelContext: modelContext, userID: userID)
    }

    private func initializeData(modelContext: ModelContext) {
        lastSimulationDate = .now
        let needsInitial = requiresInitialDataGeneration

        guard needsInitial else { return }
        logger.info("Requires an initial data generation")
        generateInitialData(modelContext: modelContext, userID: Account.defaultUserID)
    }

    private func generateInitialData(modelContext: ModelContext, userID: String) {
        logger.info("Generating initial data…")
        Self.ensureBaselineData(modelContext: modelContext, userID: userID)
        initializationDate = .now
        do {
            try modelContext.save()
        } catch {
            logger.error("Could not save model context: \(error.localizedDescription, privacy: .public)")
        }

        logger.info("Completed generating initial data")
    }

    private static func instance(with modelContext: ModelContext) -> DataGeneration {
        do {
            var descriptor = FetchDescriptor<DataGeneration>(
                predicate: #Predicate { $0.storageKey == singletonKey }
            )
            descriptor.includePendingChanges = true
            let matches = try (modelContext.fetch(descriptor))
            if let primary = matches.first {
                if matches.count > 1 {
                    matches.dropFirst().forEach { modelContext.delete($0) }
                    do {
                        try modelContext.save()
                        logger.info("Removed duplicate DataGeneration records during hydration.")
                    } catch {
                        logger.error("Failed to prune duplicate DataGeneration records: \(error.localizedDescription, privacy: .public)")
                    }
                }
                return primary
            }
        } catch {
            logger.error("Failed to fetch DataGeneration: \(error.localizedDescription, privacy: .public)")
        }
        let instance = DataGeneration(initializationDate: nil, lastSimulationDate: nil)
        modelContext.insert(instance)
        do {
            try modelContext.save()
        } catch {
            logger.error("Could not save model context: \(error.localizedDescription, privacy: .public)")
        }
        return instance
    }

    public static func ensureBaselineData(modelContext: ModelContext, userID: String = Account.defaultUserID) {
        EmojiSelection.ensureDefaults(in: modelContext)
        Account.generateAccount(modelContext: modelContext, userID: userID)
    }

    public static func generateAllData(modelContext: ModelContext) {
        logger.info("generateAllData running…")

        let instance = instance(with: modelContext)
        instance.initializeData(modelContext: modelContext)
    }

    private static func deleteAll<T: PersistentModel>(of _: T.Type, modelContext: ModelContext, batchSize: Int = 200) throws {
        logger.info("Deleting all \(String(describing: T.self))…")
        // Fetch and delete in batches to avoid memory spikes and ensure CloudKit gets tombstones
        var didDeleteAny = false
        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchLimit = batchSize
            descriptor.includePendingChanges = true
            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty { break }
            batch.forEach { modelContext.delete($0) }
            try modelContext.save()
            didDeleteAny = true
        }
        if didDeleteAny {
            logger.info("Finished deleting \(String(describing: T.self))")
        } else {
            logger.info("No instances of \(String(describing: T.self)) found to delete")
        }
    }

    public static func deleteAllData(modelContext: ModelContext) {
        logger.info("Deleting all data…")

        // Reset flags on existing DataGeneration if present so UI can reflect a fresh start
        if let instance = try? modelContext.fetch(FetchDescriptor<DataGeneration>()).first {
            instance.initializationDate = nil
            instance.lastSimulationDate = nil
            do { try modelContext.save() } catch {
                logger.error("Failed to save reset of DataGeneration flags: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Perform deletions per model in batches to ensure CloudKit tombstones are uploaded
        do { try deleteAll(of: PotatoGameLevelProgress.self, modelContext: modelContext) } catch {
            logger.error("Failed to delete Level Progress: \(error.localizedDescription, privacy: .public)")
        }
        do { try deleteAll(of: EmojiSelection.self, modelContext: modelContext) } catch {
            logger.error("Failed to delete Selection: \(error.localizedDescription, privacy: .public)")
        }
        do { try deleteAll(of: Account.self, modelContext: modelContext) } catch {
            logger.error("Failed to delete Account: \(error.localizedDescription, privacy: .public)")
        }
        do { try deleteAll(of: DataGeneration.self, modelContext: modelContext) } catch {
            logger.error("Failed to delete DataGeneration: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try modelContext.save()
            logger.info("Completed deleting all data")
        } catch {
            logger.error("Failed final save after deletions: \(error.localizedDescription, privacy: .public)")
        }

        if let defaults = UserDefaults(suiteName: Account.widgetSuiteName) {
            defaults.removeObject(forKey: Account.widgetPotatoCountKey)
            Account.reloadPotatoWidgetTimeline()
        }
    }

    public static func startNewGame(modelContext: ModelContext) {
        logger.info("Starting new game…")

        deleteAllData(modelContext: modelContext)
        generateAllData(modelContext: modelContext)
    }
}

public extension DataGeneration {
    static let schema = PotatoGameSchemas.full
}
