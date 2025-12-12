// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Observation
import SpriteKit
import SwiftData
import SwiftUI

/// Glue layer that keeps SwiftUI state, SpriteKit scenes, and persistence in sync.
@MainActor
@Observable
final class PotatoGameSessionViewModel {
    private(set) var level: PotatoGameLevelInfo?
    private(set) var scene: PotatoGameScene?
    private(set) var unlockProgress: EmojiSelection.UnlockProgress?
    var presentedGameSheet: GameEndSheet?

    private var activeGameSheet: GameEndSheet?
    private var sessionManager: PotatoGameSessionManager?
    private var hasExplicitLevel: Bool
    private var sheetDismissedProgrammatically = false

    private var accounts: [Account] = []
    private var selections: [EmojiSelection] = []
    private var levelProgress: [PotatoGameLevelProgress] = []
    private var purchasedPackIDs: Set<String> = []
    private var modelContext: ModelContext?
    private var keyboardSettings: GameKeyboardSettings?
    private var globalHapticsEnabled: Bool = PotatoGameOptions.haptics

    init(initialLevel: PotatoGameLevelInfo? = nil) {
        level = initialLevel
        hasExplicitLevel = initialLevel != nil
    }

    var isPaused: Bool {
        scene?.isPaused ?? false
    }

    var hasNextLevel: Bool {
        nextUnlockedLevelAfterCurrent != nil
    }

    var levelNumberKey: LocalizedStringResource {
        if let level {
            return .levelsTileTitle(level.levelNumber)
        }
        return .levelsTitleGeneric
    }

    /// Syncs SwiftUI inputs with the SpriteKit session so the view stays up to date.
    /// Called from the main view whenever SwiftData publishes new fetch results or toggles change.
    func updateData(
        modelContext: ModelContext,
        colorScheme: ColorScheme,
        soundEnabled: Bool,
        hapticsEnabled: Bool,
        accounts: [Account],
        selections: [EmojiSelection],
        levelProgress: [PotatoGameLevelProgress],
        purchasedPackIDs: Set<String>,
        keyboardSettings: GameKeyboardSettings
    ) {
        self.modelContext = modelContext
        self.accounts = accounts
        self.selections = selections
        self.levelProgress = levelProgress
        self.purchasedPackIDs = purchasedPackIDs
        self.keyboardSettings = keyboardSettings

        ensureDefaultLevelIfNeeded()
        ensureSessionConfiguredIfPossible(
            colorScheme: colorScheme,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled
        )

        sessionManager?.updateOwnedLevelPackIDs(ownedLevelPackIDs)
        sessionManager?.updatePalette(palette)
        scene?.applyPalette(palette)
        scene?.keyboardSettings = keyboardSettings
        globalHapticsEnabled = hapticsEnabled
        updateSceneAppearance(colorScheme: colorScheme, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
    }

    /// Simple pause/resume toggle wired to the menu button.
    func togglePause() {
        scene?.isPaused.toggle()
    }

    /// Rebuilds the current level state and clears any presented sheet.
    func restartLevel() {
        dismissSheetProgrammatically()
        guard let manager = sessionManager else { return }
        if let currentScene = scene {
            manager.restartLevel(in: currentScene)
        } else {
            let newScene = manager.startGame()
            newScene.isPaused = false
            scene = newScene
        }
        level = manager.currentLevel
        updateGameEndSheet(for: manager.currentLevel)
    }

    /// Drops the sheet and puts the scene back into playing mode.
    func continueCurrentLevel() {
        dismissSheetProgrammatically()
        guard let manager = sessionManager, let currentScene = scene else { return }
        manager.continueCurrentLevel(in: currentScene)
        level?.gameState = .playing
        if let level {
            updateGameEndSheet(for: level)
        }
    }

    /// Advances to the next unlocked level (when the sheet asks for it).
    func navigateToNextLevel() {
        dismissSheetProgrammatically()
        guard let nextLevel = nextUnlockedLevelAfterCurrent ?? nextDefaultLevel else { return }
        guard nextLevel.isLevelPackLocked == false else { return }
        sessionManager?.flushPendingSave()
        hasExplicitLevel = false
        startNewSession(for: nextLevel)
    }

    /// Saves the current scene immediately so progress isn't lost.
    func persistSessionState() {
        guard let manager = sessionManager, let scene else { return }
        manager.saveGame(from: scene, immediate: true)
    }

    /// Stops any autosave work when the view disappears.
    func stopAutosaveLoop() {
        sessionManager?.stopAutosaveLoop()
    }

    /// Flushes state before the view dismisses back to home.
    func prepareForExit() {
        dismissSheetProgrammatically()
        sessionManager?.flushPendingSave()
    }

    /// Helper to safely touch the manager + scene from menu commands.
    func withSession(_ action: (PotatoGameSessionManager, PotatoGameScene) -> Void) {
        guard let manager = sessionManager, let scene else { return }
        action(manager, scene)
    }

    /// Lets the debug toggle drive SpriteKit overlays without leaking the scene.
    func applyDebugMatchOverlay(enabled: Bool) {
        scene?.setDebugMatchOverlay(enabled: enabled)
    }

    /// Handles the UIKit sheet dismissal to keep state consistent.
    func handleGameSheetDismissal() {
        defer { activeGameSheet = nil }

        if sheetDismissedProgrammatically {
            sheetDismissedProgrammatically = false
            return
        }

        guard let sheet = activeGameSheet else { return }
        switch sheet.kind {
        case .win where sheet.resumeOnDismiss:
            continueCurrentLevel()
        default:
            break
        }
    }

    /// Stores bookkeeping so we know if the sheet was dismissed manually.
    func markSheetPresented(_ sheet: GameEndSheet) {
        activeGameSheet = sheet
        sheetDismissedProgrammatically = false
    }

    /// What should we display as the potato count for this sheet?
    func potatoesEarned(for sheet: GameEndSheet) -> Int {
        sessionManager?.potatoesCreatedThisRun ?? sheet.level.numOfPotatoesCreated
    }

    func outcome(for sheet: GameEndSheet) -> PotatoGameEndView.Outcome {
        switch sheet.kind {
        case .win:
            let isPerfect = sheet.level.gameState == .winPerfect
            return .win(perfect: isPerfect, unlockProgress: sheet.unlockProgress, potatoesEarned: potatoesEarned(for: sheet))
        case .lose:
            return .lose
        }
    }
}

// MARK: - Session lifecycle

private extension PotatoGameSessionViewModel {
    var palette: [PotatoGameAppearance] {
        PotatoGameAppearance.palette(from: selections)
    }

