// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import OSLog
import SpriteKit
import SwiftData
import SwiftUI

/// Persistence helpers that coordinate autosave, dedupe, and migrations.
@MainActor
extension SchmojiGameSessionManager {
    func saveGame(from scene: SchmojiGameScene, immediate: Bool = false) {
        if currentLevel.gameState == .playing, let updatedObjects = scene.extractUpdatedObjects() {
            pendingLayoutSnapshot = updatedObjects
        }

        if immediate {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            performImmediateSave(with: scene)
            return
        }

        pendingSceneReference = scene
        pendingSaveTask?.cancel()

        let delay = UInt64(saveDebounceInterval * 1_000_000_000)
        pendingSaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            performPendingSave()
        }
    }

    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        let scene = pendingSceneReference
        pendingSceneReference = nil
        let snapshot = drainPendingLayoutSnapshot()
        guard scene != nil || snapshot != nil else { return }
        persistScene(scene, layoutSnapshot: snapshot)
    }
}

/// Summary of the bits of `SchmojiLevelInfo` we expose to SwiftUI observers.
/// Comparing digests lets us skip redundant `@Published` updates when a save touches unrelated fields.
struct LevelUpdateDigest: Equatable {
    let levelNumber: Int
    let gameState: GameState
    let numOfPotatoesCreated: Int
    let startedDate: Date?
    let completedDate: Date?
    let ownedLevelPackIDs: Set<String>

    @MainActor
    init(level: SchmojiLevelInfo) {
        levelNumber = level.levelNumber
        gameState = level.gameState
        numOfPotatoesCreated = level.numOfPotatoesCreated
        startedDate = level.startedDate
        completedDate = level.completedDate
        ownedLevelPackIDs = level.ownedLevelPackIDs
    }
}

// MARK: - Persistence Snapshots & Actor

private struct LevelPersistenceSnapshot: Sendable {
    let levelNumber: Int
    let gameState: GameState
    let numOfPotatoesCreated: Int
    let startedDate: Date?
    let completedDate: Date?
    let objects: [SchmojiBoardObject]?
    let defaultState: GameState

    @MainActor
    init(level: SchmojiLevelInfo, boardObjects: [SchmojiBoardObject]? = nil) {
        levelNumber = level.levelNumber
        gameState = level.gameState
        numOfPotatoesCreated = level.numOfPotatoesCreated
        startedDate = level.startedDate
        completedDate = level.completedDate
        let isLocked = level.isLevelPackLocked
        defaultState = isLocked ? .newLevelPack : .newUnlocked
        let sourceObjects = boardObjects ?? level.schmojiInLevel
        objects = sourceObjects.isEmpty ? nil : sourceObjects
    }
}

private struct AccountPersistenceSnapshot: Sendable {
    let id: String
    let potatoCount: Int
    let purchasedLevelPackIDs: [String]

    init(account: Account) {
        id = account.id
        potatoCount = account.potatoCount
        purchasedLevelPackIDs = account.purchasedLevelPackIDs
    }
}

private struct SelectionPersistenceSnapshot: Sendable {
    let colorRawValue: String
    let selectedHex: String
    let perfectWinCount: Int
    let unlockedHexes: [String]

    init(selection: SchmojiSelection) {
        colorRawValue = selection.colorRawValue
        selectedHex = selection.selectedHex
        perfectWinCount = selection.perfectWinCount
        unlockedHexes = selection.unlockedHexes
    }
}

