// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import CloudKit
import Foundation
import OSLog
import SwiftData

enum SchmojiSchemas {
    /// Models that should sync via CloudKit.
    static let cloud = Schema([
        DataGeneration.self,
        Account.self,
        AccountPurchasedPack.self,
        EmojiSelection.self,
        PotatoGameUnlockedHex.self,
    ])

    /// Models that should remain local-only.
    static let localOnly = Schema([
        PotatoGameLevelProgress.self,
        PotatoGameLevelTile.self,
    ])

    static let full = Schema([
        DataGeneration.self,
        Account.self,
        AccountPurchasedPack.self,
        EmojiSelection.self,
        PotatoGameUnlockedHex.self,
        PotatoGameLevelProgress.self,
        PotatoGameLevelTile.self,
    ])
}

@MainActor
final class PotatoGameModelContainerProvider {
    static let shared = PotatoGameModelContainerProvider()
    private static let logger = Logger(subsystem: "PotatoGame", category: "SchmojiDataContainer")
    private static let promotionDefaultsKey = "SchmojiCloudKitPromotionCompleted"
    private static let storeDirectoryName = "PotatoGameData"
    private static let enablePromotion = false
    private static var cachedAccountStatus: CKAccountStatus?
    private static let accountStatusTask = Task.detached { () -> CKAccountStatus in
        #if os(iOS) || os(macOS)
            return await (try? CKContainer.default().accountStatus()) ?? .couldNotDetermine
        #else
            return .couldNotDetermine
        #endif
    }

    private lazy var accountIDTask = Task<String, Never> {
        await PotatoGameModelContainerProvider.resolveAccountID()
    }

    static func accountID() async -> String {
        await PotatoGameModelContainerProvider.shared.accountIDTask.value
    }

    /// CloudKit availability resolved once per launch.
    static func accountStatus() async -> CKAccountStatus {
        await resolveAccountStatus()
    }

    private static var cloudKitIdentifier: String? {
        #if os(iOS) || os(macOS)
            return CKContainer.default().containerIdentifier
        #else
            return nil
        #endif
    }

    private static func resolveAccountStatus() async -> CKAccountStatus {
        if let cachedAccountStatus { return cachedAccountStatus }
        let status = await accountStatusTask.value
        cachedAccountStatus = status
        return status
    }

    private static func currentAccountStatusSync() -> CKAccountStatus {
        if let cachedAccountStatus { return cachedAccountStatus }
        #if os(iOS) || os(macOS)
            // Heuristic fallback without awaiting.
            return FileManager.default.ubiquityIdentityToken != nil ? .available : .noAccount
        #else
            return .couldNotDetermine
        #endif
    }

    private static func resolveAccountID() async -> String {
        #if os(iOS) || os(macOS)
            let status = currentAccountStatusSync()
            guard status == .available else { return "local-user" }
            do {
                let recordID = try await CKContainer.default().userRecordID()
                return recordID.recordName
            } catch {
                logger.error("Failed to resolve iCloud user record ID: \(error.localizedDescription, privacy: .public)")
                return "local-user"
            }
        #else
            return "local-user"
        #endif
    }

    let container: ModelContainer

    private var didBootstrapData = false
    private var seedingTask: Task<Result<Void, Error>, Never>?

    /// Task representing readiness of baseline seeding. UI can await this to ensure data exists.
    static var readinessTask: Task<Result<Void, Error>, Never> {
        let provider = shared
        if let task = provider.seedingTask {
            return task
        }
        let task = provider.startSeedingTask()
        provider.seedingTask = task
        return task
    }