    var ownedLevelPackIDs: Set<String> {
        if let account = accounts.first {
            return account.ownedLevelPackIDs
        }
        return purchasedPackIDs
    }

    var nextDefaultLevel: PotatoGameLevelInfo? {
        PotatoGameLevelInfo.nextPlayableLevel(progress: levelProgress, ownedLevelPackIDs: ownedLevelPackIDs)
    }

    var nextUnlockedLevelAfterCurrent: PotatoGameLevelInfo? {
        let levels = PotatoGameLevelInfo.allLevels(progress: levelProgress, ownedLevelPackIDs: ownedLevelPackIDs)
        guard let current = level else {
            return levels.first(where: { $0.isLevelPackLocked == false })
        }

        guard let currentIndex = levels.firstIndex(where: { $0.levelNumber == current.levelNumber }) else {
            return levels.first(where: { $0.isLevelPackLocked == false })
        }

        return levels.dropFirst(currentIndex + 1).first(where: { $0.isLevelPackLocked == false })
    }

    /// Picks a sensible default level when the view launches fresh.
    func ensureDefaultLevelIfNeeded() {
        guard hasExplicitLevel == false else { return }
        if let state = level?.gameState, state == .win || state == .winPerfect || state == .lose { return }
        guard let suggested = nextDefaultLevel else { return }
        if let current = level {
            guard current.levelNumber != suggested.levelNumber || current.gameState != suggested.gameState else { return }
        }
        level = suggested
        updateGameEndSheet(for: suggested)
    }

    /// Spins up the session manager once we have enough data.
    func ensureSessionConfiguredIfPossible(
        colorScheme: ColorScheme,
        soundEnabled: Bool,
        hapticsEnabled: Bool
    ) {
        guard scene == nil, let level else { return }
        guard let modelContext else { return }
        configureSession(
            for: level,
            modelContext: modelContext,
            colorScheme: colorScheme,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled
        )
    }

