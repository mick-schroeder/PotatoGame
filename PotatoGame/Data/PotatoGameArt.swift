// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import SpriteKit
import SwiftUI

@MainActor
enum PotatoGameArt {
    private static let assetPrefix = ""
    private static var textureCache: [String: SKTexture] = [:]

    private static func normalizedHexcode(_ hexcode: String) -> String {
        let trimmed = hexcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return PotatoGameOptions.potatoHex
        }
        return trimmed
    }

    private static func assetName(for hexcode: String) -> String {
        "\(assetPrefix)\(normalizedHexcode(hexcode))"
    }

    static func texture(forHexcode hexcode: String, targetDiameter: CGFloat) -> SKTexture {
        let name = assetName(for: hexcode)
        let cacheKey = cacheKeyName(for: name, diameter: targetDiameter)

        if let cached = textureCache[cacheKey] {
            return cached
        }

        let texture = if let rendered = renderedImage(named: name, diameter: targetDiameter) {
            SKTexture(image: rendered)
        } else {
            SKTexture(imageNamed: name)
        }

        texture.usesMipmaps = true
        texture.filteringMode = .linear
        textureCache[cacheKey] = texture
        return texture
    }

    static func image(forHexcode hexcode: String, targetDiameter _: CGFloat = 160) -> Image {
        Image(assetName(for: hexcode))
    }

    static func image(for appearance: PotatoGameAppearance, targetDiameter: CGFloat = 160) -> Image {
        image(forHexcode: appearance.hexcode, targetDiameter: targetDiameter)
    }
}

// MARK: - Private helpers

private extension PotatoGameArt {
    static func cacheKeyName(for name: String, diameter: CGFloat) -> String {
        let scale = renderingScale
        let scaledSize = Int(round(max(diameter, 1) * scale))
        return "\(name)@\(scaledSize)"
    }

    static var renderingScale: CGFloat {
        #if os(iOS)
            UIScreen.main.scale
        #elseif os(macOS)
            NSScreen.main?.backingScaleFactor ?? 2
        #else
            1
        #endif
    }

    static func renderedImage(named name: String, diameter: CGFloat) -> PlatformImage? {
        let targetSize = CGSize(width: max(diameter, 1), height: max(diameter, 1))
        #if os(iOS)
            guard let image = UIImage(named: name) else { return nil }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = renderingScale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        #elseif os(macOS)
            guard let image = NSImage(named: NSImage.Name(name)) else { return nil }
            let newImage = NSImage(size: targetSize)
            newImage.lockFocus()
            defer { newImage.unlockFocus() }
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: CGRect(origin: .zero, size: targetSize),
                       from: CGRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0,
                       respectFlipped: true,
                       hints: nil)
            return newImage
        #else
            return nil
        #endif
    }
}

#if os(iOS)
    private typealias PlatformImage = UIImage
#elseif os(macOS)
    private typealias PlatformImage = NSImage
#else
    private typealias PlatformImage = AnyObject
#endif
