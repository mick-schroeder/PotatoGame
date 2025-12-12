// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

struct NavigationTile: View {
    let title: LocalizedStringResource
    let icon: String
    let detail: String?
    let destination: AppScreen
    @Environment(\.router) private var router
    @AppStorage("haptics") private var hapticsEnabled: Bool = PotatoGameOptions.haptics

    var body: some View {
        Button {
            HapticsCoordinator.impact(.medium, enabled: hapticsEnabled)
            router.navigate(to: destination)
        } label: {
            HStack(spacing: 6) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.headline)

                Spacer()

                if let detail {
                    HStack(spacing: 4) {
                        Text(detail)
                        Image(systemName: "chevron.right")
                    }
                    .font(.callout)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}

struct LinksView: View {
    @Environment(LevelPackStore.self) private var levelPackStore
    @Query(sort: [SortDescriptor(\PotatoGameLevelProgress.levelNumber, order: .forward)]) private var levelProgress: [PotatoGameLevelProgress]
    @Query private var selections: [EmojiSelection]

    var body: some View {
        let viewModel = LinksViewModel(
            levelProgress: levelProgress,
            selections: selections,
            purchasedPackIDs: levelPackStore.purchasedPackIDs
        )

        VStack(alignment: .leading, spacing: 16) {
            ForEach(viewModel.tiles) { tile in
                NavigationTile(
                    title: tile.title,
                    icon: tile.iconName,
                    detail: tile.detail,
                    destination: tile.destination
                )
            }
        }
    }
}

#Preview("Navigation Tile") {
    NavigationStack {
        NavigationTile(
            title: LocalizedStringResource.linksLevels,
            icon: "circle.hexagongrid.fill",
            detail: "42 / 99",
            destination: .levels
        )
        .padding()
    }
}

#Preview("Links View") {
    NavigationStack {
        LinksView()
            .padding()
    }
    .modelContainer(PreviewSampleData.makeContainer())
    .environment(PreviewSampleData.makeLevelPackStore())
}

private struct LinksViewModel {
    struct Tile: Identifiable {
        let destination: AppScreen
        let title: LocalizedStringResource
        let iconName: String
        let detail: String?

        var id: AppScreen { destination }
    }

    let tiles: [Tile]

    init(
        levelProgress: [PotatoGameLevelProgress],
        selections: [EmojiSelection],
        purchasedPackIDs: Set<String>,
        availablePacks: Int = LevelPackRegistry.availablePacks.count,
        totalLevels: Int = LevelTemplates.count
    ) {
        let levelDetail = Self.makeLevelDetail(
            levelProgress: levelProgress,
            totalLevels: totalLevels
        )
        let storeDetail = Self.makeStoreDetail(
            purchasedPackIDs: purchasedPackIDs,
            availablePackCount: availablePacks
        )
        let collectionDetail = Self.makeCollectionDetail(selections: selections)

        tiles = [
            .init(
                destination: .levels,
                title: LocalizedStringResource.linksLevels,
                iconName: "circle.hexagongrid.fill",
                detail: levelDetail
            ),
            .init(
                destination: .store,
                title: LocalizedStringResource.linksLevelStore,
                iconName: "cart.badge.plus",
                detail: storeDetail
            ),
            .init(
                destination: .collection,
                title: LocalizedStringResource.linksCollection,
                iconName: "face.smiling",
                detail: collectionDetail
            ),
            .init(
                destination: .howto,
                title: LocalizedStringResource.linksHowToPlay,
                iconName: "questionmark.circle",
                detail: nil
            ),
        ]
    }
}

private extension LinksViewModel {
    static func makeLevelDetail(levelProgress: [PotatoGameLevelProgress], totalLevels: Int) -> String? {
        guard totalLevels > 0 else { return nil }
        let completed = levelProgress.filter { $0.gameState == .win || $0.gameState == .winPerfect }.count
        return progressDetail(completed: completed, total: totalLevels)
    }

    static func makeStoreDetail(purchasedPackIDs: Set<String>, availablePackCount: Int) -> String? {
        guard availablePackCount > 0 else { return nil }
        return progressDetail(completed: purchasedPackIDs.count, total: availablePackCount)
    }

    static func makeCollectionDetail(selections: [EmojiSelection]) -> String? {
        let total = PotatoColor.allCases.reduce(0) { partial, color in
            partial + color.schmojis.count
        }
        guard total > 0 else { return nil }

        let unlocked = PotatoColor.allCases.reduce(0) { partial, color in
            let selection = selections.first { $0.color == color }
            let unlockedHexes = selection?.unlockedHexes ?? color.schmojis
            return partial + unlockedHexes.count
        }

        return progressDetail(completed: unlocked, total: total)
    }

    static func progressDetail(completed: Int, total: Int) -> String {
        String(localized: "metrics.progress_format", defaultValue: "\(completed) / \(total)")
    }
}
