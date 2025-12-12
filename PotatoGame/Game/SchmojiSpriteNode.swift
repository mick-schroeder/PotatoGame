// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit

    typealias UIColor = NSColor
#endif
import Foundation
import SpriteKit
import SwiftUI

/// SpriteKit node that renders a Schmoji face plus its background halo/physics.
final class SchmojiSpriteNode: SKSpriteNode {
    private static var circleTextureCache: [CircleTextureCacheKey: SKTexture] = [:]

    private struct CircleTextureCacheKey: Hashable {
        let color: PotatoColor
        let radius: CGFloat
        let signature: ColorSignature?
    }

    private struct GeometryMetrics {
        let fittedSize: CGSize
        let visualRadius: CGFloat
        let collisionRadius: CGFloat

        static func make(for texture: SKTexture, targetDiameter: CGFloat) -> GeometryMetrics {
            let fittedSize = SchmojiSpriteNode.fittedTextureSize(texture.size(), target: targetDiameter)
            let baseRadius = max(fittedSize.width, fittedSize.height) * 0.5
            let visualRadius = baseRadius + Constants.circlePadding
            let collisionRadius = visualRadius * Constants.physicsRadiusScale
            return GeometryMetrics(fittedSize: fittedSize, visualRadius: visualRadius, collisionRadius: collisionRadius)
        }
    }

