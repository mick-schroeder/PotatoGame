// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SpriteKit

enum PotatoGamePhysicsCategory {
    static let edge: UInt32 = 1 << 0
    static let schmoji: UInt32 = 1 << 1

    static func configure(_ body: SKPhysicsBody, category: UInt32, collisions: UInt32, contacts: UInt32) {
        body.categoryBitMask = category
        body.collisionBitMask = collisions
        body.contactTestBitMask = contacts
    }
}