    /// Awaitable readiness helper for callers that prefer async/throws.
    static func awaitReadiness() async throws {
        let result = await readinessTask.value
        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    private init(inMemory: Bool = PotatoGameOptions.inMemoryPersistence) {
        let start = Date()
        do {
            container = try PotatoGameModelContainerProvider.buildContainer(inMemory: inMemory)
            bootstrapDataIfNeeded()
            let elapsed = Date().timeIntervalSince(start)
            Self.logger.notice("ModelContainer ready in \(elapsed, privacy: .public)s.")
        } catch {
            Self.logger.critical("Failed to build ModelContainer: \(error.localizedDescription, privacy: .public)")
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }

    private func bootstrapDataIfNeeded() {
        guard didBootstrapData == false else { return }
        didBootstrapData = true
        seedingTask = startSeedingTask()
    }

    private func startSeedingTask() -> Task<Result<Void, Error>, Never> {
        Task(priority: .utility) {
            do {
                let accountID = await accountIDTask.value
                try await SeedDataActor(modelContainer: container).seedAll(accountID: accountID)
                return .success(())
            } catch {
                Self.logger.error("Seeding failed: \(error.localizedDescription, privacy: .public)")
                return .failure(error)
            }
        }
    }

    private static func buildContainer(inMemory: Bool) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(
                for: SchmojiSchemas.full,
                configurations: [ModelConfiguration(schema: SchmojiSchemas.full, isStoredInMemoryOnly: true)]
            )
        }

        var attemptedError: Error?

        #if os(iOS) || os(macOS)
            let status = currentAccountStatusSync()
            if status == .available, let desiredCloudIdentifier = cloudKitIdentifier {
                if #available(iOS 17.2, macOS 14.2, *) {
                    do {
                        let configuration = cloudStoreConfiguration(identifier: desiredCloudIdentifier)
                        let localOnlyConfiguration = localOnlyStoreConfiguration()
                        let container = try ModelContainer(
                            for: SchmojiSchemas.full,
                            configurations: [configuration, localOnlyConfiguration]
                        )
                        if enablePromotion {
                            promoteLocalStoreIfNeeded(to: container)
                        }
                        return container
                    } catch {
                        attemptedError = error
                        logger.warning("CloudKit container failed (\(error.localizedDescription, privacy: .public)); falling back to local store.")
                    }
                } else {
                    logger.notice("CloudKit requested but requires iOS 17.2 / macOS 14.2 or later; using local store instead.")
                }
            } else if cloudKitIdentifier != nil {
                logger.notice("CloudKit requested but no iCloud account is available or status not available; using local store.")
            } else {
                logger.debug("CloudKit disabled or not configured; using local on-disk storage.")
            }
        #endif

