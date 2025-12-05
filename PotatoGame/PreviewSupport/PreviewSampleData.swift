// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData
import SwiftUI

enum PreviewSampleData {
    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: DataGeneration.schema,
            configurations: [configuration]
        )
        seedIfNeeded(in: container.mainContext)
        return container
    }

    @MainActor
    static func makeLevelPackStore(purchasedPackIDs: Set<String> = []) -> LevelPackStore {
        let store = LevelPackStore()
        store.configureForPreviews(purchasedPackIDs: purchasedPackIDs)
        return store
    }

    static func sampleLevel(
        levelNumber: Int = 3,
        state: GameState = .playing,
        potatoes: Int = 6,
        ownedLevelPackIDs: Set<String> = []
    ) -> SchmojiLevelInfo {
        let template = LevelTemplateByNumber[levelNumber]
            ?? LevelTemplates.first
            ?? LevelTemplate(
                levelNumber: levelNumber,
                rows: [[nil]],
                backgroundColor: .green,
                potentialPotatoCount: potatoes
            )

        let progress = SchmojiLevelProgress(levelNumber: template.levelNumber, gameState: state)
        progress.numOfPotatoesCreated = potatoes
        return SchmojiLevelInfo(
            template: template,
            progress: progress,
            ownedLevelPackIDs: ownedLevelPackIDs
        )
    }

    static func sampleLevels() -> [SchmojiLevelInfo] {
        let lockedLevelNumber = SchmojiOptions.baseGameLevelLimit + 1
        return [
            sampleLevel(levelNumber: 1, state: .newUnlocked, potatoes: 2),
            sampleLevel(levelNumber: 2, state: .playing, potatoes: 3),
            sampleLevel(levelNumber: 3, state: .win, potatoes: 5),
            sampleLevel(levelNumber: 4, state: .winPerfect, potatoes: 8),
            sampleLevel(levelNumber: 5, state: .lose, potatoes: 1),
            sampleLevel(levelNumber: lockedLevelNumber, state: .newLevelPack, potatoes: 0),
        ]
    }

    static func sampleUnlockProgress() -> SchmojiSelection.UnlockProgress {
        let selection = SchmojiSelection(color: .yellow)
        selection.perfectWinCount = 7
        if let secondHex = selection.availableHexes.dropFirst().first {
            selection.unlock(hexcode: secondHex)
            selection.selectedHex = secondHex
        }
        return selection.currentUnlockProgress()
    }
}

private extension PreviewSampleData {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        DataGeneration.ensureBaselineData(modelContext: context)
        seedAccount(in: context)
        seedSelections(in: context)
        seedLevelProgress(in: context)
        do {
            try context.save()
        } catch {
            print("Preview seeding failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func seedAccount(in context: ModelContext) {
        var descriptor = FetchDescriptor<Account>()
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        if let account = try? context.fetch(descriptor).first {
            account.potatoCount = 256
            account.purchasedLevelPackIDs = []
        } else {
            let account = Account()
            account.potatoCount = 256
            context.insert(account)
        }
    }

    @MainActor
    static func seedSelections(in context: ModelContext) {
        let descriptor = FetchDescriptor<SchmojiSelection>()
        let selections = (try? context.fetch(descriptor)) ?? []
        for selection in selections {
            let unlocks = Array(selection.availableHexes.prefix(3))
            unlocks.forEach { selection.unlock(hexcode: $0) }
            selection.selectedHex = unlocks.first ?? selection.displayHexcode()
            selection.perfectWinCount = max(selection.perfectWinCount, 6)
        }
    }

    @MainActor
    static func seedLevelProgress(in context: ModelContext) {
        let sampleStates: [GameState] = [.newUnlocked, .playing, .win, .winPerfect, .lose]
        for (offset, state) in sampleStates.enumerated() {
            let levelNumber = offset + 1
            let progress = SchmojiLevelProgress(levelNumber: levelNumber, gameState: state)
            progress.numOfPotatoesCreated = (offset + 1) * 3
            progress.loadFromTemplateIfNeeded()
            context.insert(progress)
        }

        let lockedLevelNumber = SchmojiOptions.baseGameLevelLimit + 1
        let lockedProgress = SchmojiLevelProgress(levelNumber: lockedLevelNumber, gameState: .newUnlocked)
        lockedProgress.loadFromTemplateIfNeeded()
        context.insert(lockedProgress)
    }
}

extension ProcessInfo {
    static var isRunningPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
