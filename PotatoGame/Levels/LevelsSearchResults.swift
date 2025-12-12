// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

struct LevelsSearchResults: View {
    let levels: [PotatoGameLevelInfo]
    var body: some View {
        ForEach(levels) { level in
            LevelsGridItem(level: level)
        }
    }
}

#Preview("Levels Search Results") {
    ScrollView {
        LevelsSearchResults(levels: PreviewSampleData.sampleLevels())
            .padding()
    }
    .environment(PreviewSampleData.makeLevelPackStore())
    .background(Color.appBackground)
}