    private struct ColorSignature: Hashable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        init?(color: UIColor) {
            guard let components = SchmojiSpriteNode.rgbaComponents(of: color) else { return nil }
            red = components.red
            green = components.green
            blue = components.blue
            alpha = components.alpha
        }
    }

    static func invalidateCircleTextureCache() {
        circleTextureCache.removeAll()
    }

    private enum Constants {
        static let circlePadding: CGFloat = 15
        static let circleScaleFactor: CGFloat = 0.8
        static let circleFillAlpha: CGFloat = 0.9
        static let circleStrokeAlpha: CGFloat = 0.9
        static let bounceScale: CGFloat = 1.075
        static let bounceDuration: TimeInterval = 0.22
        static let settleScale: CGFloat = 0.96
        static let pauseAlpha: CGFloat = 0.66
        static let haloLineWidth: CGFloat = 3.8
        static let haloGlowWidth: CGFloat = 14
        static let haloAnimationDuration: TimeInterval = 0.42
        static let physicsRadiusScale: CGFloat = 0.88
    }

    private enum ActionKey {
        static let bounce = "SchmojiBounce"
        static let emphasis = "SchmojiEmphasis"
        static let tint = "SchmojiTint"
        static let halo = "SchmojiHalo"
    }

    var schmojiObject: PotatoGameBoardObject
    let schmojiColor: PotatoColor
    private(set) var collisionRadius: CGFloat
    private(set) var visualRadius: CGFloat
    var unlockable: Bool = true
    var remove: Bool = false

    private var initialScale: CGFloat = 1
    private weak var backgroundNode: SKSpriteNode?
    private weak var selectionHalo: SKShapeNode?

    init(schmojiObject: PotatoGameBoardObject, appearance: PotatoGameAppearance?) {
        let resolvedColor: PotatoColor = schmojiObject.color

        let hexcode = appearance?.hexcode
            ?? resolvedColor.schmojis.first
            ?? PotatoGameOptions.potatoHex

        let targetDiameter = resolvedColor.size
        let texture = PotatoGameArt.texture(forHexcode: hexcode, targetDiameter: targetDiameter)
        let metrics = GeometryMetrics.make(for: texture, targetDiameter: targetDiameter)

        self.schmojiObject = schmojiObject
        schmojiColor = resolvedColor

        visualRadius = metrics.visualRadius
        collisionRadius = metrics.collisionRadius

        super.init(texture: texture, color: UIColor(resolvedColor.color), size: metrics.fittedSize)

        if let positionX = schmojiObject.positionX,
           let positionY = schmojiObject.positionY
        {
            position = CGPoint(x: positionX, y: positionY)
        }

        color = UIColor(schmojiColor.color)
        colorBlendFactor = 0
        name = "schmoji-\(schmojiObject.color.rawValue)"

        applyGeometry(metrics)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    private func applyGeometry(_ metrics: GeometryMetrics) {
        size = metrics.fittedSize
        visualRadius = metrics.visualRadius
        collisionRadius = metrics.collisionRadius
        physicsBody = makePhysicsBody()

        let preservedAlpha = backgroundNode?.alpha ?? 1
        backgroundNode?.removeFromParent()
        let backgroundSprite = createBackgroundCircleSprite(radius: visualRadius)
        backgroundSprite.alpha = preservedAlpha
        addChild(backgroundSprite)
        backgroundNode = backgroundSprite

        initialScale = xScale
    }

    private func makePhysicsBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(circleOfRadius: collisionRadius)
        let edge = PotatoGamePhysicsCategory.edge
        let schmoji = PotatoGamePhysicsCategory.schmoji
        PotatoGamePhysicsCategory.configure(
            body,
            category: schmoji,
            collisions: edge | schmoji,
            contacts: edge | schmoji
        )
        body.usesPreciseCollisionDetection = false
        body.allowsRotation = true
        return body
    }

    private func createBackgroundCircleSprite(radius: CGFloat) -> SKSpriteNode {
        let texture = Self.circleTexture(for: schmojiColor, radius: radius, baseColor: platformColor())
        let node = SKSpriteNode(texture: texture)
        node.zPosition = -1
        return node
    }

    private nonisolated static func rgbaComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if os(iOS)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
            return (red, green, blue, alpha)
        #else
            guard let converted = color.usingColorSpace(.deviceRGB) else { return nil }
            return (
                converted.redComponent,
                converted.greenComponent,
                converted.blueComponent,
                converted.alphaComponent
            )
        #endif
    }

    private nonisolated static func cgColor(from color: UIColor) -> CGColor {
        #if os(iOS)
            return color.cgColor
        #else
            if let converted = color.usingColorSpace(.deviceRGB)?.cgColor {
                return converted
            }
            return color.cgColor
        #endif
    }

    private static func circleTexture(for color: PotatoColor, radius: CGFloat, baseColor: UIColor) -> SKTexture {
        let fillColor = baseColor.withAlphaComponent(Constants.circleFillAlpha)
        let strokeColor = baseColor.withAlphaComponent(Constants.circleStrokeAlpha)

        let signature = ColorSignature(color: baseColor)
        let cacheKey = CircleTextureCacheKey(color: color, radius: radius, signature: signature)

        if let cached = circleTextureCache[cacheKey] {
            return cached
        }

        let texture = makeCircleTexture(radius: radius, fill: fillColor, stroke: strokeColor, lineWidth: 1)
        circleTextureCache[cacheKey] = texture
        return texture
    }

    private static func makeCircleTexture(radius: CGFloat, fill: UIColor, stroke: UIColor, lineWidth: CGFloat) -> SKTexture {
        let diameter = max(1, radius * 2)
        let size = CGSize(width: diameter, height: diameter)
        #if os(iOS)
            let scale = UIScreen.main.scale
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            format.scale = scale
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let image = renderer.image { ctx in
                let cg = ctx.cgContext
                let rect = CGRect(origin: .zero, size: size)
                cg.setFillColor(cgColor(from: fill))
                cg.setStrokeColor(cgColor(from: stroke))
                cg.setLineWidth(lineWidth)
                cg.addEllipse(in: rect)
                cg.drawPath(using: .fillStroke)
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return texture
        #else
            let img = NSImage(size: size)
            img.lockFocus()
            if let cg = NSGraphicsContext.current?.cgContext {
                let rect = CGRect(origin: .zero, size: size)
                cg.setFillColor(cgColor(from: fill))
                cg.setStrokeColor(cgColor(from: stroke))
                cg.setLineWidth(lineWidth)
                cg.addEllipse(in: rect)
                cg.drawPath(using: .fillStroke)
            }
            img.unlockFocus()
            let texture = SKTexture(image: img)
            texture.filteringMode = .linear
            return texture
        #endif
    }

    private static func makeConfettiTexture(color: UIColor) -> SKTexture {
        let size = CGSize(width: 32, height: 32)
        let rectSize = CGSize(width: size.width * 0.6, height: size.height * 0.6)
        #if os(iOS)
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            format.scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let image = renderer.image { ctx in
                let cg = ctx.cgContext
                cg.translateBy(x: size.width / 2, y: size.height / 2)
                cg.rotate(by: .pi / 4)
                let rect = CGRect(
                    x: -rectSize.width / 2,
                    y: -rectSize.height / 2,
                    width: rectSize.width,
                    height: rectSize.height
                )
                cg.setFillColor(cgColor(from: color))
                cg.fill(rect)
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return texture
        #else
            let image = NSImage(size: size)
            image.lockFocus()
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.translateBy(x: size.width / 2, y: size.height / 2)
                cg.rotate(by: .pi / 4)
                let rect = CGRect(
                    x: -rectSize.width / 2,
                    y: -rectSize.height / 2,
                    width: rectSize.width,
                    height: rectSize.height
                )
                cg.setFillColor(cgColor(from: color))
                cg.fill(rect)
            }
            image.unlockFocus()
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return texture
        #endif
    }

    func refreshCircleAppearance(for scheme: ColorScheme) {
        guard let backgroundNode else { return }
        let preservedAlpha = backgroundNode.alpha
        let texture = Self.circleTexture(for: schmojiColor, radius: visualRadius, baseColor: platformColor(for: scheme))
        backgroundNode.texture = texture
        backgroundNode.size = texture.size()
        backgroundNode.alpha = preservedAlpha
    }

    private nonisolated static func fittedTextureSize(_ size: CGSize, target: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: target, height: target)
        }
        let scale = min(target / size.width, target / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: - Selection & Animations

    func makeSelected() {
        guard unlockable else { return }
        physicsBody?.isDynamic = false
        backgroundNode?.alpha = 1
        runHaloPulse()
        runBounceLoop()
    }

    func bounce() {
        let emphasis = SKAction.sequence([
            SKAction.scale(to: initialScale * Constants.bounceScale, duration: 0.14).easeOut(),
            SKAction.scale(to: initialScale * Constants.settleScale, duration: 0.16).easeInEaseOut(),
            SKAction.scale(to: initialScale, duration: 0.18).easeOut(),
        ])
        run(emphasis, withKey: ActionKey.emphasis)
    }

    func fadeInandOut() {
        guard unlockable else { return }
        let tintDown = tintAction(colorBlendFactor: 0.85, alpha: 0.2, duration: 0.22)
        let wait = SKAction.wait(forDuration: 0.6)
        let tintUp = tintAction(colorBlendFactor: 0, alpha: 1, duration: 0.22)
        let sequence = SKAction.sequence([tintDown, wait, tintUp])
        run(sequence, withKey: ActionKey.tint)
    }

    func makeTouched() {
        bounce()
    }

    func makeNotTheOneToBeUnlocked() {
        unlockable = false
        applyLockTint()
        backgroundNode?.alpha = Constants.pauseAlpha
    }

    func makePaused() {
        guard unlockable else { return }
        run(tintAction(colorBlendFactor: 1, alpha: Constants.pauseAlpha, duration: 0.18), withKey: ActionKey.tint)
        physicsBody?.isDynamic = false
        backgroundNode?.alpha = Constants.pauseAlpha
    }

    func makePausedSameColor() {
        guard unlockable else { return }
        run(tintAction(colorBlendFactor: 0.66, alpha: Constants.pauseAlpha, duration: 0.18), withKey: ActionKey.tint)
        physicsBody?.isDynamic = false
        backgroundNode?.alpha = Constants.pauseAlpha
    }

    func makeUnSelected() {
        removeAction(forKey: ActionKey.bounce)
        removeAction(forKey: ActionKey.emphasis)
        removeAction(forKey: ActionKey.tint)

        setScale(initialScale)
        selectionHalo?.removeAction(forKey: ActionKey.halo)
        selectionHalo?.run(SKAction.fadeOut(withDuration: 0.12))
        physicsBody?.isDynamic = true

        if unlockable {
            colorBlendFactor = 0
            alpha = 1
            backgroundNode?.alpha = 1
        }
    }

    func hideSchmojiFromScene() {
        isHidden = true
        alpha = 0
        physicsBody = nil
        removeAllActions()
        backgroundNode?.isHidden = true
        selectionHalo?.isHidden = true
    }

    func makeByeBye() {
        let explosion = explosionEmitter()
        if let parent {
            explosion.position = position
            parent.addChild(explosion)
        } else if let scene {
            explosion.position = convert(.zero, to: scene)
            scene.addChild(explosion)
        } else {
            addChild(explosion)
        }

        let cleanup = SKAction.sequence([
            SKAction.wait(forDuration: 2.2),
            SKAction.run { [weak explosion] in
                explosion?.removeFromParent()
            },
        ])
        explosion.run(cleanup)

        hideSchmojiFromScene()
        removeFromParent()
    }

    func updateAppearance(_ appearance: PotatoGameAppearance) {
        guard appearance.color == schmojiColor else { return }
        let targetDiameter = schmojiColor.size
        let updatedTexture = PotatoGameArt.texture(forHexcode: appearance.hexcode, targetDiameter: targetDiameter)
        texture = updatedTexture
        let metrics = GeometryMetrics.make(for: updatedTexture, targetDiameter: targetDiameter)
        applyGeometry(metrics)
        let scheme = (scene as? PotatoGameScene)?.colorScheme ?? .light
        refreshCircleAppearance(for: scheme)
    }

    // MARK: - State Sync

    func updateCoordinates() {
        guard parent != nil else { return }
        schmojiObject.positionX = Double(position.x)
        schmojiObject.positionY = Double(position.y)
    }

    // MARK: - Private Helpers

    private func runBounceLoop() {
        if action(forKey: ActionKey.bounce) != nil { return }

        let scaleUp = SKAction.scale(to: initialScale * Constants.bounceScale, duration: Constants.bounceDuration).easeInEaseOut()
        let scaleDown = SKAction.scale(to: initialScale * Constants.settleScale, duration: Constants.bounceDuration).easeInEaseOut()
        let settle = SKAction.scale(to: initialScale, duration: Constants.bounceDuration * 0.9).easeInEaseOut()
        let delay = SKAction.wait(forDuration: 0.08)

        let loop = SKAction.sequence([scaleUp, scaleDown, settle, delay])
        run(SKAction.repeatForever(loop), withKey: ActionKey.bounce)
    }

    private func tintAction(colorBlendFactor: CGFloat, alpha: CGFloat, duration: TimeInterval) -> SKAction {
        let tint = SKAction.colorize(with: .black, colorBlendFactor: colorBlendFactor, duration: duration).easeInEaseOut()
        let fade = SKAction.fadeAlpha(to: alpha, duration: duration).easeInEaseOut()
        return SKAction.group([tint, fade])
    }

    private func applyLockTint() {
        let tint = SKAction.colorize(with: .black, colorBlendFactor: 1, duration: 0.1)
        let fade = SKAction.fadeAlpha(to: 0.7, duration: 0.1)
        run(SKAction.group([tint, fade]), withKey: ActionKey.tint)
    }

    private func runHaloPulse() {
        let halo = selectionHalo ?? createHalo()
        halo.removeAction(forKey: ActionKey.halo)
        halo.alpha = 0.3
        halo.setScale(1)

        let scaleUp = SKAction.scale(to: 1.18, duration: Constants.haloAnimationDuration).easeOut()
        let scaleDown = SKAction.scale(to: 0.96, duration: Constants.haloAnimationDuration * 0.74).easeInEaseOut()
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        halo.run(SKAction.repeatForever(pulse), withKey: ActionKey.halo)
    }

    private func createHalo() -> SKShapeNode {
        let radius = max(size.width, size.height) * 0.58
        let halo = SKShapeNode(circleOfRadius: radius)
        halo.lineWidth = Constants.haloLineWidth
        halo.strokeColor = UIColor.white.withAlphaComponent(0.55)
        halo.fillColor = .clear
        halo.glowWidth = Constants.haloGlowWidth
        halo.zPosition = -0.5
        halo.alpha = 0
        halo.blendMode = .add
        addChild(halo)
        selectionHalo = halo
        return halo
    }

    private func explosionEmitter() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let palette = PotatoColor.allCases.map { platformColor(for: .light, overriding: $0) }
        #if os(iOS)
            let skPalette = palette.map { SKColor(cgColor: Self.cgColor(from: $0)) }
        #else
            let skPalette = palette.compactMap { color in
                SKColor(cgColor: Self.cgColor(from: color)) ?? nil
            }
        #endif

        emitter.particleTexture = Self.makeConfettiTexture(color: UIColor.white)
        emitter.particleSize = CGSize(width: 28, height: 28)
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 1.4
        emitter.particleLifetimeRange = 0.35
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = 240
        emitter.particleSpeedRange = 160
        emitter.particleAlpha = 1
        emitter.particleAlphaRange = 0.25
        emitter.particleAlphaSpeed = -0.9
        emitter.particleScale = 0.52
        emitter.particleScaleRange = 0.26
        emitter.particleScaleSpeed = -0.38
        emitter.particleColor = skPalette.randomElement() ?? SKColor.white
        emitter.particleColorBlendFactor = 1
        emitter.particleColorSequence = nil
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = .pi * 1.6
        emitter.particlePositionRange = CGVector(dx: collisionRadius, dy: collisionRadius)
        emitter.xAcceleration = 0
        emitter.yAcceleration = -320
        emitter.fieldBitMask = 0
        emitter.particleBlendMode = .alpha
        emitter.zPosition = 8
        if let scene {
            emitter.targetNode = scene
        } else if let parent {
            emitter.targetNode = parent
        }
        emitter.name = "SchmojiConfetti"

        if skPalette.count > 1 {
            let cycleKey = "SchmojiConfettiColorCycle"
            let shuffled = skPalette.shuffled()
            var actions: [SKAction] = []
            for color in shuffled {
                actions.append(SKAction.run { [weak emitter] in
                    emitter?.particleColor = color
                })
                actions.append(SKAction.wait(forDuration: 0.005))
            }
            if shuffled.count > 1 {
                let colorCycle = SKAction.repeatForever(SKAction.sequence(actions))
                emitter.run(colorCycle, withKey: cycleKey)
                let stopCycle = SKAction.sequence([
                    SKAction.wait(forDuration: 0.4),
                    SKAction.run { [weak emitter] in
                        emitter?.removeAction(forKey: cycleKey)
                    },
                ])
                emitter.run(stopCycle)
            }
        }

        let burst = SKAction.sequence([
            SKAction.run { emitter.particleBirthRate = 120 }, // Lower birth rate
            SKAction.wait(forDuration: 0.18), // Shorter burst
            SKAction.run { emitter.particleBirthRate = 0 },
        ])
        emitter.run(burst)
        return emitter
    }
}

