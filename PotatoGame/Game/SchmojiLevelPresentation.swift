// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation

/// Lightweight DTO that mirrors the level data needed by SpriteKit.
struct SchmojiLevelPresentation {
    let levelNumber: Int
    let backgroundColor: SchmojiColor
    let potentialPotatoCount: Int
    let ownedLevelPackIDs: Set<String>
    var objects: [SchmojiBoardObject]

    @MainActor
    init(levelInfo: SchmojiLevelInfo) {
        levelNumber = levelInfo.levelNumber
        backgroundColor = levelInfo.levelBackgroundColor
        potentialPotatoCount = levelInfo.potentialPotatoCount
        ownedLevelPackIDs = levelInfo.ownedLevelPackIDs
        objects = levelInfo.schmojiInLevel
    }
}
