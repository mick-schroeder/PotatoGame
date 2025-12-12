// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData

@Model
final class PotatoGameLevelProgress {
    var levelNumber: Int = 0

    private var storedGameState: String = GameState.newUnlocked.rawValue
    var numOfPotatoesCreated: Int = 0
    var isDeleted: Bool = false
    var startedDate: Date?
    var completedDate: Date?
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \PotatoGameLevelTile.progress)
    var storedTiles: [PotatoGameLevelTile]?

    init(levelNumber: Int,
         gameState: GameState = GameState.newUnlocked)
    {
        self.levelNumber = levelNumber
        storedGameState = gameState.rawValue
    }

    /// If serialized objects are absent, hydrate them from the static level template.
    /// Returns true if new objects were generated and stored.
    @discardableResult
    func loadFromTemplateIfNeeded() -> Bool {
        guard storedTiles?.isEmpty ?? true else { return false }
        let generated = PotatoGameLevelLayoutGenerator.layoutObjects(for: levelNumber)
        guard generated.isEmpty == false else { return false }
        setBoardObjects(generated)
        numOfPotatoesCreated = 0
        return true
    }
}

extension PotatoGameLevelProgress {
    var gameState: GameState {
        get { GameState(rawValue: storedGameState) ?? .newUnlocked }
        set {
            let rawValue = newValue.rawValue
            guard storedGameState != rawValue else { return }
            storedGameState = rawValue
            updatedAt = .now
        }
    }
}

extension PotatoGameLevelProgress {
    static func progress(levelNumber: Int, in context: ModelContext) -> PotatoGameLevelProgress? {
        var descriptor = FetchDescriptor<PotatoGameLevelProgress>()
        descriptor.predicate = #Predicate { $0.levelNumber == levelNumber }
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func ensure(levelNumber: Int, defaultState: GameState, in context: ModelContext) -> PotatoGameLevelProgress {
        if let existing = progress(levelNumber: levelNumber, in: context) {
            return existing
        }
        let progress = PotatoGameLevelProgress(levelNumber: levelNumber, gameState: defaultState)
        // Materialize level objects from LevelTemplate for a brand-new progress record.
        progress.loadFromTemplateIfNeeded()
        context.insert(progress)
        return progress
    }

    var boardObjects: [PotatoGameBoardObject] {
        if storedTiles?.isEmpty ?? true {
            _ = loadFromTemplateIfNeeded()
        }
        return storedTiles?.map(\.boardObject) ?? []
    }

    func setBoardObjects(_ objects: [PotatoGameBoardObject]) {
        storedTiles = objects.map { $0.makeTile(progress: self) }
        updatedAt = .now
    }

    func replaceTile(with board: PotatoGameBoardObject) {
        if storedTiles == nil {
            storedTiles = []
        }
        if let index = storedTiles?.firstIndex(where: { $0.id == board.id }) {
            storedTiles?[index].update(from: board)
        } else {
            storedTiles?.append(board.makeTile(progress: self))
        }
        updatedAt = .now
    }

    func removeTile(id: UUID) {
        storedTiles?.removeAll { $0.id == id }
        updatedAt = .now
    }
}
