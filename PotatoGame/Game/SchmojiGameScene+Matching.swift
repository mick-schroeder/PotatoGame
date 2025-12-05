// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit
#endif
import Foundation
import SpriteKit

/// Matching/selection helpers extracted from the main SpriteKit scene.
@MainActor
extension SchmojiGameScene {
    private func isConnected(_ testNode: SchmojiSpriteNode, to baseNode: SchmojiSpriteNode) -> Bool {
        intersects(testNode, baseNode)
    }

    /// Depth-first flood fill that gathers all connected nodes of the same color.
    private func schmojiCombo(accumulated: [SchmojiSpriteNode], around baseNode: SchmojiSpriteNode) -> [SchmojiSpriteNode] {
        var combo = accumulated
        if combo.contains(where: { $0 === baseNode }) == false {
            combo.append(baseNode)
        }

        pruneSchmojiNodes()
        for target in schmojiNodes where target !== baseNode && target.schmojiColor == baseNode.schmojiColor {
            guard combo.contains(where: { $0 === target }) == false else { continue }
            if isConnected(target, to: baseNode) {
                combo = schmojiCombo(accumulated: combo, around: target)
            }
        }

        return combo
    }

    private func intersects(_ lhs: SchmojiSpriteNode, _ rhs: SchmojiSpriteNode) -> Bool {
        let lhsRadius = matchRadius(for: lhs)
        let rhsRadius = matchRadius(for: rhs)
        guard lhsRadius > 0, rhsRadius > 0 else { return false }

        let dx = lhs.position.x - rhs.position.x
        let dy = lhs.position.y - rhs.position.y
        let distanceSquared = dx * dx + dy * dy
        let allowedDistance = lhsRadius + rhsRadius
        return distanceSquared <= allowedDistance * allowedDistance
    }

    func rawRadius(for node: SchmojiSpriteNode) -> CGFloat {
        node.visualRadius * node.xScale
    }

    func matchRadius(for node: SchmojiSpriteNode) -> CGFloat {
        let radius = rawRadius(for: node)
        guard radius > 0 else { return 0 }
        let expansion = max(matchExpansionMinimum, radius * matchExpansionFraction)
        return radius + expansion
    }

    func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Clears selection state and restores all nodes to their idle visuals.
    func clearSchmojiSelection() {
        pruneSchmojiNodes()
        for schmoji in schmojiNodes {
            schmoji.makeUnSelected()
            schmoji.remove = false
            schmoji.updateCoordinates()
        }
        selectedSchmojiNodes.removeAll()
        currentMatchClusterIndex = -1
    }

    /// Main tap handler that toggles selection or evolves a chain.
    func handleSelection(at location: CGPoint) {
        guard let tappedNode = nodes(at: location).compactMap({ $0 as? SchmojiSpriteNode }).first else {
            clearSchmojiSelection()
            return
        }

        if selectedSchmojiNodes.contains(where: { $0 === tappedNode }), tappedNode.schmojiColor != SchmojiOptions.lastColor {
            evolveChain(from: tappedNode)
        } else if tappedNode.schmojiColor == SchmojiOptions.lastColor {
            // Do nothing for final color
            clearSchmojiSelection()
        } else {
            startNewSelection(from: tappedNode)
        }
    }