    /// Reuses the existing session when possible, otherwise builds a new one.
    /// Keeps SpriteKit scene creation cheap by diffing the requested level against the current manager.
    func configureSession(
        for level: PotatoGameLevelInfo,
        modelContext _: ModelContext,
        colorScheme: ColorScheme,
        soundEnabled: Bool,
        hapticsEnabled: Bool
    ) {
        guard level.isLevelPackLocked == false else { return }
        if let manager = sessionManager {
            bindLevelUpdates(to: manager)
            if manager.currentLevel.id == level.id {
                if scene == nil {
                    scene = manager.startGame()
                }
            } else {
                startNewSession(for: level)
            }
        } else {
            startNewSession(for: level)
        }
        updateSceneAppearance(colorScheme: colorScheme, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
    }

    /// Tears down any existing session and boots a brand new SpriteKit scene.
    func startNewSession(for targetLevel: PotatoGameLevelInfo) {
        guard targetLevel.isLevelPackLocked == false else { return }
        guard let account = resolvedAccount(), let modelContext else { return }

        dismissSheetProgrammatically()
        teardownCurrentSession(flushSceneState: true)
        let target = targetLevel
        level = target
        unlockProgress = nil
        let manager = PotatoGameSessionManager(
            account: account,
            context: modelContext,
            level: target,
            palette: palette,
            keyboardSettings: keyboardSettings ?? GameKeyboardSettings.shared
        )
        manager.updateOwnedLevelPackIDs(ownedLevelPackIDs)
        bindLevelUpdates(to: manager)
        sessionManager = manager
        let newScene = manager.startGame()
        scene = newScene
        level = manager.currentLevel
        updateGameEndSheet(for: manager.currentLevel)
    }

    /// Keeps the live SpriteKit scene in sync with SwiftUI toggles.
    func updateSceneAppearance(colorScheme: ColorScheme, soundEnabled: Bool, hapticsEnabled: Bool) {
        scene?.setColorScheme(colorScheme)
        scene?.setSoundEnabled(soundEnabled)
        scene?.setHapticsEnabled(hapticsEnabled)
    }

    /// Hooks manager callbacks back into our published SwiftUI state so sheets/HUD react immediately.
    func bindLevelUpdates(to manager: PotatoGameSessionManager) {
        manager.onLevelUpdate = { [weak self] updatedLevel in
            guard let self else { return }
            level = updatedLevel
            updateGameEndSheet(for: updatedLevel)
        }
        manager.onUnlockProgress = { [weak self] progress in
            guard let self else { return }
            unlockProgress = progress
            if let currentLevel = level {
                updateGameEndSheet(for: currentLevel, unlock: progress)
            }
        }
        manager.onLevelUpdate?(manager.currentLevel)
        manager.notifyCurrentUnlockProgress()
    }

    /// Builds the right sheet for the current level state and surfaces it to the view.
    func updateGameEndSheet(for level: PotatoGameLevelInfo, unlock: EmojiSelection.UnlockProgress? = nil) {
        let sheet = makeGameEndSheet(for: level, unlock: unlock ?? unlockProgress)
        activeGameSheet = sheet
        if sheet != nil {
            sheetDismissedProgrammatically = false
            triggerHaptics(for: level)
        }
        presentedGameSheet = sheet
    }

    /// Converts the level’s state into the win/lose sheet metadata.
    func makeGameEndSheet(for level: PotatoGameLevelInfo, unlock: EmojiSelection.UnlockProgress?) -> GameEndSheet? {
        switch level.gameState {
        case .win, .winPerfect:
            let resumeOnDismiss = level.gameState == .win
            return GameEndSheet(kind: .win, level: level, unlockProgress: unlock, hasNextLevel: hasNextLevel, resumeOnDismiss: resumeOnDismiss)
        case .lose:
            return GameEndSheet(kind: .lose, level: level, unlockProgress: nil, hasNextLevel: hasNextLevel, resumeOnDismiss: false)
        default:
            return nil
        }
    }

    private func triggerHaptics(for level: PotatoGameLevelInfo) {
        #if os(iOS)
            guard globalHapticsEnabled else { return }
            switch level.gameState {
            case .winPerfect:
                HapticsCoordinator.notification(.success, enabled: true)
            case .win:
                HapticsCoordinator.notification(.success, enabled: true)
            case .lose:
                HapticsCoordinator.notification(.error, enabled: true)
            default:
                break
            }
        #endif
    }

    /// Clears any presented sheet while letting the dismissal callback know it was intentional.
    func dismissSheetProgrammatically() {
        sheetDismissedProgrammatically = true
        presentedGameSheet = nil
        activeGameSheet = nil
    }

    /// Cleans up the current manager and scene before starting fresh.
    func teardownCurrentSession(flushSceneState: Bool = false) {
        guard let manager = sessionManager else {
            scene = nil
            return
        }

        if flushSceneState, let activeScene = scene {
            manager.saveGame(from: activeScene, immediate: true)
        } else {
            manager.flushPendingSave()
        }
        manager.stopAutosaveLoop()
        sessionManager = nil
        scene = nil
    }

    /// We only expect one account; fall back to the most recent if duplicates slip through.
    private func resolvedAccount() -> Account? {
        guard accounts.isEmpty == false else { return nil }
        if accounts.count == 1 { return accounts.first }

        // Prefer the default account when multiple entries exist, otherwise pick the newest.
        if let primary = accounts
            .filter({ $0.id == Account.defaultUserID })
            .max(by: { $0.joinDate < $1.joinDate })
        {
            return primary
        }

        return accounts.max { lhs, rhs in lhs.joinDate < rhs.joinDate }
    }
}
