// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import OSLog
import SwiftData

public enum GameState: String, Codable, CaseIterable, Hashable, Sendable {
    case newUnlocked
    case newLevelPack
    case playing
    case win
    case winPerfect
    case lose

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        switch rawValue {
        case Self.newLevelPack.rawValue: self = .newLevelPack
        case Self.playing.rawValue: self = .playing
        case Self.win.rawValue: self = .win
        case Self.winPerfect.rawValue: self = .winPerfect
        case Self.lose.rawValue: self = .lose
        default: self = .newUnlocked
        }
    }

    public var iconSystemName: String {
        switch self {
        case .newUnlocked: "play"
        case .newLevelPack: "lock.fill"
        case .playing: "playpause"
        case .win: "checkmark"
        case .winPerfect: "medal"
        case .lose: "xmark"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct PotatoGameLevelInfo: Identifiable, Hashable {
    var id: Int { levelNumber }

    let levelNumber: Int
    let levelBackgroundColor: PotatoColor
    let potentialPotatoCount: Int
    var progress: PotatoGameLevelProgress?
    let ownedLevelPackIDs: Set<String>

    var startedDate: Date? { progress?.startedDate }
    var completedDate: Date? { progress?.completedDate }
    var isCompleted: Bool { resolvedGameState == .win || resolvedGameState == .winPerfect || resolvedGameState == .lose }
    var isWon: Bool { resolvedGameState == .win || resolvedGameState == .winPerfect }
    var isLost: Bool { resolvedGameState == .lose }
    var isPlayable: Bool { resolvedGameState == .newUnlocked || resolvedGameState == .playing }
    var isLevelPackLocked: Bool { resolvedGameState == .newLevelPack }
    var requiresAdditionalLevelPack: Bool { LevelPackRegistry.definition(forLevel: levelNumber) != nil }
    var requiredLevelPack: LevelPackDefinition? { LevelPackRegistry.definition(forLevel: levelNumber) }

    private var resolvedGameState: GameState {
        if needsLevelPackAccess { return .newLevelPack }
        return progress?.gameState ?? defaultState
    }

    private var defaultState: GameState {
        needsLevelPackAccess ? .newLevelPack : .newUnlocked
    }

    private var needsLevelPackAccess: Bool {
        guard let pack = requiredLevelPack else { return false }
        return ownedLevelPackIDs.contains(pack.id) == false
    }

    init(template: LevelTemplate, progress: PotatoGameLevelProgress? = nil, ownedLevelPackIDs: Set<String> = []) {
        levelNumber = template.levelNumber
        levelBackgroundColor = template.backgroundColor
        potentialPotatoCount = template.potentialPotatoCount
        self.ownedLevelPackIDs = ownedLevelPackIDs
        self.progress = progress
    }

    init(levelNumber: Int,
         levelBackgroundColor: PotatoColor,
         potentialPotatoCount: Int,
         progress: PotatoGameLevelProgress? = nil,
         ownedLevelPackIDs: Set<String> = [])
    {
        self.levelNumber = levelNumber
        self.levelBackgroundColor = levelBackgroundColor
        self.potentialPotatoCount = potentialPotatoCount
        self.progress = progress
        self.ownedLevelPackIDs = ownedLevelPackIDs
    }
}

extension PotatoGameLevelInfo {
    private static let logger = Logger(subsystem: "PotatoGame", category: "PotatoGameLevelInfo")

    /// Convenience access to the static template for this level number (if any).
    var template: LevelTemplate? {
        LevelTemplateByNumber[levelNumber]
    }

    static func allLevels(progress: [PotatoGameLevelProgress], ownedLevelPackIDs: Set<String>) -> [PotatoGameLevelInfo] {
        let lookup = normalizedProgressLookup(from: progress)
        return LevelTemplates.map { template in
            PotatoGameLevelInfo(template: template, progress: lookup[template.levelNumber], ownedLevelPackIDs: ownedLevelPackIDs)
        }
    }

    static func nextPlayableLevel(progress: [PotatoGameLevelProgress], ownedLevelPackIDs: Set<String>) -> PotatoGameLevelInfo? {
        nextPlayableLevel(in: allLevels(progress: progress, ownedLevelPackIDs: ownedLevelPackIDs))
    }

    static func nextPlayableLevel(in levels: [PotatoGameLevelInfo]) -> PotatoGameLevelInfo? {
        levels.first(where: { $0.isPlayable && $0.isCompleted == false })
            ?? levels.first(where: { $0.isPlayable })
            ?? levels.first(where: { $0.isLevelPackLocked })
            ?? levels.first
    }

    static func level(number: Int, progress: [PotatoGameLevelProgress], ownedLevelPackIDs: Set<String>) -> PotatoGameLevelInfo? {
        guard let template = LevelTemplateByNumber[number] else {
            return nil
        }
        let progress = normalizedProgressLookup(from: progress)[number]
        return PotatoGameLevelInfo(template: template, progress: progress, ownedLevelPackIDs: ownedLevelPackIDs)
    }

    static func level(number: Int, context: ModelContext, ownedLevelPackIDs: Set<String>) -> PotatoGameLevelInfo? {
        guard let template = LevelTemplateByNumber[number] else {
            return nil
        }
        var descriptor = FetchDescriptor<PotatoGameLevelProgress>()
        descriptor.predicate = #Predicate { $0.levelNumber == number }
        descriptor.fetchLimit = 1
        let progress = try? context.fetch(descriptor).first
        return PotatoGameLevelInfo(template: template, progress: progress, ownedLevelPackIDs: ownedLevelPackIDs)
    }
}

@MainActor
extension PotatoGameLevelInfo {
    @discardableResult
    mutating func ensureProgress(in context: ModelContext) -> PotatoGameLevelProgress {
        guard let ensured = ensureProgressIfNeeded(context) else {
            fatalError("Unable to create progress for level \(levelNumber)")
        }
        return ensured
    }

    var hasGeneratedLayout: Bool {
        !(progress?.storedTiles?.isEmpty ?? true)
    }

    var schmojiInLevel: [PotatoGameBoardObject] {
        get {
            _ = progress?.loadFromTemplateIfNeeded()
            return progress?.boardObjects ?? []
        }
        set {
            progress?.setBoardObjects(newValue)
        }
    }

    mutating func addLevelObject(_ object: PotatoGameBoardObject, in context: ModelContext? = nil) {
        updateProgress(in: context) { progress in
            progress.replaceTile(with: object)
        }
    }

    mutating func removeLevelObject(withId id: UUID, in context: ModelContext? = nil) {
        updateProgress(in: context) { progress in
            progress.removeTile(id: id)
        }
    }

    mutating func discardStoredLayout(in context: ModelContext? = nil) {
        updateProgress(in: context) { progress in
            progress.storedTiles = []
            progress.updatedAt = .now
        }
    }

    mutating func commitLayoutIfNeeded(in _: ModelContext? = nil) {
        // Placeholder for parity with the old SchmojiLevel API.
    }

    mutating func startPlaying(in context: ModelContext? = nil) {
        updateProgress(in: context) { progress in
            if progress.startedDate == nil {
                progress.startedDate = Date()
            }
            progress.gameState = .playing
        }
    }

    mutating func completeLevel(perfect: Bool = false, in context: ModelContext? = nil) {
        updateProgress(in: context) { progress in
            progress.completedDate = Date()
            progress.gameState = perfect ? .winPerfect : .win
        }
    }

    mutating func ensureTemplateLayout(in context: ModelContext? = nil) {
        updateProgress(in: context) { progress in
            if progress.storedTiles?.isEmpty ?? true {
                let generated = progress.loadFromTemplateIfNeeded()
                if generated || (progress.storedTiles?.isEmpty ?? true) {
                    progress.numOfPotatoesCreated = 0
                }
            }
        }
    }

    var numOfPotatoesCreated: Int {
        get { progress?.numOfPotatoesCreated ?? 0 }
        set { progress?.numOfPotatoesCreated = newValue }
    }

    var gameState: GameState {
        get { progress?.gameState ?? defaultState }
        set { progress?.gameState = newValue }
    }

    @discardableResult
    mutating func ensureProgressIfNeeded(_ context: ModelContext?) -> PotatoGameLevelProgress? {
        if let existing = progress {
            return existing
        }
        guard let ctx = context else { return nil }

        if let persisted = PotatoGameLevelProgress.progress(levelNumber: levelNumber, in: ctx) {
            progress = persisted
            return persisted
        }

        let created = PotatoGameLevelProgress(levelNumber: levelNumber, gameState: defaultState)
        ctx.insert(created)
        created.loadFromTemplateIfNeeded()
        progress = created
        let currentLevelNumber = levelNumber
        do {
            if ctx.hasChanges {
                try ctx.save()
            }
        } catch {
            Self.logger.error("Failed to save new level progress for \(currentLevelNumber, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return created
    }

    mutating func updateProgress(in context: ModelContext?, _ update: (PotatoGameLevelProgress) -> Void) {
        guard let progress = ensureProgressIfNeeded(context) else { return }
        update(progress)
    }

    func potentialPotatoCountInGame(using providedCounts: [PotatoColor: Int]? = nil) -> Int {
        guard let lastColor = PotatoGameOptions.lastColor else { return 0 }
        let matchThreshold = max(2, PotatoGameOptions.matchCountMin)

        let colorCounts: [PotatoColor: Int]
        if let providedCounts {
            colorCounts = providedCounts
        } else {
            var computedCounts: [PotatoColor: Int] = [:]
            for object in schmojiInLevel {
                let color = object.color
                computedCounts[color, default: 0] += 1
            }
            colorCounts = computedCounts
        }

        var promotableColors = PotatoColor.allCases.filter { $0 != lastColor }
        promotableColors.sort { $0.order < $1.order }
        guard promotableColors.isEmpty == false else { return 0 }

        var counts = promotableColors.map { colorCounts[$0, default: 0] }
        var potentialPotatoes = 0
        var didPromote = true

        while didPromote {
            didPromote = false

            for index in promotableColors.indices {
                let current = counts[index]
                guard current >= matchThreshold else { continue }

                let promoted = (current + 1) / 2
                counts[index] = 0
                didPromote = true

                if index + 1 < counts.count {
                    counts[index + 1] += promoted
                } else {
                    potentialPotatoes += promoted
                }
            }
        }

        return potentialPotatoes
    }
}

private extension PotatoGameLevelInfo {
    static func normalizedProgressLookup(from entries: [PotatoGameLevelProgress]) -> [Int: PotatoGameLevelProgress] {
        var lookup: [Int: PotatoGameLevelProgress] = [:]
        var duplicateLevels: Set<Int> = []

        for entry in entries {
            let levelNumber = entry.levelNumber
            if let existing = lookup[levelNumber] {
                duplicateLevels.insert(levelNumber)
                if entry.updatedAt >= existing.updatedAt {
                    lookup[levelNumber] = entry
                }
            } else {
                lookup[levelNumber] = entry
            }
        }

        if duplicateLevels.isEmpty == false {
            let sortedLevels = duplicateLevels.sorted()
            logger.notice("Resolved duplicate progress entries for levels: \(sortedLevels, privacy: .public)")
        }

        return lookup
    }
}