    /// Converts the current selection into evolved Schmojis + potato updates.
    func evolveChain(from node: SchmojiSpriteNode) {
        let chainCount = selectedSchmojiNodes.count
        guard chainCount > 0 else { return }

        let newSchmojiCount = (chainCount + 1) / 2

        for _ in 0 ..< newSchmojiCount {
            generateNewSchmojiFromPosition(schmoji: node)
        }

        sessionManager?.trackPotatoCreation(from: node.schmojiColor, createdCount: newSchmojiCount)
        playSound(.matchSuccess)

        for schmoji in selectedSchmojiNodes {
            removeSchmojiNode(schmoji)
        }

        clearSchmojiSelection()
        checkForGameEnd()
        sessionManager?.scheduleEvolutionSave(from: self)
        #if os(iOS)
            if hapticsEnabled {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        #endif
    }

    /// Finds a cluster around the tapped node and applies highlighting/haptics.
    func startNewSelection(from node: SchmojiSpriteNode) {
        if selectedSchmojiNodes.isEmpty == false {
            clearSchmojiSelection()
        }

        selectedSchmojiNodes = schmojiCombo(accumulated: [], around: node)
        let clusters = computeSelectableClusters()
        if let index = clusters.firstIndex(where: { cluster in
            cluster.contains(where: { $0 === node })
        }) {
            currentMatchClusterIndex = index
        }

        let count = selectedSchmojiNodes.count

        if count >= SchmojiOptions.matchCountMin {
            for schmoji in selectedSchmojiNodes {
                schmoji.remove = true
                schmoji.makeSelected()
            }

            pruneSchmojiNodes()
            for schmoji in schmojiNodes where schmoji.remove == false {
                if schmoji.schmojiColor == node.schmojiColor {
                    schmoji.makePausedSameColor()
                } else {
                    schmoji.makePaused()
                }
            }
            #if os(iOS)
                if hapticsEnabled {
                    let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle =
                        count > 10 ? .heavy : count > 5 ? .medium : .light
                    let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
                    generator.impactOccurred()
                }
            #endif
            playSound(.matchReady)
        } else {
            #if os(iOS)
                if hapticsEnabled {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            #endif
            playSound(.matchFail)
            clearSchmojiSelection()

            pruneSchmojiNodes()
            for schmoji in schmojiNodes {
                if schmoji === node {
                    schmoji.makeTouched()
                } else {
                    schmoji.fadeInandOut()
                }
            }
        }
    }

    /// Spawns the next-color Schmoji near a match origin with a ripple.
    func generateNewSchmojiFromPosition(schmoji: SchmojiSpriteNode) {
        guard let manager = sessionManager else { return }
        let nextColor = schmoji.schmojiColor.nextColor()

        let offset = schmoji.size.width / 2
        let rawX = schmoji.position.x + CGFloat.random(in: -offset ... offset)
        let rawY = schmoji.position.y + CGFloat.random(in: -offset ... offset)
        let clampedX = max(offset, min(rawX, size.width - offset))
        let clampedY = max(offset, min(rawY, size.height - offset))
        let newPosition = CGPoint(x: clampedX, y: clampedY)

        let newLevelObject = SchmojiBoardObject(
            color: nextColor,
            positionX: Double(newPosition.x),
            positionY: Double(newPosition.y)
        )

        manager.registerSpawnedObject(newLevelObject, in: self)
        let newNode = manager.createNode(for: newLevelObject)
        let originalScaleX = newNode.xScale
        let originalScaleY = newNode.yScale
        addChild(newNode)
        registerSchmojiNode(newNode)
        runSpawnAnimation(for: newNode, originalScaleX: originalScaleX, originalScaleY: originalScaleY)
        if newNode.schmojiColor == SchmojiOptions.lastColor {
            playSound(.potatoCreated)
        }
    }

    /// Keyboard/controller shortcut to evolve the current selection.
    func confirmCurrentSelection() {
        guard let anchor = selectedSchmojiNodes.first else { return }
        evolveChain(from: anchor)
        currentMatchClusterIndex = -1
    }

    /// Cycles through selectable clusters for accessibility / keyboard play.
    func selectNextMatchCluster() {
        let clusters = computeSelectableClusters()
        guard clusters.isEmpty == false else {
            clearSchmojiSelection()
            return
        }
        currentMatchClusterIndex = (currentMatchClusterIndex + 1) % clusters.count
        if let anchor = clusters[currentMatchClusterIndex].first {
            startNewSelection(from: anchor)
        }
    }

    /// Computes matchable clusters sorted by a top-to-bottom, left-to-right order.
    private func computeSelectableClusters() -> [[SchmojiSpriteNode]] {
        pruneSchmojiNodes()
        var clusters: [[SchmojiSpriteNode]] = []
        var visited = Set<ObjectIdentifier>()

        for node in schmojiNodes {
            let identifier = ObjectIdentifier(node)
            if visited.contains(identifier) {
                continue
            }
            let combo = schmojiCombo(accumulated: [], around: node)
            combo.forEach { visited.insert(ObjectIdentifier($0)) }
            guard combo.count >= SchmojiOptions.matchCountMin, node.schmojiColor != SchmojiOptions.lastColor else {
                continue
            }
            clusters.append(combo)
        }

        clusters.sort { lhs, rhs in
            guard let left = lhs.first, let right = rhs.first else { return false }
            if left.position.y == right.position.y {
                return left.position.x < right.position.x
            }
            return left.position.y > right.position.y
        }
        return clusters
    }

    private func spawnAnimationDelay() -> TimeInterval {
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastSpawnAnimationTimestamp > 0.35 {
            spawnAnimationIndex = 0
        }
        lastSpawnAnimationTimestamp = now
        defer { spawnAnimationIndex += 1 }
        return 0.055 * Double(spawnAnimationIndex)
    }

    private func runSpawnAnimation(for node: SchmojiSpriteNode, originalScaleX: CGFloat, originalScaleY: CGFloat) {
        node.alpha = 0
        node.xScale = originalScaleX * 0.22
        node.yScale = originalScaleY * 0.22

        let delay = spawnAnimationDelay()
        let fadeIn = SKAction.fadeIn(withDuration: 0.18).easeOut()
        let overshoot = SKAction.scaleX(to: originalScaleX * 1.18, y: originalScaleY * 1.18, duration: 0.24).easeOut()
        let settle = SKAction.scaleX(to: originalScaleX, y: originalScaleY, duration: 0.16).easeInEaseOut()

        let sequence = SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.group([fadeIn, overshoot]),
            SKAction.run { [weak self, weak node] in
                guard let self, let node else { return }
                runSpawnRipple(from: node)
            },
            settle,
            SKAction.run { [weak node] in
                node?.bounce()
            },
        ])

        node.run(sequence, withKey: "SchmojiSpawn")
    }

    private func runSpawnRipple(from originNode: SchmojiSpriteNode) {
        pruneSchmojiNodes()
        let rippleKey = "SchmojiSpawnRipple"
        let origin = originNode.position
        let diagonal = hypot(size.width, size.height)
        guard diagonal > 0 else { return }

        for target in schmojiNodes {
            guard target !== originNode, target.parent != nil else { continue }

            let distance = hypot(target.position.x - origin.x, target.position.y - origin.y)
            let normalized = max(CGFloat(0), min(CGFloat(1), distance / diagonal))
            let rippleDelay = 0.04 + 0.22 * Double(normalized)

            let originalScaleX = target.xScale
            let originalScaleY = target.yScale

            let pulseUp = SKAction.scaleX(to: originalScaleX * 1.08, y: originalScaleY * 1.08, duration: 0.12).easeOut()
            let pulseDown = SKAction.scaleX(to: originalScaleX, y: originalScaleY, duration: 0.18).easeInEaseOut()

            let ripple = SKAction.sequence([
                SKAction.wait(forDuration: rippleDelay),
                pulseUp,
                pulseDown,
            ])

            target.removeAction(forKey: rippleKey)
            target.run(ripple, withKey: rippleKey)
        }
    }
}
