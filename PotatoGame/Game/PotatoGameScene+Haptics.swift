// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SpriteKit

extension PotatoGameScene {
    #if os(iOS)
        func prepareCollisionFeedbackIfNeeded() {
            guard hapticsEnabled else { return }
            collisionFeedbackGenerator.prepare()
        }

        @MainActor
        func handleCollisionFeedback(summary: SchmojiCollisionSummary) {
            guard hapticsEnabled else { return }
            guard let kind = collisionKind(for: summary) else { return }
            guard summary.impulse >= CollisionHaptics.threshold(for: kind) else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCollisionFeedbackTime > 0.08 else { return }
            lastCollisionFeedbackTime = now
            collisionFeedbackGenerator.impactOccurred(intensity: CollisionHaptics.intensity(for: kind))
            collisionFeedbackGenerator.prepare()
        }
    #else
        func prepareCollisionFeedbackIfNeeded() {}

        @MainActor
        func handleCollisionFeedback(summary _: SchmojiCollisionSummary) {}
    #endif
}

extension PotatoGameScene {
    enum CollisionKind {
        case schmojiEdge
        case schmojiSchmoji
    }

    enum CollisionHaptics {
        static let schmojiThreshold: CGFloat = 0.3
        static let edgeThreshold: CGFloat = 0.55
        static let schmojiIntensity: CGFloat = 0.38
        static let edgeIntensity: CGFloat = 0.65

        static func threshold(for kind: CollisionKind) -> CGFloat {
            switch kind {
            case .schmojiSchmoji:
                schmojiThreshold
            case .schmojiEdge:
                edgeThreshold
            }
        }

        static func intensity(for kind: CollisionKind) -> CGFloat {
            switch kind {
            case .schmojiSchmoji:
                schmojiIntensity
            case .schmojiEdge:
                edgeIntensity
            }
        }
    }

    func collisionKind(for summary: SchmojiCollisionSummary) -> CollisionKind? {
        let schmoji = PotatoGamePhysicsCategory.schmoji
        let edge = PotatoGamePhysicsCategory.edge

        let firstIsSchmoji = summary.categoryA == schmoji
        let secondIsSchmoji = summary.categoryB == schmoji
        guard firstIsSchmoji || secondIsSchmoji else { return nil }
        let otherMask = firstIsSchmoji ? summary.categoryB : summary.categoryA
        if otherMask == edge {
            return .schmojiEdge
        } else if otherMask == schmoji {
            return .schmojiSchmoji
        }
        return nil
    }
}