extension SchmojiSpriteNode {
    static func prewarmCircleTextures(for palette: [PotatoGameAppearance], colorScheme: ColorScheme) {
        let byColor = Dictionary(uniqueKeysWithValues: palette.map { ($0.color, $0) })
        for (color, appearance) in byColor {
            let hexcode = appearance.hexcode
            let targetDiameter = color.size
            let faceTexture = PotatoGameArt.texture(forHexcode: hexcode, targetDiameter: targetDiameter)
            let metrics = GeometryMetrics.make(for: faceTexture, targetDiameter: targetDiameter)
            let baseColor = platformColor(for: colorScheme, color: color)
            _ = circleTexture(for: color, radius: metrics.visualRadius, baseColor: baseColor)
        }
    }

    func platformColor(for scheme: ColorScheme? = nil, overriding overrideColor: PotatoColor? = nil) -> UIColor {
        let resolved = overrideColor ?? schmojiColor
        return Self.platformColor(for: scheme, color: resolved)
    }

    static func platformColor(for scheme: ColorScheme? = nil, color: PotatoColor) -> UIColor {
        let base = UIColor(color.color)
        #if os(iOS)
            guard let scheme else { return base }
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            return base.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        #elseif os(macOS)
            guard let scheme else { return base }
            if #available(macOS 10.14, *),
               let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            {
                return base.resolved(using: appearance)
            }
            return base
        #else
            return base
        #endif
    }
}

// MARK: - SKAction Convenience

extension SKAction {
    func easeInEaseOut() -> SKAction {
        timingMode = .easeInEaseOut
        return self
    }

    func easeOut() -> SKAction {
        timingMode = .easeOut
        return self
    }
}
