// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData

@Model final class SchmojiLevelTile {
    var id: UUID = UUID()
    var colorRawValue: String = SchmojiColor.green.rawValue
    var positionX: Double?
    var positionY: Double?

    var progress: SchmojiLevelProgress?

    init(id: UUID = UUID(), color: SchmojiColor, positionX: Double?, positionY: Double?, progress: SchmojiLevelProgress? = nil) {
        self.id = id
        colorRawValue = color.rawValue
        self.positionX = positionX
        self.positionY = positionY
        self.progress = progress
    }
}

extension SchmojiLevelTile {
    var color: SchmojiColor {
        get { SchmojiColor(rawValue: colorRawValue) ?? .green }
        set { colorRawValue = newValue.rawValue }
    }

    var boardObject: SchmojiBoardObject {
        SchmojiBoardObject(id: id, color: color, positionX: positionX, positionY: positionY)
    }

    func update(from boardObject: SchmojiBoardObject) {
        id = boardObject.id
        color = boardObject.color
        positionX = boardObject.positionX
        positionY = boardObject.positionY
    }
}
