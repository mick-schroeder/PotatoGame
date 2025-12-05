// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SpriteKit

struct SchmojiCollisionSummary {
    let categoryA: UInt32
    let categoryB: UInt32
    let impulse: CGFloat
}

final class UnownedContactDelegate: NSObject, SKPhysicsContactDelegate {
    private weak var scene: SchmojiGameScene?

    init(scene: SchmojiGameScene) {
        self.scene = scene
    }

    func didBegin(_ contact: SKPhysicsContact) {
        // Filter collision category/impulse before invoking haptics to avoid per-contact Task churn.
        let categoryA = contact.bodyA.categoryBitMask
        let categoryB = contact.bodyB.categoryBitMask
        let impulse = contact.collisionImpulse
        let schmoji = SchmojiPhysicsCategory.schmoji
        let edge = SchmojiPhysicsCategory.edge

        let firstIsSchmoji = categoryA == schmoji
        let secondIsSchmoji = categoryB == schmoji
        guard firstIsSchmoji || secondIsSchmoji else { return }
        let otherMask = firstIsSchmoji ? categoryB : categoryA

        let collisionKind: SchmojiGameScene.CollisionKind? = switch otherMask {
        case edge:
            .schmojiEdge
        case schmoji:
            .schmojiSchmoji
        default:
            nil
        }
        guard let kind = collisionKind else { return }
        guard impulse >= SchmojiGameScene.CollisionHaptics.threshold(for: kind) else { return }

        guard let scene else { return }

        let summary = SchmojiCollisionSummary(categoryA: categoryA, categoryB: categoryB, impulse: impulse)

        Task { [weak scene] in
            guard let scene else { return }
            await scene.handleCollisionFeedback(summary: summary)
        }
    }
}
