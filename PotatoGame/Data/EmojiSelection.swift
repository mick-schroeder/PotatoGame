// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import OSLog
import SwiftData

public struct SchmojiAppearance: Identifiable, Hashable {
    public let color: PotatoColor
    public let hexcode: String
    public var id: PotatoColor { color }
}

@Model
public final class EmojiSelection {
    public var colorRawValue: PotatoColor.RawValue = PotatoColor.green.rawValue
    public var selectedHex: String = ""
    public var perfectWinCount: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \SchmojiUnlockedHex.selection)
    var unlockedHexEntries: [SchmojiUnlockedHex]?

    private static let perfectWinsMilestone = 5

    public var unlockedHexes: [String] {
        get {
            (unlockedHexEntries ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(\.hexcode)
        }
        set {
            unlockedHexEntries = EmojiSelection
                .sanitizedUnlockedList(newValue, available: availableHexes)
                .enumerated()
                .map { index, hex in
                    SchmojiUnlockedHex(hexcode: hex, orderIndex: index, selection: self)
                }
        }
    }

    public init(color: PotatoColor, selectedHex: String? = nil, unlockedHexes: [String]? = nil) {
        colorRawValue = color.rawValue
        let defaults = color.schmojis
        let resolvedSelection = selectedHex ?? defaults.first ?? PotatoGameOptions.potatoHex
        self.selectedHex = resolvedSelection
        let resolvedUnlocked = unlockedHexes ?? [resolvedSelection]
        let list = Self.sanitizedUnlockedList(resolvedUnlocked + [resolvedSelection], available: defaults)
        self.unlockedHexes = list
    }

    public var color: PotatoColor {
        get { PotatoColor(rawValue: colorRawValue) ?? .green }
        set {
            colorRawValue = newValue.rawValue
            sanitizeSelection()
        }
    }

    public var availableHexes: [String] { color.schmojis }

    public func isUnlocked(_ hexcode: String) -> Bool {
        unlockedHexes.contains(hexcode)
    }

    public func unlock(hexcode: String) {
        var hexes = unlockedHexes
        guard hexes.contains(hexcode) == false else { return }
        hexes.append(hexcode)
        unlockedHexes = hexes
    }

    public func displayHexcode() -> String {
        if availableHexes.contains(selectedHex) {
            return selectedHex
        }
        return availableHexes.first ?? PotatoGameOptions.potatoHex
    }

    private func sanitizeSelection() {
        if availableHexes.contains(selectedHex) == false {
            selectedHex = availableHexes.first ?? PotatoGameOptions.potatoHex
        }
        var hexes = unlockedHexes.filter { availableHexes.contains($0) }
        if hexes.contains(selectedHex) == false {
            hexes.append(selectedHex)
        }
        unlockedHexes = hexes
    }
}

extension EmojiSelection {
    public struct UnlockProgress: Equatable {
        public let color: PotatoColor
        public let totalPerfectWins: Int
        public let winsTowardNextUnlock: Int
        public let winsRequired: Int
        public let remainingToNextUnlock: Int
        public let unlockedCount: Int
        public let totalSchmojis: Int
        public let didUnlockThisRun: Bool
        public let unlockedHexThisRun: String?
        public let nextUnlockHex: String?

        public var progressFraction: Double {
            guard totalSchmojis > 0 else { return 0 }
            if nextUnlockHex == nil { return 1 }
            return Double(winsTowardNextUnlock) / Double(winsRequired)
        }

        public var hasRemainingUnlocks: Bool { nextUnlockHex != nil }
    }

    func recordPerfectWin() -> UnlockProgress {
        perfectWinCount += 1
        var unlockedHex: String?

        if perfectWinCount % Self.perfectWinsMilestone == 0, let candidate = lockedHexes.randomElement() {
            unlock(hexcode: candidate)
            unlockedHex = candidate
        }

        return buildUnlockProgress(unlockedHex: unlockedHex)
    }

    func currentUnlockProgress() -> UnlockProgress {
        buildUnlockProgress(unlockedHex: nil)
    }

