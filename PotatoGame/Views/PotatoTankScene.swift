// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

@preconcurrency import SpriteKit

#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

class PotatoTankScene: SKScene {
    private enum NodeName {
        static let background = "backgroundGradient"
        static let potato = "potato"
    }

    private var lastBackgroundSize: CGSize = .zero
    #if os(iOS) || os(tvOS) || os(visionOS)
        private var lastInterfaceStyle: UIUserInterfaceStyle = .unspecified
    #elseif os(macOS)
        private var lastAppearanceName: NSAppearance.Name?
    #endif
    private weak var backgroundNode: SKSpriteNode?
    private var hasSpawnedPotatoes = false
    private var isSpawningPotatoes = false
    private var potatoTexture: SKTexture?

    private var potatoScaleRange: ClosedRange<CGFloat> = 1 ... 2
    private let driftDurationRange: ClosedRange<TimeInterval> = 12.0 ... 22.0
    private let driftPauseRange: ClosedRange<TimeInterval> = 1.5 ... 3.0
    private let rotationRange: ClosedRange<CGFloat> = -.pi ... .pi
    private var potatoSpawnRange: ClosedRange<Int> = 14 ... 28

    override func didMove(to _: SKView) {
        backgroundColor = .black
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        updateBounds(to: size)
        setupBackground()

        spawnPotatoesIfNeeded()
    }

    func updateBounds(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        self.size = size
        updateBackground(to: size)

        let frameRect = CGRect(
            origin: CGPoint(x: -size.width / 2, y: -size.height / 2),
            size: size
        )

        physicsBody = SKPhysicsBody(edgeLoopFrom: frameRect)
        physicsBody?.isDynamic = false
        physicsBody?.categoryBitMask = 1 << 0
        physicsBody?.collisionBitMask = 1 << 0
        physicsBody?.contactTestBitMask = 0

        updateDynamics(for: size)
    }

    func refreshAppearance() {
        updateBackground(to: size, force: true)
    }

    private func updateDynamics(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let dropSize = 1.0

        for node in children {
            guard let sprite = node as? SKSpriteNode, sprite.name == NodeName.potato else { continue }

            sprite.setScale(min(max(sprite.xScale, potatoScaleRange.lowerBound), potatoScaleRange.upperBound))
            sprite.position = clamp(position: sprite.position, inset: max(dropSize / 2, sprite.frame.width / 2))

            if sprite.action(forKey: "appearance") == nil, sprite.action(forKey: "drift") == nil {
                startDrift(for: sprite)
            }
        }
    }

    private func startDrift(for potato: SKSpriteNode) {
        potato.removeAction(forKey: "drift")

        let duration = TimeInterval.random(in: driftDurationRange)
        let pause = TimeInterval.random(in: driftPauseRange)
        let targetScale = CGFloat.random(in: potatoScaleRange)
        let targetPosition = randomDriftTarget(from: potato.position, inset: potato.frame.width / 2)
        let rotation = SKAction.rotate(byAngle: CGFloat.random(in: rotationRange), duration: duration)
        rotation.timingMode = .easeInEaseOut

        let move = SKAction.move(to: targetPosition, duration: duration)
        move.timingMode = .easeInEaseOut

        let scale = SKAction.scale(to: targetScale, duration: duration)
        scale.timingMode = .easeInEaseOut

        let driftGroup = SKAction.group([move, scale, rotation])
        let sequence = SKAction.sequence([
            driftGroup,
            SKAction.wait(forDuration: pause),
            SKAction.run { [weak self, weak potato] in
                guard let self, let potato else { return }
                startDrift(for: potato)
            },
        ])

        potato.run(sequence, withKey: "drift")
    }

    private func randomDriftTarget(from position: CGPoint, inset: CGFloat) -> CGPoint {
        let radius = min(size.width, size.height) / 4
        var candidate = CGPoint(
            x: position.x + CGFloat.random(in: -radius ... radius),
            y: position.y + CGFloat.random(in: -radius ... radius)
        )

        candidate = clamp(position: candidate, inset: inset)
        return candidate
    }

