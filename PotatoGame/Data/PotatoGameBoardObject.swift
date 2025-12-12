// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import CoreGraphics
import Foundation

/// Value-type representation of a Schmoji on the board so SpriteKit doesn't mutate SwiftData models directly.
struct PotatoGameBoardObject: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var color: PotatoColor
    var positionX: Double?
    var positionY: Double?

    init(id: UUID = UUID(), color: PotatoColor = .green, positionX: Double? = nil, positionY: Double? = nil) {
        self.id = id
        self.color = color
        self.positionX = positionX
        self.positionY = positionY
    }

    init(tile: PotatoGameLevelTile) {
        id = tile.id
        color = tile.color
        positionX = tile.positionX
        positionY = tile.positionY
    }

    var position: CGPoint? {
        get {
            guard let x = positionX, let y = positionY else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let point = newValue {
                positionX = Double(point.x)
                positionY = Double(point.y)
            } else {
                positionX = nil
                positionY = nil
            }
        }
    }

    func makeTile(progress: PotatoGameLevelProgress? = nil) -> PotatoGameLevelTile {
        PotatoGameLevelTile(id: id, color: color, positionX: positionX, positionY: positionY, progress: progress)
    }
}
