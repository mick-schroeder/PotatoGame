// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

struct PotatoCountView: View {
    @Query private var accounts: [Account]

    var body: some View {
        if let account = accounts.first {
            HStack(spacing: 8) {
                Image("Cool Potato")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(radius: 2)
                    .padding(3)
                Text("\(account.potatoCount)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .padding(3)
            }
            .foregroundStyle(PotatoTheme.accent)
        }
    }
}

#Preview("Potato Count") {
    PotatoCountView()
        .padding()
        .background(Color.appBackground)
        .modelContainer(PreviewSampleData.makeContainer())
}
