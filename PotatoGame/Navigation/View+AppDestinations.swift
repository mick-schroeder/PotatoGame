// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

extension View {
    /// Applies all navigation destinations used across the PotatoGame app.
    func potatoNavigationDestinations() -> some View {
        navigationDestination(for: AppScreen.self) { destination(for: $0) }
            .navigationDestination(for: SchmojiLevelInfo.self) { levelDestination(for: $0) }
    }

    @ViewBuilder
    private func destination(for screen: AppScreen) -> some View {
        switch screen {
        case .levels:
            LevelGrid()
        case .collection:
            SchmojiCollectionView()
        case .settings:
            SettingsView()
        case .howto:
            HowToPlayView()
        case .potatoes:
            PotatoTankView()
        case .game:
            SchmojiGameView()
        case .store:
            StoreView()
        }
    }

    @ViewBuilder
    private func levelDestination(for level: SchmojiLevelInfo) -> some View {
        SchmojiGameView(level: level)
    }
}