actor GamePersistenceActor {
    private let container: ModelContainer
    private lazy var context: ModelContext = {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }()

    private let logger = Logger(subsystem: "PotatoGame", category: "GamePersistence")

    init(container: ModelContainer) {
        self.container = container
    }

    func pruneExistingDuplicates() async {
        do {
            try pruneLevelDuplicates()
            try pruneAccountDuplicates()
            try pruneSelectionDuplicates()
            if context.hasChanges {
                try context.save()
            }
        } catch {
            logger.error("Failed to prune duplicates: \(error.localizedDescription, privacy: .public)")
        }
    }

    fileprivate func persistLevel(_ snapshot: LevelPersistenceSnapshot, account: AccountPersistenceSnapshot?, reason: String) async {
        do {
            let levelNumber = snapshot.levelNumber
            var descriptor = FetchDescriptor<SchmojiLevelProgress>()
            descriptor.predicate = #Predicate { $0.levelNumber == levelNumber }
            descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
            descriptor.includePendingChanges = true

            var matches = try context.fetch(descriptor)
            let progress: SchmojiLevelProgress
            if let existing = matches.first {
                progress = existing
            } else {
                let created = SchmojiLevelProgress(levelNumber: levelNumber, gameState: snapshot.defaultState)
                created.loadFromTemplateIfNeeded()
                context.insert(created)
                progress = created
                matches = []
            }

            if matches.count > 1 {
                matches.dropFirst().forEach { context.delete($0) }
                logger.notice("Removed duplicate level progress rows for level \(levelNumber, privacy: .public)")
            }

            progress.gameState = snapshot.gameState
            progress.numOfPotatoesCreated = snapshot.numOfPotatoesCreated
            progress.startedDate = snapshot.startedDate
            progress.completedDate = snapshot.completedDate
            if let objects = snapshot.objects {
                progress.setBoardObjects(objects)
            }

            if let accountSnapshot = account {
                try persistAccountInternal(accountSnapshot)
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            logger.error("Failed to persist level \(snapshot.levelNumber, privacy: .public) for reason \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    fileprivate func persistAccount(_ snapshot: AccountPersistenceSnapshot) async {
        do {
            try persistAccountInternal(snapshot)
            if context.hasChanges {
                try context.save()
            }
        } catch {
            logger.error("Failed to persist account \(snapshot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    fileprivate func persistSelection(_ snapshot: SelectionPersistenceSnapshot) async {
        do {
            let colorRawValue = snapshot.colorRawValue
            var descriptor = FetchDescriptor<SchmojiSelection>()
            descriptor.predicate = #Predicate { $0.colorRawValue == colorRawValue }
            descriptor.includePendingChanges = true

            let matches = try context.fetch(descriptor)
            let selection: SchmojiSelection
            if let existing = matches.first {
                selection = existing
            } else {
                let color = SchmojiColor(rawValue: snapshot.colorRawValue) ?? .green
                let created = SchmojiSelection(color: color, selectedHex: snapshot.selectedHex, unlockedHexes: snapshot.unlockedHexes)
                created.perfectWinCount = snapshot.perfectWinCount
                context.insert(created)
                selection = created
            }

            if matches.count > 1 {
                matches.dropFirst().forEach { context.delete($0) }
                logger.notice("Removed duplicate SchmojiSelection rows for color \(colorRawValue, privacy: .public)")
            }

            selection.selectedHex = snapshot.selectedHex
            selection.perfectWinCount = snapshot.perfectWinCount
            selection.unlockedHexes = snapshot.unlockedHexes

            if context.hasChanges {
                try context.save()
            }
        } catch {
            logger.error("Failed to persist selection for color \(snapshot.colorRawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func discardLayout(for levelNumber: Int) async {
        do {
            if let progress = SchmojiLevelProgress.progress(levelNumber: levelNumber, in: context) {
                progress.storedTiles = []
                progress.updatedAt = .now
                if context.hasChanges {
                    try context.save()
                }
            }
        } catch {
            logger.error("Failed to discard layout for level \(levelNumber, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func ensureTemplateLayout(for levelNumber: Int) async {
        do {
            let progress = SchmojiLevelProgress.ensure(levelNumber: levelNumber, defaultState: .newUnlocked, in: context)
            let generated = progress.loadFromTemplateIfNeeded()
            if generated, context.hasChanges {
                try context.save()
            } else if context.hasChanges {
                try context.save()
            }
        } catch {
            logger.error("Failed to ensure template layout for level \(levelNumber, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    private func persistAccountInternal(_ snapshot: AccountPersistenceSnapshot) throws -> Account {
        var descriptor = FetchDescriptor<Account>()
        let targetID = snapshot.id
        descriptor.predicate = #Predicate { $0.id == targetID }
        descriptor.sortBy = [SortDescriptor(\.joinDate, order: .reverse)]
        descriptor.includePendingChanges = true
        let matches = try context.fetch(descriptor)
        let account: Account
        if let existing = matches.first {
            account = existing
        } else {
            let created = Account(
                id: snapshot.id,
                purchasedLevelPackIDs: snapshot.purchasedLevelPackIDs
            )
            created.potatoCount = snapshot.potatoCount
            context.insert(created)
            return created
        }
        if matches.count > 1 {
            matches.dropFirst().forEach { context.delete($0) }
            logger.notice("Removed duplicate Account rows for id \(snapshot.id, privacy: .public)")
        }
        account.potatoCount = snapshot.potatoCount
        account.purchasedLevelPackIDs = Array(Set(snapshot.purchasedLevelPackIDs)).sorted()
        return account
    }

    private func pruneLevelDuplicates() throws {
        var descriptor = FetchDescriptor<SchmojiLevelProgress>()
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        descriptor.includePendingChanges = true
        let allProgress = try context.fetch(descriptor)
        var seen: Set<Int> = []
        var duplicates: [SchmojiLevelProgress] = []
        for entry in allProgress {
            let levelNumber = entry.levelNumber
            if seen.insert(levelNumber).inserted {
                continue
            }
            duplicates.append(entry)
        }
        guard duplicates.isEmpty == false else { return }
        duplicates.forEach { context.delete($0) }
        let removedLevels = duplicates.map(\.levelNumber).sorted()
        logger.notice("Pruned duplicate level progress rows for levels: \(removedLevels, privacy: .public)")
    }

    private func pruneAccountDuplicates() throws {
        var descriptor = FetchDescriptor<Account>()
        descriptor.sortBy = [SortDescriptor(\.joinDate, order: .reverse)]
        descriptor.includePendingChanges = true
        let allAccounts = try context.fetch(descriptor)
        var seen: Set<String> = []
        var duplicates: [Account] = []
        for account in allAccounts {
            let id = account.id
            if seen.insert(id).inserted {
                continue
            }
            duplicates.append(account)
        }
        guard duplicates.isEmpty == false else { return }
        duplicates.forEach { context.delete($0) }
        let removedIDs = duplicates.map(\.id)
        logger.notice("Pruned duplicate Account rows for ids: \(removedIDs, privacy: .public)")
    }

    private func pruneSelectionDuplicates() throws {
        var descriptor = FetchDescriptor<SchmojiSelection>()
        descriptor.includePendingChanges = true
        let allSelections = try context.fetch(descriptor)
        var seen: Set<String> = []
        var duplicates: [SchmojiSelection] = []
        for selection in allSelections {
            let raw = selection.colorRawValue
            if seen.insert(raw).inserted {
                continue
            }
            duplicates.append(selection)
        }
        guard duplicates.isEmpty == false else { return }
        duplicates.forEach { context.delete($0) }
        let removed = duplicates.map(\.colorRawValue)
        logger.notice("Pruned duplicate SchmojiSelection rows for colors: \(removed, privacy: .public)")
    }
}

// MARK: - Shared Helpers

extension SchmojiGameSessionManager {
    func notifyLevelUpdate(force: Bool = false) {
        let digest = LevelUpdateDigest(level: currentLevel)
        if force == false, digest == lastLevelUpdateDigest {
            return
        }
        lastLevelUpdateDigest = digest
        onLevelUpdate?(currentLevel)
    }

    func applySpawnRotation(to node: SchmojiSpriteNode) {
        let randomRotation = CGFloat.random(in: spawnRotationRange)
        node.zRotation = randomRotation
    }

    func performPendingSave() {
        let scene = pendingSceneReference
        pendingSceneReference = nil
        pendingSaveTask = nil

        let snapshot = drainPendingLayoutSnapshot()
        guard scene != nil || snapshot != nil else { return }
        persistScene(scene, layoutSnapshot: snapshot)
    }

    func performImmediateSave(with scene: SchmojiGameScene) {
        pendingSceneReference = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        let snapshot = drainPendingLayoutSnapshot()
        persistScene(scene, layoutSnapshot: snapshot)
    }

    private func drainPendingLayoutSnapshot() -> [SchmojiBoardObject]? {
        defer { pendingLayoutSnapshot = nil }
        return pendingLayoutSnapshot
    }

    func ensureLevelLayout() {
        guard currentLevel.hasGeneratedLayout == false || currentLevel.schmojiInLevel.isEmpty else { return }
        currentLevel.ensureTemplateLayout()
        persistLevelState(reason: "generate level layout", includeAccount: false)
        Task(priority: .utility) { [levelNumber = currentLevel.levelNumber, actor = persistenceActor] in
            await actor.ensureTemplateLayout(for: levelNumber)
        }
        notifyLevelUpdate()
    }

    /// Clears layout/progress so the current level can be replayed fresh.
    func resetLevelState() {
        pendingGameEndTask?.cancel()
        pendingGameEndTask = nil
        currentLevel.discardStoredLayout()
        currentLevel.updateProgress(in: nil) { progress in
            progress.completedDate = nil
            progress.startedDate = Date()
            progress.gameState = .playing
        }
        currentLevel.numOfPotatoesCreated = 0
        potatoesCreatedThisRun = 0
        lastEvolutionSaveDate = nil
        persistLevelState(reason: "persist level reset", includeAccount: false)
        notifyLevelUpdate()
    }

    /// Serializes the live scene (or a supplied snapshot) back into persistence.
    func persistScene(_ scene: SchmojiGameScene?, layoutSnapshot: [SchmojiBoardObject]? = nil) {
        var snapshotObjects = layoutSnapshot
        if currentLevel.gameState == .playing {
            if snapshotObjects == nil, let scene, let updatedObjects = scene.extractUpdatedObjects() {
                snapshotObjects = updatedObjects
            }
            if let updatedObjects = snapshotObjects {
                currentLevel.schmojiInLevel = updatedObjects
            } else if scene != nil {
                logger.notice("Skipped saving layout snapshot because the scene was not ready.")
            }
        }
        currentLevel.commitLayoutIfNeeded()
        persistLevelState(reason: "save game", boardObjectsOverride: snapshotObjects)
        notifyLevelUpdate()
    }

    /// Throttled save used during rapid match chains so we don’t spam disk.
    func scheduleEvolutionSave(from scene: SchmojiGameScene) {
        guard currentLevel.gameState == .playing else { return }
        let now = Date()
        if let last = lastEvolutionSaveDate, now.timeIntervalSince(last) < evolutionSaveCooldown {
            saveGame(from: scene)
            return
        }
        lastEvolutionSaveDate = now
        saveGame(from: scene, immediate: true)
    }

    /// Periodic save loop that runs while the level is in the playing state.
    func startAutosaveLoop(scene: SchmojiGameScene) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self, weak scene] in
            guard let self else { return }
            let delay = UInt64(autosaveInterval * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let scene else { break }
                await MainActor.run {
                    guard self.currentLevel.gameState == .playing else { return }
                    self.saveGame(from: scene)
                }
            }
            await MainActor.run { [weak self] in
                self?.autosaveTask = nil
            }
        }
    }

    /// Cancels the autosave task when pausing or leaving the scene.
    func stopAutosaveLoop() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    private func persistLevelState(reason: String, boardObjectsOverride: [SchmojiBoardObject]? = nil, includeAccount: Bool = false) {
        let levelSnapshot = LevelPersistenceSnapshot(level: currentLevel, boardObjects: boardObjectsOverride)
        let accountSnapshot = includeAccount ? AccountPersistenceSnapshot(account: currentAccount) : nil
        Task(priority: .utility) { [actor = persistenceActor] in
            await actor.persistLevel(levelSnapshot, account: accountSnapshot, reason: reason)
        }
    }

    private func persistAccountState() {
        let snapshot = AccountPersistenceSnapshot(account: currentAccount)
        Task(priority: .utility) { [actor = persistenceActor] in
            await actor.persistAccount(snapshot)
        }
    }

    private func persistSelectionState(_ selection: SchmojiSelection) {
        let snapshot = SelectionPersistenceSnapshot(selection: selection)
        Task(priority: .utility) { [actor = persistenceActor] in
            await actor.persistSelection(snapshot)
        }
    }

    /// Adds to the account’s potato wallet and syncs to persistence/Game Center.
    func incrementPotatoCount(by amount: Int = 1) {
        currentAccount.addPotatoes(by: amount)
        persistAccountState()
        reportGameCenterLifetimeProgress()
    }

    /// Clears out old layouts once a level has finished so templates regenerate.
    func discardInactiveLayoutIfNeeded() {
        guard currentLevel.gameState != .playing else { return }
        currentLevel.discardStoredLayout()
        currentLevel.commitLayoutIfNeeded()
        Task(priority: .utility) { [levelNumber = currentLevel.levelNumber, actor = persistenceActor] in
            await actor.discardLayout(for: levelNumber)
        }
        notifyLevelUpdate()
    }

    /// Tracks perfect wins vs normal wins for collection unlock progress.
    func updateColorUnlockProgress(perfect: Bool) {
        let color = currentLevel.levelBackgroundColor
        let selection = SchmojiSelection.resolve(color: color, in: modelContext)
        let progress: SchmojiSelection.UnlockProgress = if perfect {
            selection.recordPerfectWin()
        } else {
            selection.currentUnlockProgress()
        }

        lastUnlockProgress = progress
        onUnlockProgress?(progress)
        persistSelectionState(selection)
    }

    func reportGameCenterLifetimeProgress() {
        #if os(iOS)
            let preference = UserDefaults.standard.object(forKey: "gamecenter") as? Bool ?? SchmojiOptions.gameCenter
            guard preference else { return }
            let descriptor = FetchDescriptor<SchmojiLevelProgress>()
            let completedLevels = (try? modelContext.fetch(descriptor))?.reduce(into: 0) { sum, entry in
                if entry.gameState == .win || entry.gameState == .winPerfect {
                    sum += 1
                }
            } ?? 0

            var selectionDescriptor = FetchDescriptor<SchmojiSelection>()
            selectionDescriptor.includePendingChanges = true
            let selections = (try? modelContext.fetch(selectionDescriptor)) ?? []

            let totalUnlockedSchmojis = selections.reduce(into: 0) { count, selection in
                let unlocked = selection.unlockedHexes.filter { selection.availableHexes.contains($0) }
                count += unlocked.count
            }

            let totalAvailableSchmojis = SchmojiColor.allCases.reduce(into: 0) { count, color in
                count += color.schmojis.count
            }

            GameCenterManager.shared.syncLifetimeProgress(
                levelsCompleted: completedLevels,
                potatoesCreated: currentAccount.potatoCount,
                schmojisUnlocked: totalUnlockedSchmojis,
                totalSchmojis: totalAvailableSchmojis
            )
        #endif
    }
}
