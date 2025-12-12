// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import OSLog
import SpriteKit
import SwiftData
import SwiftUI

/// Coordinates SpriteKit gameplay with SwiftData persistence, StoreKit unlocks, and progress tracking.
@MainActor
class PotatoGameSessionManager {
    let logger = Logger(subsystem: "PotatoGame", category: "GameSession")
    let saveDebounceInterval: TimeInterval = 0.25
    var pendingSaveTask: Task<Void, Never>?
    /// Small pause before finalizing a game so the last spawn/sound can breathe.
    let gameEndDelay: TimeInterval = 0.6
    var pendingGameEndTask: Task<Void, Never>?
    /// We keep the scene alive between debounce cycles so the layout can be re-read.
    weak var pendingSceneReference: PotatoGameScene?
    /// Snapshot generated during gameplay that will eventually be persisted.
    var pendingLayoutSnapshot: [SchmojiBoardObject]?
    /// Periodic autosave loop that runs while the level is active.
    var autosaveTask: Task<Void, Never>?
    let autosaveInterval: TimeInterval = 30
    let evolutionSaveCooldown: TimeInterval = 2
    let spawnRotationRange: ClosedRange<CGFloat> = (-.pi / 14) ... (.pi / 14)
    var lastEvolutionSaveDate: Date?

    var modelContext: ModelContext
    var currentLevel: SchmojiLevelInfo
    var currentPalette: [SchmojiAppearance]
    var currentAccount: Account
    var onLevelUpdate: ((SchmojiLevelInfo) -> Void)?
    var onUnlockProgress: ((SchmojiSelection.UnlockProgress?) -> Void)?
    var lastUnlockProgress: SchmojiSelection.UnlockProgress?
    /// Running count of potatoes earned since the scene was built (for sheets/HUD).
    var potatoesCreatedThisRun: Int = 0
    var lastLevelUpdateDigest: LevelUpdateDigest?
    let persistenceActor: GamePersistenceActor
    let keyboardSettings: GameKeyboardSettings

    /// Build a session around the given account/level/palette combo.
    init(account: Account, context: ModelContext, level: SchmojiLevelInfo, palette: [SchmojiAppearance], keyboardSettings: GameKeyboardSettings) {
        currentLevel = level
        modelContext = context
        currentPalette = palette
        currentAccount = account
        self.keyboardSettings = keyboardSettings
        persistenceActor = GamePersistenceActor(container: context.container)

        Task(priority: .utility) { [actor = persistenceActor] in
            await actor.pruneExistingDuplicates()
        }
        _ = currentLevel.ensureProgress(in: context)
        potatoesCreatedThisRun = currentLevel.numOfPotatoesCreated
        notifyLevelUpdate()
    }

    @MainActor
    deinit {
        pendingSaveTask?.cancel()
        pendingGameEndTask?.cancel()
        stopAutosaveLoop()
    }

    /// Spins up a brand new SpriteKit scene, primed with level data and autosave.
    func startGame() -> PotatoGameScene {
        potatoesCreatedThisRun = currentLevel.numOfPotatoesCreated
        // Make sure brand-new progress rows have a generated board before the scene boots.
        ensureLevelLayout()
        lastEvolutionSaveDate = nil
        let presentation = SchmojiLevelPresentation(levelInfo: currentLevel)
        let scene = PotatoGameScene(levelPresentation: presentation)
        scene.keyboardSettings = keyboardSettings
        scene.sessionManager = self
        currentLevel.startPlaying(in: modelContext)
        notifyLevelUpdate()
        updateColorUnlockProgress(perfect: false)
        startAutosaveLoop(scene: scene)

        return scene
    }

    /// Wipe gameplay state and regenerate layout for editing tools.
    func resetLevel() {
        resetLevelState()
    }

    /// Allows the view model to swap palettes mid-session.
    func updatePalette(_ palette: [SchmojiAppearance]) {
        currentPalette = palette
    }

