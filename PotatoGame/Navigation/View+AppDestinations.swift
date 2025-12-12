// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

extension View {
    /// Applies all navigation destinations used across the PotatoGame app.
    func potatoNavigationDestinations() -> some View {
        navigationDestination(for: AppScreen.self) { destination(for: $0) }
            .navigationDestination(for: PotatoGameLevelInfo.self) { levelDestination(for: $0) }
    }

    @ViewBuilder
    private func destination(for screen: AppScreen) -> some View {
        switch screen {
        case .levels:
            LevelGrid()
        case .collection:
            CollectionView()
        case .settings:
            SettingsView()
        case .howto:
            HowToPlayView()
        case .potatoes:
            PotatoTankView()
        case .game:
            PotatoGameView()
        case .store:
            StoreView()
        }
    }

    @ViewBuilder
    private func levelDestination(for level: PotatoGameLevelInfo) -> some View {
        PotatoGameView(level: level)
    }
}
