// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData

@Model final class SchmojiUnlockedHex {
    var id: UUID = UUID()
    var hexcode: String = SchmojiOptions.potatoHex
    var orderIndex: Int = 0

    var selection: SchmojiSelection?

    init(hexcode: String, orderIndex: Int, selection: SchmojiSelection? = nil) {
        self.hexcode = hexcode
        self.orderIndex = orderIndex
        self.selection = selection
    }
}
