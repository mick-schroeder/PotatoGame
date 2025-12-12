// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

struct CollectionCircleView: View {
    @Environment(\.colorScheme) private var colorScheme

    let color: PotatoColor
    let hexcode: String

    var body: some View {
        VStack(spacing: 4) {
            PotatoGameArt.image(forHexcode: hexcode, targetDiameter: 48)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .shadow(radius: 3)
                .padding(6)
                .background(
                    Circle()
                        .foregroundStyle(color.color)
                )
            /*
                        #if DEBUG
                            Text(hexcode.uppercased())
                                .font(.caption2.monospaced())
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(
                                            (colorScheme == .dark ? Color.white : Color.black)
                                                .opacity(colorScheme == .dark ? 0.25 : 0.6)
                                        )
                                )
                        #endif
             */
        }
    }
}

#Preview("Schmoji Circle") {
    CollectionCircleView(
        color: .green,
        hexcode: PotatoColor.green.schmojis.first ?? PotatoGameOptions.potatoHex
    )
    .padding()
    .background(Color.appBackground)
}
