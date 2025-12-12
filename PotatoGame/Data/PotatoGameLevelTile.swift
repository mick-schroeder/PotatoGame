// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData

@Model final class PotatoGameLevelTile {
    var id: UUID = UUID()
    var colorRawValue: String = PotatoColor.green.rawValue
    var positionX: Double?
    var positionY: Double?

    var progress: PotatoGameLevelProgress?

    init(id: UUID = UUID(), color: PotatoColor, positionX: Double?, positionY: Double?, progress: PotatoGameLevelProgress? = nil) {
        self.id = id
        colorRawValue = color.rawValue
        self.positionX = positionX
        self.positionY = positionY
        self.progress = progress
    }
}

extension PotatoGameLevelTile {
    var color: PotatoColor {
        get { PotatoColor(rawValue: colorRawValue) ?? .green }
        set { colorRawValue = newValue.rawValue }
    }

    var boardObject: PotatoGameBoardObject {
        PotatoGameBoardObject(id: id, color: color, positionX: positionX, positionY: positionY)
    }

    func update(from boardObject: PotatoGameBoardObject) {
        id = boardObject.id
        color = boardObject.color
        positionX = boardObject.positionX
        positionY = boardObject.positionY
    }
}