        do {
            let configuration = localStoreConfiguration(schema: SchmojiSchemas.full)
            let container = try ModelContainer(
                for: SchmojiSchemas.full,
                configurations: [configuration]
            )
            if attemptedError != nil {
                logger.notice("ModelContainer using local on-disk storage until CloudKit becomes available.")
            }
            return container
        } catch {
            if let attemptedError {
                throw attemptedError
            }
            throw error
        }
    }

    private static func localStoreConfiguration(schema: Schema) -> ModelConfiguration {
        let url = localStoreURL()
        return ModelConfiguration(
            "LocalStore",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }

    private static func cloudStoreConfiguration(identifier: String) -> ModelConfiguration {
        let url = cloudStoreURL()
        return ModelConfiguration(
            "CloudStore",
            schema: SchmojiSchemas.cloud,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .private(identifier)
        )
    }

    private static func localOnlyStoreConfiguration() -> ModelConfiguration {
        let url = localOnlyStoreURL()
        return ModelConfiguration(
            "LocalOnlyStore",
            schema: SchmojiSchemas.localOnly,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }

    private static func localStoreURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(storeDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: directory.path) == false {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to prepare local store directory: \(error.localizedDescription, privacy: .public)")
            }
        }

        return directory.appendingPathComponent("local.store")
    }

    private static func cloudStoreURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(storeDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: directory.path) == false {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to prepare cloud store directory: \(error.localizedDescription, privacy: .public)")
            }
        }

        return directory.appendingPathComponent("cloud.store")
    }

    private static func localOnlyStoreURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(storeDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: directory.path) == false {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to prepare local-only store directory: \(error.localizedDescription, privacy: .public)")
            }
        }

        return directory.appendingPathComponent("local-only.store")
    }

    private static func promoteLocalStoreIfNeeded(to cloudContainer: ModelContainer) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: promotionDefaultsKey) {
            logger.debug("CloudKit promotion already completed; skipping import.")
            return
        }

        let localURL = localStoreURL()
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            defaults.set(true, forKey: promotionDefaultsKey)
            logger.info("No legacy local store to promote; marking promotion complete.")
            return
        }

        Task(priority: .utility) {
            do {
                let migrator = CloudPromotionMigrator()
                try await migrator.migrate(
                    localConfiguration: localStoreConfiguration(schema: SchmojiSchemas.full),
                    localOnlyConfiguration: localOnlyStoreConfiguration(),
                    cloudContainer: cloudContainer
                )
                defaults.set(true, forKey: promotionDefaultsKey)
                logger.info("Successfully promoted local data to CloudKit-backed store.")
            } catch {
                logger.error("CloudKit promotion failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private actor CloudPromotionMigrator {
    private let logger = Logger(subsystem: "PotatoGame", category: "SchmojiCloudPromotion")

    func migrate(localConfiguration: ModelConfiguration,
                 localOnlyConfiguration: ModelConfiguration,
                 cloudContainer: ModelContainer) throws
    {
        let localContainer = try ModelContainer(for: DataGeneration.schema, configurations: [localConfiguration])
        let localContext = ModelContext(localContainer)
        let cloudContext = ModelContext(cloudContainer)
        let localOnlyContainer = try ModelContainer(for: SchmojiSchemas.localOnly, configurations: [localOnlyConfiguration])
        let localOnlyContext = ModelContext(localOnlyContainer)

        var descriptor = FetchDescriptor<DataGeneration>()
        descriptor.fetchLimit = 1
        if let existing = try? cloudContext.fetch(descriptor), existing.isEmpty == false {
            logger.notice("Cloud store already populated; skipping local promotion.")
            return
        }

        try copyAllData(from: localContext, cloudDestination: cloudContext, localOnlyDestination: localOnlyContext)
        try cloudContext.save()
        try localOnlyContext.save()
    }

    private func copyAllData(from source: ModelContext, cloudDestination: ModelContext, localOnlyDestination: ModelContext) throws {
        try copyDataGenerations(from: source, to: cloudDestination)
        try copyAccounts(from: source, to: cloudDestination)
        try copySelections(from: source, to: cloudDestination)
        try copyLevelProgress(from: source, to: localOnlyDestination)
    }

    private func copyDataGenerations(from source: ModelContext, to destination: ModelContext) throws {
        let records = try source.fetch(FetchDescriptor<DataGeneration>())
        for record in records {
            let clone = DataGeneration(initializationDate: record.initializationDate, lastSimulationDate: record.lastSimulationDate)
            clone.storageKey = record.storageKey
            destination.insert(clone)
        }
    }

    private func copyAccounts(from source: ModelContext, to destination: ModelContext) throws {
        let accounts = try source.fetch(FetchDescriptor<Account>())
        for account in accounts {
            let clone = Account(id: account.id, joinDate: account.joinDate, purchasedLevelPackIDs: account.purchasedLevelPackIDs)
            clone.potatoCount = account.potatoCount
            clone.purchasedLevelPackIDs = account.purchasedLevelPackIDs
            destination.insert(clone)
        }
    }

    private func copySelections(from source: ModelContext, to destination: ModelContext) throws {
        let selections = try source.fetch(FetchDescriptor<EmojiSelection>())
        for selection in selections {
            let clone = EmojiSelection(color: selection.color, selectedHex: selection.selectedHex, unlockedHexes: selection.unlockedHexes)
            clone.perfectWinCount = selection.perfectWinCount
            destination.insert(clone)
        }
    }

    private func copyLevelProgress(from source: ModelContext, to destination: ModelContext) throws {
        let progresses = try source.fetch(FetchDescriptor<PotatoGameLevelProgress>())
        for progress in progresses {
            let clone = PotatoGameLevelProgress(levelNumber: progress.levelNumber, gameState: progress.gameState)
            clone.numOfPotatoesCreated = progress.numOfPotatoesCreated
            clone.isDeleted = progress.isDeleted
            clone.startedDate = progress.startedDate
            clone.completedDate = progress.completedDate
            clone.updatedAt = progress.updatedAt

            if let tiles = progress.storedTiles {
                clone.storedTiles = tiles.map { tile in
                    PotatoGameLevelTile(
                        id: tile.id,
                        color: tile.color,
                        positionX: tile.positionX,
                        positionY: tile.positionY,
                        progress: clone
                    )
                }
            }

            destination.insert(clone)
        }
    }
}

@ModelActor
actor SeedDataActor {
    func seedAll(accountID: String) throws {
        DataGeneration.generateAllDataIfNeeded(modelContext: modelContext, userID: accountID)
    }
}