    private func clamp(position: CGPoint, inset: CGFloat) -> CGPoint {
        let halfWidth = size.width / 2 - inset
        let halfHeight = size.height / 2 - inset

        guard halfWidth > 0, halfHeight > 0 else { return position }

        let x = min(max(position.x, -halfWidth), halfWidth)
        let y = min(max(position.y, -halfHeight), halfHeight)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Potatoes

    private func spawnPotatoesIfNeeded() {
        guard !hasSpawnedPotatoes, !isSpawningPotatoes else { return }
        let texture = potatoTexture ?? makePotatoTexture()
        guard let texture else { return }

        potatoTexture = texture
        isSpawningPotatoes = true
        texture.preload { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      let potatoTexture else { return }
                hasSpawnedPotatoes = true
                isSpawningPotatoes = false
                spawnPotatoes(with: potatoTexture)
            }
        }
    }

    private func spawnPotatoes(with texture: SKTexture) {
        let count = Int.random(in: potatoSpawnRange)
        let baseSize = CGFloat(PotatoGameOptions.baseSizePotatoTank)
        let spawnAction = SKAction.sequence([
            SKAction.run { [weak self] in
                guard let self else { return }
                let targetScale = CGFloat.random(in: potatoScaleRange)
                let potato = SKSpriteNode(texture: texture, size: CGSize(width: baseSize, height: baseSize))
                potato.name = NodeName.potato

                potato.position = CGPoint(
                    x: CGFloat.random(in: -size.width / 2 ... size.width / 2),
                    y: CGFloat.random(in: -size.height / 2 ... size.height / 2)
                )

                potato.zRotation = CGFloat.random(in: rotationRange)

                addChild(potato)

                potato.alpha = 0
                potato.setScale(0.2)

                let fadeIn = SKAction.fadeAlpha(to: 0.5, duration: 4.0)
                let scaleIn = SKAction.scale(to: targetScale, duration: 5.0)
                let appearSequence = SKAction.sequence([
                    SKAction.group([fadeIn, scaleIn]),
                    SKAction.run { [weak self, weak potato] in
                        guard let self, let potato else { return }
                        startDrift(for: potato)
                    },
                ])
                potato.run(appearSequence, withKey: "appearance")
            },
            SKAction.wait(forDuration: 0.1),
        ])

        run(SKAction.repeat(spawnAction, count: count), withKey: "initialPotatoSpawn")
    }

    private func makePotatoTexture() -> SKTexture? {
        // Render large enough for the maximum runtime scale so SVG detail stays sharp.
        let targetDiameter = CGFloat(PotatoGameOptions.baseSizePotatoTank) * potatoScaleRange.upperBound
        return PotatoGameArt.texture(
            forHexcode: PotatoGameOptions.potatoHex,
            targetDiameter: targetDiameter
        )
    }

    // MARK: - Background

    private func setupBackground() {
        // Create once; texture will be (re)generated for current size
        if backgroundNode == nil {
            let node = SKSpriteNode()
            node.zPosition = -10
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = CGPoint(x: 0, y: 0)
            node.name = NodeName.background
            addChild(node)
            backgroundNode = node
        }
        updateBackground(to: size)
    }

