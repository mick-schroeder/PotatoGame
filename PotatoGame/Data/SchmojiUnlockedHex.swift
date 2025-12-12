// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData

@Model final class PotatoGameUnlockedHex {
    var id: UUID = UUID()
    var hexcode: String = PotatoGameOptions.potatoHex
    var orderIndex: Int = 0

    var selection: EmojiSelection?

    init(hexcode: String, orderIndex: Int, selection: EmojiSelection? = nil) {
        self.hexcode = hexcode
        self.orderIndex = orderIndex
        self.selection = selection
    }
}
