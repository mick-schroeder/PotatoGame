// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

struct LevelGrid: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(LevelPackStore.self) private var levelPackStore
    @State private var hidesCompletedLevels: Bool = true
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query(sort: [SortDescriptor(\PotatoGameLevelProgress.levelNumber, order: .forward)]) private var progress: [PotatoGameLevelProgress]
    private let maxTileWidth: CGFloat = 190

    private var ownedLevelPackIDs: Set<String> {
        if let account = accounts.first {
            return account.ownedLevelPackIDs
        }
        return levelPackStore.purchasedPackIDs
    }

    private var effectiveLevels: [PotatoGameLevelInfo] {
        PotatoGameLevelInfo.allLevels(progress: progress, ownedLevelPackIDs: ownedLevelPackIDs)
    }

    private var allLevels: [PotatoGameLevelInfo] {
        effectiveLevels
    }

    private var displayLevels: [PotatoGameLevelInfo] {
        hidesCompletedLevels ? allLevels.filter { $0.isCompleted == false } : allLevels
    }

    private var nextLevelCandidate: PotatoGameLevelInfo? {
        allLevels.first(where: { $0.isCompleted == false }) ?? allLevels.first
    }

    private var nextPlayableLevel: PotatoGameLevelInfo? {
        PotatoGameLevelInfo.nextPlayableLevel(in: allLevels)
    }

    var body: some View {
        content()
    }
}

private extension LevelGrid {
    @ViewBuilder
    func content() -> some View {
        if let nextLevel = nextLevelCandidate {
            LevelGridContentView(
                allLevels: allLevels,
                displayLevels: displayLevels,
                nextLevel: nextLevel,
                playLevel: nextPlayableLevel,
                gridColumns: gridColumns,
                gridSpacing: gridSpacing,
                hidesCompletedLevels: $hidesCompletedLevels
            )
            .environment(levelPackStore)
        } else {
            EmptyView()
        }
    }
}

private struct LevelGridContentView: View {
    @Environment(LevelPackStore.self) private var levelPackStore
    let allLevels: [PotatoGameLevelInfo]
    let displayLevels: [PotatoGameLevelInfo]
    let nextLevel: PotatoGameLevelInfo
    let playLevel: PotatoGameLevelInfo?
    let gridColumns: [GridItem]
    let gridSpacing: CGFloat
    @Binding var hidesCompletedLevels: Bool

    private var targetPlayLevel: PotatoGameLevelInfo { playLevel ?? nextLevel }

    private var completedLevelCount: Int {
        allLevels.filter(\.isCompleted).count
    }

    private var playIsLocked: Bool {
        targetPlayLevel.isLevelPackLocked
    }

    private var shouldShowUnlockButton: Bool {
        displayLevels.contains { $0.isLevelPackLocked }
    }

    private var purchaseErrorBinding: Binding<Bool> {
        Binding(
            get: { levelPackStore.purchaseError != nil },
            set: { newValue in
                if newValue == false {
                    levelPackStore.purchaseError = nil
                }
            }
        )
    }

    var body: some View {
        gridView
            .potatoBackground()
            .toolbar { toolbarContent() }
            .navigationTitle(Text(.navigationLevels))
            .alert(
                Text(LocalizedStringResource("levels.level-pack.error.title", defaultValue: "Level Pack Error")),
                isPresented: purchaseErrorBinding,
                presenting: levelPackStore.purchaseError
            ) { _ in
                Button(role: .cancel) {
                    levelPackStore.purchaseError = nil
                } label: {
                    Text(.buttonOk)
                }
            } message: { error in
                Text(error.localizedDescription)
            }
    }

    private var gridView: some View {
        ScrollView {
            LevelsSummaryView(
                completedLevels: completedLevelCount,
                totalLevels: allLevels.count,
                nextLevel: nextLevel,
                playLevel: targetPlayLevel,
                playIsLocked: playIsLocked,
                shouldShowUnlockButton: shouldShowUnlockButton
            )
            .frame(maxWidth: CGFloat(PotatoGameOptions.width))
            .padding()

            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                LevelsSearchResults(levels: displayLevels)
            }
            .frame(maxWidth: CGFloat(PotatoGameOptions.width))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            filterMenu
        }
    }

    private var filterMenu: some View {
        Menu {
            Button {
                hidesCompletedLevels.toggle()
            } label: {
                let toggleTitle: LocalizedStringResource = hidesCompletedLevels
                    ? .levelsFilterShowCompleted
                    : .levelsFilterHideCompleted
                let iconName = hidesCompletedLevels ? "eye" : "eye.slash"
                Label {
                    Text(toggleTitle)
                } icon: {
                    Image(systemName: iconName)
                }
            }
        } label: {
            Image(
                systemName: hidesCompletedLevels
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .accessibilityLabel(Text(.accessibilityLevelsFilter))
        }
    }
}

private extension LevelGrid {
    var isCompactWidth: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: tileMinimumWidth, maximum: maxTileWidth), spacing: gridSpacing, alignment: .top)]
    }

    var tileMinimumWidth: CGFloat {
        isCompactWidth ? 100 : 120
    }

    var gridSpacing: CGFloat {
        isCompactWidth ? 16 : 20
    }

    var horizontalPadding: CGFloat {
        #if os(iOS)
            return isCompactWidth ? 0 : 20
        #elseif os(macOS)
            return 24
        #else
            return 18
        #endif
    }

    var indicatorInset: CGFloat {
        isCompactWidth ? 8 : 0
    }
}

#Preview("Level Grid") {
    NavigationStack {
        LevelGrid()
    }
    .environment(PreviewSampleData.makeLevelPackStore())
    .modelContainer(PreviewSampleData.makeContainer())
}