    private func updateBackground(to size: CGSize, force: Bool = false) {
        guard size.width > 0, size.height > 0 else { return }
        guard let node = backgroundNode ?? childNode(withName: NodeName.background) as? SKSpriteNode else { return }

        #if os(iOS) || os(tvOS) || os(visionOS)
            let traitCollection = view?.traitCollection ?? UITraitCollection(userInterfaceStyle: .unspecified)
            let interfaceStyle = traitCollection.userInterfaceStyle

            if force == false,
               size == lastBackgroundSize,
               interfaceStyle == lastInterfaceStyle
            {
                return
            }

            let baseTopColor = UIColor(named: "PotatoBackground") ?? .systemBackground
            let baseBottomColor = UIColor(named: "PotatoSecondaryBackground") ?? .secondarySystemBackground
            let topColor = baseTopColor.resolvedColor(with: traitCollection)
            let bottomColor = baseBottomColor.resolvedColor(with: traitCollection)
            let screenScale: CGFloat = if let resolvedScale = view?.window?.screen.scale {
                resolvedScale
            } else {
                UIScreen.main.scale
            }

            let texture = makeLinearGradientTexture(size: size, top: topColor, bottom: bottomColor, scale: screenScale)
            texture.filteringMode = SKTextureFilteringMode.linear
            node.texture = texture
            lastInterfaceStyle = interfaceStyle
        #elseif os(macOS)
            let windowAppearance = view?.window?.effectiveAppearance
            let appAppearance = NSApp?.effectiveAppearance
            let appearance: NSAppearance = (windowAppearance ?? appAppearance) ?? NSAppearance.currentDrawing()
            let appearanceName: NSAppearance.Name = appearance.name

            if force == false,
               size == lastBackgroundSize,
               lastAppearanceName == appearanceName
            {
                return
            }

            let baseTopColor = NSColor(named: "PotatoBackground") ?? .windowBackgroundColor
            let baseBottomColor = NSColor(named: "PotatoSecondaryBackground") ?? .underPageBackgroundColor
            let texture = makeLinearGradientTexture(size: size, top: baseTopColor, bottom: baseBottomColor, scale: view?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0, appearance: appearance)
            texture.filteringMode = SKTextureFilteringMode.linear
            node.texture = texture
            lastAppearanceName = appearanceName
        #endif

        node.size = size
        node.position = CGPoint(x: 0, y: 0)
        lastBackgroundSize = size
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
        private func makeLinearGradientTexture(size: CGSize, top: UIColor, bottom: UIColor, scale: CGFloat) -> SKTexture {
            let pixelSize = CGSize(width: max(1, size.width), height: max(1, size.height))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 1.0]
            let topCG = top.withAlphaComponent(1.0).cgColor
            let bottomCG = bottom.withAlphaComponent(1.0).cgColor

            let rendererFormat = UIGraphicsImageRendererFormat.default()
            rendererFormat.opaque = true
            rendererFormat.scale = scale
            let renderer = UIGraphicsImageRenderer(size: pixelSize, format: rendererFormat)
            let image = renderer.image { ctx in
                let ctxRef = ctx.cgContext
                let rect = CGRect(origin: .zero, size: pixelSize)
                ctxRef.setFillColor(topCG)
                ctxRef.fill(rect)
                if let gradient = CGGradient(colorsSpace: colorSpace, colors: [topCG, bottomCG] as CFArray, locations: locations) {
                    let start = CGPoint(x: 0, y: pixelSize.height)
                    let end = CGPoint(x: 0, y: 0)
                    ctxRef.drawLinearGradient(gradient, start: start, end: end, options: [])
                }
            }
            return SKTexture(image: image)
        }

    #elseif os(macOS)
        private func makeLinearGradientTexture(size: CGSize, top: NSColor, bottom: NSColor, scale _: CGFloat, appearance: NSAppearance) -> SKTexture {
            let pixelSize = CGSize(width: max(1, size.width), height: max(1, size.height))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 1.0]

            func drawImage() -> NSImage {
                let img = NSImage(size: pixelSize)
                img.lockFocus()
                if let ctxRef = NSGraphicsContext.current?.cgContext {
                    ctxRef.setShouldAntialias(true)
                    let rect = CGRect(origin: .zero, size: pixelSize)
                    let topCG = top.withAlphaComponent(1.0).cgColor
                    let bottomCG = bottom.withAlphaComponent(1.0).cgColor
                    ctxRef.setFillColor(topCG)
                    ctxRef.fill(rect)
                    if let gradient = CGGradient(colorsSpace: colorSpace, colors: [topCG, bottomCG] as CFArray, locations: locations) {
                        let start = CGPoint(x: 0, y: pixelSize.height)
                        let end = CGPoint(x: 0, y: 0)
                        ctxRef.drawLinearGradient(gradient, start: start, end: end, options: [])
                    }
                }
                img.unlockFocus()
                return img
            }

            let image: NSImage
            var produced: NSImage?
            appearance.performAsCurrentDrawingAppearance {
                produced = drawImage()
            }
            image = produced ?? drawImage()

            return SKTexture(image: image)
        }
    #endif
}
