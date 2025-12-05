// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import CoreMotion
import SpriteKit
import SwiftData
import SwiftUI

struct PotatoTankView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var scene = PotatoTankScene()
    @State private var preparedScene: PotatoTankScene? = nil
    @State private var isPaused: Bool = false
    @State private var lastSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let preparedScene {
                    SpriteView(
                        scene: preparedScene,
                        isPaused: isPaused,
                        options: []
                    )
                    .ignoresSafeArea()
                } else {
                    Color.clear.ignoresSafeArea()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                handleAppear(with: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateSceneSize(newSize)
            }
            .onChange(of: colorScheme) { _, _ in
                preparedScene?.refreshAppearance()
            }
            .onDisappear {
                handleDisappear()
            }
        }
    }

    private func handleAppear(with size: CGSize) {
        updateSceneSize(size)

        preparedScene?.refreshAppearance()

        isPaused = false
        preparedScene?.isPaused = false
    }

    private func handleDisappear() {
        isPaused = true
        preparedScene?.isPaused = true
    }

    private func updateSceneSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        if preparedScene == nil {
            scene.updateBounds(to: size)
            preparedScene = scene
            lastSize = size
            return
        } else {
            guard size != lastSize else { return }
            preparedScene?.updateBounds(to: size)
        }

        lastSize = size
    }
}

#Preview("Potato Tank Background") {
    PotatoTankView()
        .frame(height: 240)
}