    /// Refreshes lock state if the user purchases packs mid-session.
    func updateOwnedLevelPackIDs(_ ownedPackIDs: Set<String>) {
        guard currentLevel.ownedLevelPackIDs != ownedPackIDs else { return }
        if let template = currentLevel.template {
            currentLevel = SchmojiLevelInfo(template: template, progress: currentLevel.progress, ownedLevelPackIDs: ownedPackIDs)
        } else {
            currentLevel = SchmojiLevelInfo(
                levelNumber: currentLevel.levelNumber,
                levelBackgroundColor: currentLevel.levelBackgroundColor,
                potentialPotatoCount: currentLevel.potentialPotatoCount,
                progress: currentLevel.progress,
                ownedLevelPackIDs: ownedPackIDs
            )
        }
        notifyLevelUpdate()
    }

    /// Rebuilds the current level and kicks the autosave loop again.
    func restartLevel(in scene: PotatoGameScene) {
        resetLevelState()
        let presentation = SchmojiLevelPresentation(levelInfo: currentLevel)
        scene.reloadLevel(with: presentation)
        scene.isPaused = false
        saveGame(from: scene, immediate: true)
        startAutosaveLoop(scene: scene)
    }

    /// Called when a sheet dismissal wants to resume play without resetting.
    func continueCurrentLevel(in scene: PotatoGameScene) {
        currentLevel.startPlaying(in: modelContext)
        currentLevel.gameState = .playing
        saveGame(from: scene, immediate: true)
        startAutosaveLoop(scene: scene)
    }

    /// Sends the latest unlock progress to any observers (e.g. sheet UI).
    func notifyCurrentUnlockProgress() {
        onUnlockProgress?(lastUnlockProgress)
    }

    // MARK: - Game End Evaluation

    private func scheduleGameEnd(after delay: TimeInterval, perform action: @escaping () -> Void) {
        pendingGameEndTask?.cancel()
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        pendingGameEndTask = Task { [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard Task.isCancelled == false else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                action()
                pendingGameEndTask = nil
            }
        }
    }

    /// Determines win/lose/perfect state based on the live board snapshot.
    func evaluateGameEnd(in scene: PotatoGameScene, forced: Bool = false) {
        guard let lastColor = SchmojiOptions.lastColor else { return }
        let matchThreshold = max(2, SchmojiOptions.matchCountMin)

        guard let layoutObjects = scene.extractUpdatedObjects() else { return }
        currentLevel.schmojiInLevel = layoutObjects

        var schmojiCountMap: [SchmojiColor: Int] = [:]
        var potatoCount = 0

        // Build a histogram of remaining colors so we can determine whether more evolutions are possible.
        for object in layoutObjects {
            let color = object.color
            schmojiCountMap[color, default: 0] += 1
            if color == lastColor {
                potatoCount += 1
            }
        }

        let extraPotatoesPossible = currentLevel.potentialPotatoCountInGame(using: schmojiCountMap)
        let hasMatchAvailable = schmojiCountMap.contains { color, count in
            color != lastColor && count >= matchThreshold
        }
        let hasNonLastColorRemaining = schmojiCountMap.contains { color, count in
            color != lastColor && count > 0
        }
        let isPerfectWin = potatoCount > 0 && extraPotatoesPossible == 0 && hasNonLastColorRemaining == false

        #if DEBUG
            let levelNumber = currentLevel.levelNumber
            let countsDescription = schmojiCountMap
                .sorted { $0.key.order < $1.key.order }
                .map { "\($0.key.rawValue):\($0.value)" }
                .joined(separator: ", ")
            logger.debug(
                """
                EvalGameEnd L\(levelNumber) \
                counts[\(countsDescription)] \
                existingPotatoes=\(potatoCount) \
                potentialPotatoes=\(extraPotatoesPossible) \
                matchAvailable=\(hasMatchAvailable) \
                nonLastColorsRemaining=\(hasNonLastColorRemaining)
                """
            )
        #endif

        let hasWon = potatoCount > 0 && (forced || extraPotatoesPossible == 0)
        let shouldLose = potatoCount == 0 && (forced || hasMatchAvailable == false)

        if potatoCount > 0 {
            if currentLevel.numOfPotatoesCreated < potatoCount {
                currentLevel.numOfPotatoesCreated = potatoCount
                notifyLevelUpdate()
            }
            potatoesCreatedThisRun = max(potatoesCreatedThisRun, currentLevel.numOfPotatoesCreated)
        }

        if forced {
            pendingGameEndTask?.cancel()
            pendingGameEndTask = nil
            if hasWon {
                handleWin(in: scene, perfect: isPerfectWin)
            } else {
                handleLoss(in: scene)
            }
            return
        }

        if hasWon {
            #if DEBUG
                let outcomeLabel = isPerfectWin ? "WIN PERFECT" : "WIN"
                logger.debug("EvalGameEnd -> \(outcomeLabel) \(forced ? "[forced]" : "") (potatoCount=\(potatoCount), potential=\(extraPotatoesPossible))")
            #endif
            scheduleGameEnd(after: gameEndDelay) { [weak self] in
                self?.handleWin(in: scene, perfect: isPerfectWin)
            }
        } else if shouldLose {
            #if DEBUG
                logger.debug("EvalGameEnd -> LOSE \(forced ? "[forced]" : "") (potatoCount=\(potatoCount), matchAvailable=\(hasMatchAvailable))")
            #endif
            scheduleGameEnd(after: gameEndDelay) { [weak self] in
                self?.handleLoss(in: scene)
            }
        } else {
            #if DEBUG
                logger.debug("EvalGameEnd -> CONTINUE")
            #endif
        }
    }

