// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import CoreMotion
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import Foundation
import GameController
import GameplayKit
import SpriteKit
import SwiftUI

/// Live SpriteKit scene that handles physics, input, and match interactions.
@MainActor
final class PotatoGameScene: SKScene {
    #if os(iOS)
        static let preferredFramesPerSecond: Int = {
            let fps = UIScreen.main.maximumFramesPerSecond
            return fps > 0 ? fps : 60
        }()

    #elseif os(macOS)
        static let preferredFramesPerSecond: Int = {
            let fps = NSScreen.main?.maximumFramesPerSecond ?? 120
            return fps > 0 ? fps : 60
        }()
    #else
        static let preferredFramesPerSecond = 60
    #endif
    weak var sessionManager: SchmojiGameSessionManager?
    /// Immutable snapshot describing the level when this scene was created/reloaded.
    private(set) var levelPresentation: SchmojiLevelPresentation?
    #if os(iOS)
        let motionManager = CMMotionManager()
        let motionQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInteractive
            queue.name = "com.potatogame.motion"
            queue.maxConcurrentOperationCount = 1
            return queue
        }()

        let collisionFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        var lastCollisionFeedbackTime: TimeInterval = 0
        @available(iOS 14.0, *)
        var hardwareKeyboardInput: GCKeyboardInput?

        var isIPadDevice: Bool {
            UIDevice.current.userInterfaceIdiom == .pad
        }
    #endif
    var selectedSchmojiNodes: [SchmojiSpriteNode] = []
    /// Local copy of the board state so SpriteKit doesn’t reach into SwiftData models directly.
    private var storedLevelObjects: [SchmojiBoardObject] = []
    private var hasLoadedInitialLayout = false
    var colorScheme: ColorScheme = .light
    private(set) var hapticsEnabled: Bool = SchmojiOptions.haptics
    private(set) var soundEnabled: Bool = SchmojiOptions.sound
    let defaultGravity = CGVector(dx: 0, dy: -9.8)
    let matchExpansionFraction: CGFloat = 0.2
    let matchExpansionMinimum: CGFloat = 8
    let gravityMagnitude: CGFloat = 9.8
    var schmojiNodes: [SchmojiSpriteNode] = []
    var spawnAnimationIndex: Int = 0
    private var contactDelegateProxy: SKPhysicsContactDelegate?
    var lastSpawnAnimationTimestamp: TimeInterval = 0
    var keyboardSettings: GameKeyboardSettings?
    #if os(iOS) || os(macOS)
        private var soundActionCache: [SoundEffect: SKAction] = [:]
    #endif
    #if DEBUG
        private var debugMatchOverlayEnabled = false
        private var debugOverlayNodes: [ObjectIdentifier: DebugOverlay] = [:]
        private var isRenderingDebugOverlay = false
    #endif

    #if os(iOS) || os(macOS)
        enum DirectionKey: Hashable {
            case left
            case right
            case up
            case down
        }

        private enum RotationKey {
            case left
            case right
        }

        var activeKeyboardDirections: Set<DirectionKey> = []
        private var rotateLeftActive = false
        private var rotateRightActive = false
    #endif
    var hasKeyboardGravityOverride = false
    var hasControllerGravityOverride = false
    private var previousUpdateTime: TimeInterval?
    var currentMatchClusterIndex: Int = -1
    var controllerIdentifiers = Set<ObjectIdentifier>()

    init(levelPresentation: SchmojiLevelPresentation) {
        self.levelPresentation = levelPresentation
        storedLevelObjects = levelPresentation.objects
        let sceneSize = CGSize(width: SchmojiOptions.width, height: SchmojiOptions.height)
        super.init(size: sceneSize)
        scaleMode = .aspectFit
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
        // Handle decoding if needed, but usually, you can leave it empty for most SpriteKit scenes.
    }

    /// Keeps gravity/controller input in sync each frame.
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        #if DEBUG
            guard debugMatchOverlayEnabled, isRenderingDebugOverlay == false else { return }
            isRenderingDebugOverlay = true
            renderDebugMatchOverlay()
            isRenderingDebugOverlay = false
        #endif
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        view.shouldCullNonVisibleNodes = true
        view.isAsynchronous = true
        view.preferredFramesPerSecond = Self.preferredFramesPerSecond

        #if os(iOS)
            prepareCollisionFeedbackIfNeeded()
        #endif

        // Physics world setup
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        if let edgeBody = physicsBody {
            SchmojiPhysicsCategory.configure(
                edgeBody,
                category: SchmojiPhysicsCategory.edge,
                collisions: SchmojiPhysicsCategory.schmoji,
                contacts: SchmojiPhysicsCategory.schmoji
            )
        }
        contactDelegateProxy = UnownedContactDelegate(scene: self)
        physicsWorld.contactDelegate = contactDelegateProxy
        physicsWorld.gravity = defaultGravity

        loadLevelObjectsIfNeeded()

        setupBackground()
        registerControllerNotifications()
        #if os(iOS)
            if isIPadDevice {
                configureHardwareKeyboard()
            }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(handleExternalKeyboardAction(_:)), name: .gameInputActionTriggered, object: nil)

        // Gravity setup
        #if os(iOS)
            startDeviceMotion()
        #endif
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        #if os(iOS)
            stopDeviceMotion()
        #endif
        unregisterControllerNotifications()
        #if os(iOS)
            if isIPadDevice {
                teardownHardwareKeyboard()
            }
        #endif
        NotificationCenter.default.removeObserver(self, name: .gameInputActionTriggered, object: nil)
    }

    override func sceneDidLoad() {
        // Check for Game Over right away in case level is unwinable
        checkForGameEnd()
    }

    /// Hydrates SpriteKit nodes from the cached level snapshot when needed.
    private func loadLevelObjectsIfNeeded(force: Bool = false) {
        if force == false {
            guard hasLoadedInitialLayout == false else { return }
            hasLoadedInitialLayout = true
        } else {
            hasLoadedInitialLayout = true
        }

        guard let manager = sessionManager else { return }
        let levelObjects = storedLevelObjects.reversed()

        for schmojiObject in levelObjects {
            let node = manager.createNode(for: schmojiObject)
            addChild(node)
            registerSchmojiNode(node)
        }
    }

    /// Removes a Schmoji from the scene and mirrors the change to persistence.
    func removeSchmojiNode(_ node: SchmojiSpriteNode) {
        unregisterSchmojiNode(node)
        sessionManager?.removeSchmojiNode(node, from: self)
    }

    /// Resets physics/input state and rebuilds nodes for the supplied level snapshot.
    func reloadLevel(with presentation: SchmojiLevelPresentation) {
        levelPresentation = presentation
        storedLevelObjects = presentation.objects
        selectedSchmojiNodes.removeAll()
        #if os(iOS) || os(macOS)
            activeKeyboardDirections.removeAll()
            hasKeyboardGravityOverride = false
        #endif
        pruneSchmojiNodes()
        for node in schmojiNodes {
            node.removeAllActions()
            node.removeFromParent()
        }
        schmojiNodes.removeAll()
        physicsWorld.gravity = defaultGravity
        hasLoadedInitialLayout = false
        loadLevelObjectsIfNeeded(force: true)
    }

    func extractUpdatedObjects() -> [SchmojiBoardObject]? {
        // Snapshot even while paused/off-screen so persistence can run after sheets or backgrounding.

        let storedObjects = storedLevelObjects
        pruneSchmojiNodes()

        // If the scene has no active nodes yet, fall back to the stored snapshot.
        guard schmojiNodes.isEmpty == false else {
            #if DEBUG
                print("📦 Extracted \(storedObjects.count) total objects for persistence (scene has no nodes).")
            #endif
            return storedObjects
        }

        var nodeLookup: [UUID: SchmojiSpriteNode] = [:]
        nodeLookup.reserveCapacity(schmojiNodes.count)
        for node in schmojiNodes {
            nodeLookup[node.schmojiObject.id] = node
        }

        var updatedObjects: [SchmojiBoardObject] = []
        updatedObjects.reserveCapacity(max(storedObjects.count, schmojiNodes.count))
        var matchedCount = 0

        for object in storedObjects {
            guard let node = nodeLookup.removeValue(forKey: object.id) else { continue }
            matchedCount += 1
            node.schmojiObject.positionX = Double(node.position.x)
            node.schmojiObject.positionY = Double(node.position.y)
            updatedObjects.append(node.schmojiObject)
        }

        let addedCount = nodeLookup.count
        if addedCount > 0 {
            for node in nodeLookup.values {
                node.schmojiObject.positionX = Double(node.position.x)
                node.schmojiObject.positionY = Double(node.position.y)
                updatedObjects.append(node.schmojiObject)
            }
        }

        let filteredCount = max(0, storedObjects.count - matchedCount)

        // Cache the snapshot locally so future saves can run even if the view pauses/offloads.
        storedLevelObjects = updatedObjects
        syncPresentationObjects()

        #if DEBUG
            if filteredCount > 0 || addedCount > 0 {
                print("📦 Extracted \(updatedObjects.count) objects for persistence (filtered \(filteredCount), added \(addedCount)).")
            } else {
                print("📦 Extracted \(updatedObjects.count) total objects for persistence.")
            }
        #endif
        return updatedObjects
    }

    // MARK: - Game Logic

    /// Asks the session manager to see if the board is in a terminal state.
    func checkForGameEnd() {
        sessionManager?.evaluateGameEnd(in: self)
    }

    /// Called by SwiftUI toggles to flip the per-scene haptics flag.
    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        #if os(iOS)
            prepareCollisionFeedbackIfNeeded()
        #endif
    }

    /// Called by SwiftUI toggles to flip the per-scene sound flag.
    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
    }

    // MARK: - Node Registry

    /// Runs a closure over every active Schmoji node, pruning dead references first.
    func forEachSchmojiNode(_ body: (SchmojiSpriteNode) -> Void) {
        pruneSchmojiNodes()
        for node in schmojiNodes {
            body(node)
        }
    }

    /// Updates node textures/colors when the palette changes.
    func applyPalette(_ palette: [SchmojiAppearance]) {
        SchmojiSpriteNode.prewarmCircleTextures(for: palette, colorScheme: colorScheme)
        let lookup = Dictionary(uniqueKeysWithValues: palette.map { ($0.color, $0) })
        forEachSchmojiNode { node in
            guard let appearance = lookup[node.schmojiColor] else { return }
            node.updateAppearance(appearance)
        }
    }

    /// Mirror deletions originating from gameplay so our cached snapshot stays aligned with persistence.
    func applyStoredObjectRemoval(withId id: UUID) {
        storedLevelObjects.removeAll { $0.id == id }
        syncPresentationObjects()
    }

    /// Track objects spawned from match evolutions before persistence round-trips.
    func appendStoredObject(_ object: SchmojiBoardObject) {
        storedLevelObjects.append(object)
        syncPresentationObjects()
    }

    /// Used when the session manager injects a brand-new layout snapshot.
    func replaceStoredObjects(_ objects: [SchmojiBoardObject]) {
        storedLevelObjects = objects
        syncPresentationObjects()
    }

    private func syncPresentationObjects() {
        guard var presentation = levelPresentation else { return }
        presentation.objects = storedLevelObjects
        levelPresentation = presentation
    }

    /// Tracks a newly-added node so we can find it later for matches or persistence.
    func registerSchmojiNode(_ node: SchmojiSpriteNode) {
        pruneSchmojiNodes()
        if schmojiNodes.contains(where: { $0 === node }) == false {
            schmojiNodes.append(node)
        }
    }

    private func unregisterSchmojiNode(_ node: SchmojiSpriteNode) {
        schmojiNodes.removeAll { $0 === node }
    }

    /// Drops nodes that have left the scene graph to keep `schmojiNodes` lean.
    func pruneSchmojiNodes() {
        schmojiNodes.removeAll { $0.parent == nil }
    }

    /// Toggle rendering of match radius overlays for debugging.
    func setDebugMatchOverlay(enabled: Bool) {
        #if DEBUG
            debugMatchOverlayEnabled = enabled
            if enabled == false {
                removeDebugOverlay()
            }
        #endif
    }

    #if DEBUG
        private func renderDebugMatchOverlay() {
            pruneSchmojiNodes()
            var activeIdentifiers = Set<ObjectIdentifier>()

            for node in schmojiNodes {
                let identifier = ObjectIdentifier(node)
                activeIdentifiers.insert(identifier)
                let overlays = debugOverlayNodes[identifier] ?? createDebugOverlay()

                let outerRadius = rawRadius(for: node)
                let innerRadius = matchRadius(for: node)
                overlays.outer.path = CGPath(ellipseIn: circleRect(center: node.position, radius: outerRadius), transform: nil)
                overlays.inner.path = CGPath(ellipseIn: circleRect(center: node.position, radius: innerRadius), transform: nil)

                if overlays.outer.parent == nil {
                    addChild(overlays.outer)
                }
                if overlays.inner.parent == nil {
                    addChild(overlays.inner)
                }

                debugOverlayNodes[identifier] = overlays
            }

            for (identifier, overlays) in debugOverlayNodes where activeIdentifiers.contains(identifier) == false {
                overlays.outer.removeFromParent()
                overlays.inner.removeFromParent()
                debugOverlayNodes.removeValue(forKey: identifier)
            }
        }

        private func removeDebugOverlay() {
            for overlays in debugOverlayNodes.values {
                overlays.outer.removeFromParent()
                overlays.inner.removeFromParent()
            }
            debugOverlayNodes.removeAll()
        }

        private func createDebugOverlay() -> DebugOverlay {
            let outer = SKShapeNode()
            outer.strokeColor = .systemRed
            outer.lineWidth = 1.0
            outer.zPosition = 10000
            outer.fillColor = SKColor.clear
            outer.isAntialiased = false

            let inner = SKShapeNode()
            inner.strokeColor = .systemGreen
            inner.lineWidth = 1.0
            inner.zPosition = 10000
            inner.fillColor = SKColor.clear
            inner.isAntialiased = false

            return DebugOverlay(outer: outer, inner: inner)
        }

        private struct DebugOverlay {
            let outer: SKShapeNode
            let inner: SKShapeNode
        }
    #endif

    // MARK: - Background Setup

    private func setupBackground() {
        // Build a fully opaque diagonal gradient background once per call and apply as a single texture.
        // Keep the scene opaque for maximum SpriteKit performance.
        let sceneSize = size
        guard sceneSize.width > 0, sceneSize.height > 0 else { return }

        // Resolve SwiftUI colors to platform colors just once.
        let levelTintSwiftUI = levelPresentation?.backgroundColor.color ?? Color("PotatoSecondaryBackground")
        #if os(iOS)
            let systemBGSwiftUI = Color.appBackground
            let topPlatformColor = UIColor(levelTintSwiftUI)
            let bottomPlatformColor = UIColor(systemBGSwiftUI)
        #else
            let systemBGSwiftUI = Color.appBackground
            let topPlatformColor = NSColor(levelTintSwiftUI)
            let bottomPlatformColor = NSColor(systemBGSwiftUI)
        #endif

        // Compute blended top/bottom colors in Device RGB to avoid repeated conversions.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        func deviceRGBA(_ color: CGColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            let converted = color.converted(to: colorSpace, intent: .defaultIntent, options: nil) ?? color
            let comps = converted.components ?? [1, 1, 1, 1]
            let r = comps.count > 0 ? comps[0] : 1
            let g = comps.count > 1 ? comps[1] : 1
            let b = comps.count > 2 ? comps[2] : 1
            let a = comps.count > 3 ? comps[3] : 1
            return (r, g, b, a)
        }
        func blend(_ fg: CGColor, over bg: CGColor, factor: CGFloat) -> CGColor {
            let f = deviceRGBA(fg)
            let b = deviceRGBA(bg)
            let r = f.r * factor + b.r * (1 - factor)
            let g = f.g * factor + b.g * (1 - factor)
            let bl = f.b * factor + b.b * (1 - factor)
            return CGColor(colorSpace: colorSpace, components: [r, g, bl, 1.0])!
        }

        let darkTopAlpha: CGFloat = 0.9
        let lightTopAlpha: CGFloat = 0.7
        let topBlend = (colorScheme == .dark) ? darkTopAlpha : lightTopAlpha
        let darkBottomAlpha: CGFloat = 0.9
        let lightBottomAlpha: CGFloat = 0.7
        let bottomBlend = (colorScheme == .dark) ? darkBottomAlpha : lightBottomAlpha

        let topBase = topPlatformColor.withAlphaComponent(1.0).cgColor
        let bottomBase = bottomPlatformColor.withAlphaComponent(1.0).cgColor
        let topCGColor = blend(topBase, over: bottomBase, factor: topBlend)
        let bottomCGColor = blend(bottomBase, over: topBase, factor: bottomBlend)

        // Build gradient once.
        let locations: [CGFloat] = [0.0, 1.0]
        let colors = [topCGColor, bottomCGColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
            return
        }

        // Render into a platform bitmap once, avoiding intermediate image representations when possible.
        #if os(iOS)
            let scale = UIScreen.main.scale
            let pixelSize = CGSize(width: sceneSize.width, height: sceneSize.height)
            let rendererFormat = UIGraphicsImageRendererFormat.default()
            rendererFormat.opaque = true
            rendererFormat.scale = scale
            let renderer = UIGraphicsImageRenderer(size: pixelSize, format: rendererFormat)
            let image = renderer.image { ctx in
                let ctxRef = ctx.cgContext
                let rect = CGRect(origin: .zero, size: pixelSize)
                // Fill with top color as a cheap background, then draw gradient.
                ctxRef.setFillColor(topCGColor)
                ctxRef.fill(rect)
                // Diagonal: visual top-left -> bottom-right in SpriteKit.
                let start = CGPoint(x: 0, y: pixelSize.height)
                let end = CGPoint(x: pixelSize.width, y: 0)
                ctxRef.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
            let texture = SKTexture(image: image)
        #else
            // macOS: Use a single Core Graphics bitmap context.
            let width = max(1, Int(sceneSize.width.rounded()))
            let height = max(1, Int(sceneSize.height.rounded()))
            let bitsPerComponent = 8
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            guard let ctxRef = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                // Fallback: simple solid fill.
                let fallback = NSImage(size: sceneSize)
                fallback.lockFocus()
                NSColor(cgColor: topCGColor)?.setFill()
                NSBezierPath(rect: CGRect(origin: .zero, size: sceneSize)).fill()
                fallback.unlockFocus()
                let texture = SKTexture(image: fallback)
                texture.filteringMode = .nearest
                if let old = childNode(withName: "backgroundGradient") { old.removeFromParent() }
                let node = SKSpriteNode(texture: texture)
                node.size = sceneSize
                node.zPosition = -10
                node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                node.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
                node.name = "backgroundGradient"
                addChild(node)
                return
            }
            // Fill and gradient
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            ctxRef.setFillColor(topCGColor)
            ctxRef.fill(rect)
            let start = CGPoint(x: 0, y: CGFloat(height))
            let end = CGPoint(x: CGFloat(width), y: 0)
            ctxRef.drawLinearGradient(gradient, start: start, end: end, options: [])
            guard let cgImage = ctxRef.makeImage() else {
                let fallback = NSImage(size: sceneSize)
                fallback.lockFocus()
                NSColor(cgColor: topCGColor)?.setFill()
                NSBezierPath(rect: CGRect(origin: .zero, size: sceneSize)).fill()
                fallback.unlockFocus()
                let texture = SKTexture(image: fallback)
                texture.filteringMode = .nearest
                if let old = childNode(withName: "backgroundGradient") { old.removeFromParent() }
                let node = SKSpriteNode(texture: texture)
                node.size = sceneSize
                node.zPosition = -10
                node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                node.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
                node.name = "backgroundGradient"
                addChild(node)
                return
            }
            let image = NSImage(size: sceneSize)
            image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
            let texture = SKTexture(image: image)
        #endif

        // Apply texture to a single background node, replacing any prior one.
        texture.filteringMode = .nearest
        if let old = childNode(withName: "backgroundGradient") { old.removeFromParent() }
        let node = SKSpriteNode(texture: texture)
        node.size = sceneSize
        node.zPosition = -10
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        node.name = "backgroundGradient"
        addChild(node)
    }

    func setColorScheme(_ scheme: ColorScheme) {
        guard colorScheme != scheme else { return }
        colorScheme = scheme
        setupBackground()
        SchmojiSpriteNode.invalidateCircleTextureCache()
        forEachSchmojiNode { node in
            node.refreshCircleAppearance(for: scheme)
        }
    }

    #if os(iOS) || os(macOS)
        func playSound(_ effect: SoundEffect) {
            guard soundEnabled, let fileName = effect.fileName else { return }
            if let cached = soundActionCache[effect] {
                run(cached)
                return
            }
            let action = SKAction.playSoundFileNamed(fileName, waitForCompletion: false)
            soundActionCache[effect] = action
            run(action)
        }
    #else
        private func playSound(_: SoundEffect) {}
    #endif

    enum SoundEffect: Hashable {
        case matchReady
        case matchSuccess
        case matchFail
        case potatoCreated
        case win
        case perfectWin
        case loss

        var fileName: String? {
            switch self {
            case .matchReady:
                "mixkit-dry-pop-up-notification-alert-2356"
            case .matchSuccess:
                "mixkit-explainer-video-pops-whoosh-light-pop-3005"
            case .matchFail:
                "mixkit-click-error-1110"
            case .potatoCreated:
                "mixkit-winning-notification-2018"
            case .win:
                "mixkit-completion-of-a-level-2063"
            case .perfectWin:
                "mixkit-bonus-extra-in-a-video-game-2064"
            case .loss:
                "mixkit-player-losing-or-failing-2042"
            }
        }
    }
}
