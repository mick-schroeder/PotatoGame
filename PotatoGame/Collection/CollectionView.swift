// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

#if canImport(AppKit)
    import AppKit
#endif

struct SchmojiCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [EmojiSelection]
    var body: some View {
        let selectionLookup = Dictionary(uniqueKeysWithValues: selections.map { ($0.color, $0) })

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                collectionSummary

                LazyVStack(spacing: 16) {
                    ForEach(displayColors) { color in
                        SchmojiCollectionColorCard(
                            color: color,
                            selection: selectionLookup[color],
                            updateSelection: { selection, hex in
                                updateSelection(selection, to: hex)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: CGFloat(PotatoGameOptions.width), alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .potatoBackground()
        .navigationTitle(Text(.navigationCollection))

        #if os(macOS)
            .contentMargins(10, for: .scrollContent)
        #else
            .contentMargins([.horizontal], 10, for: .scrollContent)
        #endif
    }

    private func updateSelection(_ selection: EmojiSelection, to hex: String) {
        guard selection.displayHexcode() != hex else { return }
        selection.selectedHex = hex
        do {
            try modelContext.save()
        } catch {
            print("Failed to save schmoji selection: \(error.localizedDescription)")
        }
    }
}

private extension SchmojiCollectionView {
    var totalAvailableSchmojis: Int {
        PotatoColor.allCases.reduce(into: 0) { count, color in
            count += color.schmojis.count
        }
    }

    var totalUnlockedSchmojis: Int {
        selections.reduce(0) { partialResult, selection in
            let unlocked = selection.unlockedHexes.filter { selection.availableHexes.contains($0) }
            return partialResult + unlocked.count
        }
    }

    var collectionSummary: some View {
        SchmojiCollectionSummaryCard(
            unlocked: totalUnlockedSchmojis,
            total: totalAvailableSchmojis
        )
    }

    var displayColors: [PotatoColor] {
        if let hidden = PotatoGameOptions.lastColor {
            return PotatoColor.allCases.filter { $0 != hidden }
        }
        return PotatoColor.allCases
    }
}

#Preview("Schmoji Collection") {
    NavigationStack {
        SchmojiCollectionView()
    }
    .modelContainer(PreviewSampleData.makeContainer())
}