    /// Applies win bookkeeping, updates unlocks, and persists the final state.
    func handleWin(in scene: PotatoGameScene, perfect: Bool = false) {
        scene.playSound(perfect ? .perfectWin : .win)
        currentLevel.completeLevel(perfect: perfect, in: modelContext)
        finishGame()
        updateColorUnlockProgress(perfect: perfect)
        saveGame(from: scene, immediate: true)
        discardInactiveLayoutIfNeeded()
        notifyLevelUpdate()
        reportGameCenterLifetimeProgress()
    }

    /// Applies loss bookkeeping and persists state for a retry.
    func handleLoss(in scene: PotatoGameScene) {
        scene.playSound(.loss)
        if let progress = currentLevel.ensureProgressIfNeeded(modelContext) {
            progress.gameState = .lose
            progress.completedDate = Date()
        }
        finishGame()
        saveGame(from: scene, immediate: true)
        discardInactiveLayoutIfNeeded()
        notifyLevelUpdate()
    }

    /// Manual “end level” button that reuses the same evaluation flow.
    func handleEnd(in scene: PotatoGameScene) {
        evaluateGameEnd(in: scene, forced: true)
    }

    private func finishGame() {
        stopAutosaveLoop()
        let levelNumber = currentLevel.levelNumber
        logger.debug("Game ended for level \(levelNumber).")
        notifyLevelUpdate()
    }

    /// Builds a SpriteKit node for a stored board object snapshot.
    func createNode(for object: SchmojiBoardObject) -> SchmojiSpriteNode {
        let color = object.color
        let appearance = currentPalette.first { $0.color == color }

        let node = SchmojiSpriteNode(
            schmojiObject: object,
            appearance: appearance
        )
        node.name = "schmoji_\(object.id.uuidString)"
        applySpawnRotation(to: node)
        return node
    }

    /// Updates potato counts when a match chain reaches the final color.
    func trackPotatoCreation(from color: SchmojiColor, createdCount: Int) {
        guard createdCount > 0 else { return }
        guard let lastColor = SchmojiOptions.lastColor else { return }

        if color.nextColor() == lastColor {
            currentLevel.numOfPotatoesCreated += createdCount
            potatoesCreatedThisRun += createdCount
            incrementPotatoCount(by: createdCount)
            notifyLevelUpdate()
        }
    }

    /// Removes a node from both SpriteKit and the underlying level state.
    func removeSchmojiNode(_ node: SchmojiSpriteNode, from scene: SKScene) {
        let object = node.schmojiObject

        if node.parent != nil {
            node.makeByeBye()
        } else {
            node.removeFromParent()
        }

        currentLevel.removeLevelObject(withId: object.id, in: modelContext)
        if let gameScene = scene as? PotatoGameScene {
            gameScene.applyStoredObjectRemoval(withId: object.id)
        }

        notifyLevelUpdate()
    }

    /// Persists dynamically spawned Schmojis so the board stays in sync.
    func registerSpawnedObject(_ object: SchmojiBoardObject, in scene: PotatoGameScene?) {
        currentLevel.addLevelObject(object, in: modelContext)
        scene?.appendStoredObject(object)
        notifyLevelUpdate()
    }
}
