// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit
#endif
import Foundation
import SpriteKit

/// Matching/selection helpers extracted from the main SpriteKit scene.
@MainActor
extension PotatoGameScene {
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
        let chain = selectedSchmojiNodes
        let chainCount = chain.count
        guard chainCount > 0 else { return }

        let color = node.schmojiColor
        let newSchmojiCount = (chainCount + 1) / 2

        let fxDuration = runEvolutionVisualization(for: chain, color: color)

        let evolveWork = { [weak self] in
            guard let self else { return }

            for _ in 0 ..< newSchmojiCount {
                generateNewSchmojiFromPosition(schmoji: node)
            }

            sessionManager?.trackPotatoCreation(from: node.schmojiColor, createdCount: newSchmojiCount)
            playSound(.matchSuccess)

            for schmoji in chain {
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

        if fxDuration > 0 {
            run(SKAction.sequence([
                SKAction.wait(forDuration: fxDuration),
                SKAction.run(evolveWork),
            ]), withKey: "SchmojiEvolutionMerge")
        } else {
            evolveWork()
        }
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
        if now - lastSpawnAnimationTimestamp > 0.24 {
            spawnAnimationIndex = 0
        }
        lastSpawnAnimationTimestamp = now
        defer { spawnAnimationIndex += 1 }
        return 0.03 * Double(spawnAnimationIndex)
    }

    private func runSpawnAnimation(for node: SchmojiSpriteNode, originalScaleX: CGFloat, originalScaleY: CGFloat) {
        node.alpha = 0
        node.xScale = originalScaleX * 0.24
        node.yScale = originalScaleY * 0.24
        node.zRotation = CGFloat.random(in: -0.12 ... 0.12)

        let delay = spawnAnimationDelay()
        let fadeAndLift = SKAction.group([
            SKAction.fadeIn(withDuration: 0.18).easeOut(),
            SKAction.scaleX(to: originalScaleX * 0.78, y: originalScaleY * 0.78, duration: 0.2).easeOut(),
        ])
        let dramaticPop = SKAction.group([
            SKAction.scaleX(to: originalScaleX * 1.22, y: originalScaleY * 1.22, duration: 0.26).easeOut(),
            SKAction.rotate(toAngle: 0, duration: 0.26, shortestUnitArc: true).easeOut(),
            SKAction.colorize(with: node.color, colorBlendFactor: 0.4, duration: 0.24).easeInEaseOut(),
        ])
        let settle = SKAction.group([
            SKAction.scaleX(to: originalScaleX * 0.98, y: originalScaleY * 0.98, duration: 0.18).easeInEaseOut(),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.16),
        ])
        let finalSettle = SKAction.scaleX(to: originalScaleX, y: originalScaleY, duration: 0.14).easeInEaseOut()

        let sequence = SKAction.sequence([
            SKAction.wait(forDuration: delay),
            fadeAndLift,
            dramaticPop,
            SKAction.run { [weak self, weak node] in
                guard let self, let node else { return }
                runSpawnFlare(from: node)
                runSpawnRipple(from: node)
            },
            settle,
            finalSettle,
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

    /// A bright flare that underscores a dramatic spawn.
    private func runSpawnFlare(from node: SchmojiSpriteNode) {
        let baseRadius = matchRadius(for: node) * 1.08
        guard baseRadius.isFinite, baseRadius > 0 else { return }

        let color = node.color
        let flareZ = node.zPosition - 0.2

        func addRing(lineWidth: CGFloat, scale: CGFloat, alpha: CGFloat, duration: TimeInterval, delay: TimeInterval) {
            let ring = SKShapeNode(circleOfRadius: baseRadius)
            ring.strokeColor = color.withAlphaComponent(alpha)
            ring.lineWidth = lineWidth
            ring.fillColor = color.withAlphaComponent(alpha * 0.25)
            ring.glowWidth = 10
            ring.alpha = 0
            ring.zPosition = flareZ
            ring.position = node.position
            ring.setScale(0.45)
            addChild(ring)

            let sequence = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([
                    SKAction.fadeAlpha(to: 1, duration: 0.12),
                    SKAction.scale(to: scale, duration: duration * 0.6).easeOut(),
                ]),
                SKAction.group([
                    SKAction.fadeOut(withDuration: duration * 0.4),
                    SKAction.scale(to: scale * 1.25, duration: duration * 0.4).easeInEaseOut(),
                ]),
                SKAction.removeFromParent(),
            ])
            ring.run(sequence, withKey: "SchmojiSpawnFlareRing")
        }

        addRing(lineWidth: 3.5, scale: 1.18, alpha: 0.82, duration: 0.36, delay: 0)
        addRing(lineWidth: 2.2, scale: 1.4, alpha: 0.55, duration: 0.44, delay: 0.04)
    }

    /// Brief visual that shows the current color evolving into the next one.
    @discardableResult
    private func runEvolutionVisualization(for nodes: [SchmojiSpriteNode], color: SchmojiColor) -> TimeInterval {
        guard nodes.isEmpty == false else { return 0 }
        let pulseDuration: TimeInterval = 0.5
        let animationColor = SchmojiSpriteNode.platformColor(for: colorScheme, color: color)
        
        let nextStroke = animationColor.withAlphaComponent(0.9)
        let nextFill = animationColor.withAlphaComponent(0.16)

        for (index, node) in nodes.enumerated() {
            let ringRadius = matchRadius(for: node) * 1.08
            let ring = SKShapeNode(circleOfRadius: ringRadius)
            ring.strokeColor = nextStroke
            ring.lineWidth = 5.0
            ring.fillColor = nextFill
            ring.glowWidth = 12
            ring.alpha = 0
            ring.position = node.position
            ring.zPosition = node.zPosition - 0.5
            addChild(ring)

            let rippleDelay = 0.04 * Double(index)
            let ringSequence = SKAction.sequence([
                SKAction.wait(forDuration: rippleDelay),
                SKAction.group([
                    SKAction.fadeAlpha(to: 1, duration: 0.1),
                    SKAction.scale(to: 1.24, duration: pulseDuration * 0.42).easeOut(),
                ]),
                SKAction.group([
                    SKAction.fadeOut(withDuration: pulseDuration * 0.38),
                    SKAction.scale(to: 1.4, duration: pulseDuration * 0.38).easeInEaseOut(),
                ]),
                SKAction.removeFromParent(),
            ])
            ring.run(ringSequence, withKey: "SchmojiEvolutionRing")

            let popUp = SKAction.scale(to: node.xScale * 1.2, duration: 0.14).easeOut()
            let tint = SKAction.colorize(with: animationColor, colorBlendFactor: 0.55, duration: 0.2).easeInEaseOut()
            let fade = SKAction.fadeAlpha(to: 0.4, duration: pulseDuration * 0.5).easeInEaseOut()
            let settle = SKAction.wait(forDuration: pulseDuration * 0.12)
            let nodeSequence = SKAction.sequence([
                SKAction.wait(forDuration: rippleDelay),
                SKAction.group([popUp, tint]),
                fade,
                settle,
            ])
            node.run(nodeSequence, withKey: "SchmojiEvolutionPreview")
        }

        return pulseDuration + 0.04 * Double(nodes.count)
    }
}
