// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

/// Simple horizontal legend showing the current appearance palette.
struct SchmojiColorsLegendGenericView: View {
    @Query private var selections: [SchmojiSelection]

    private var palette: [SchmojiAppearance] {
        SchmojiAppearance.palette(from: selections)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(palette) { appearance in
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        Circle()
                            .foregroundStyle(appearance.color.color)
                            .contentShape(Circle())

                        SchmojiArt.image(forHexcode: appearance.hexcode, targetDiameter: max(24, side))
                            .resizable()
                            .scaledToFit()
                            .padding(side * 0.1)
                            .shadow(radius: max(1, side * 0.045))
                    }
                    .frame(width: side)
                }
                .aspectRatio(1, contentMode: .fit)
                if appearance.color != SchmojiOptions.lastColor {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.black)
                        .imageScale(.small)
                }
            }
        }
    }
}

#Preview("Schmoji Legend") {
    SchmojiColorsLegendGenericView()
        .padding()
        .background(Color.appBackground)
        .modelContainer(PreviewSampleData.makeContainer())
}