    static func selection(for color: PotatoColor, in context: ModelContext) -> EmojiSelection? {
        var descriptor = FetchDescriptor<EmojiSelection>()
        descriptor.predicate = #Predicate { $0.colorRawValue == color.rawValue }
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        return try? context.fetch(descriptor).first
    }

    static func resolve(color: PotatoColor, in context: ModelContext) -> EmojiSelection {
        if let existing = selection(for: color, in: context) {
            return existing
        }
        let selection = EmojiSelection(color: color)
        context.insert(selection)
        return selection
    }
}

private extension EmojiSelection {
    static func sanitizedUnlockedList(_ hexes: [String], available: [String]) -> [String] {
        var ordered: [String] = []
        for hex in hexes {
            let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, available.contains(normalized) else { continue }
            if ordered.contains(normalized) == false {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    var lockedHexes: [String] {
        availableHexes.filter { unlockedHexes.contains($0) == false }
    }

    var nextLockedHex: String? {
        lockedHexes.first
    }

    func buildUnlockProgress(unlockedHex: String?) -> UnlockProgress {
        let winsRequired = Self.perfectWinsMilestone
        let totalWins = perfectWinCount
        let remainder = totalWins % winsRequired
        let nextLocked = nextLockedHex

        let winsTowardNext: Int
        let remaining: Int

        if nextLocked == nil {
            winsTowardNext = winsRequired
            remaining = 0
        } else if remainder == 0 {
            winsTowardNext = 0
            remaining = winsRequired
        } else {
            winsTowardNext = remainder
            remaining = winsRequired - remainder
        }

        let availableCount = availableHexes.count
        let unlockedCount = unlockedHexes.filter { availableHexes.contains($0) }.count

        return UnlockProgress(
            color: color,
            totalPerfectWins: totalWins,
            winsTowardNextUnlock: winsTowardNext,
            winsRequired: winsRequired,
            remainingToNextUnlock: remaining,
            unlockedCount: unlockedCount,
            totalSchmojis: availableCount,
            didUnlockThisRun: unlockedHex != nil,
            unlockedHexThisRun: unlockedHex,
            nextUnlockHex: nextLocked
        )
    }
}

public extension SchmojiAppearance {
    static func palette(from selections: [EmojiSelection]) -> [SchmojiAppearance] {
        var lookup: [PotatoColor: String] = [:]
        for selection in selections {
            lookup[selection.color] = selection.displayHexcode()
        }

        return PotatoColor.allCases.map { color in
            let hex = lookup[color] ?? color.schmojis.first ?? PotatoGameOptions.potatoHex
            return SchmojiAppearance(color: color, hexcode: hex)
        }
    }
}

public extension EmojiSelection {
    static func ensureDefaults(in context: ModelContext) {
        let logger = Logger(subsystem: "PotatoGame", category: "SchmojiSelection")
        var descriptor = FetchDescriptor<EmojiSelection>()
        descriptor.includePendingChanges = true
        let existingSelections = (try? context.fetch(descriptor)) ?? []

        var seen: [PotatoColor: EmojiSelection] = [:]
        var duplicates: [EmojiSelection] = []

        for selection in existingSelections {
            let color = selection.color
            if let existing = seen[color] {
                duplicates.append(selection)
                let combined = existing.unlockedHexes + selection.unlockedHexes
                existing.unlockedHexes = Self.sanitizedUnlockedList(combined, available: existing.availableHexes)
                if selection.availableHexes.contains(selection.selectedHex) {
                    existing.selectedHex = selection.selectedHex
                }
                if selection.perfectWinCount > existing.perfectWinCount {
                    existing.perfectWinCount = selection.perfectWinCount
                }
            } else {
                seen[color] = selection
            }
        }

        let existingColors = Set(seen.keys)

        for selection in seen.values {
            selection.sanitizeSelection()
        }

        let missingColors = PotatoColor.allCases.filter { existingColors.contains($0) == false }
        for color in missingColors {
            let selection = EmojiSelection(color: color)
            context.insert(selection)
        }

        if duplicates.isEmpty == false {
            duplicates.forEach { context.delete($0) }
            logger.info("Removed duplicate SchmojiSelection records: \(duplicates.count, privacy: .public)")
        }

        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Failed to seed Schmoji selections: \(error.localizedDescription, privacy: .public)")
        }
    }
}
