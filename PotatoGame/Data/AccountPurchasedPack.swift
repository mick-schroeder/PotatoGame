// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftData

@Model final class AccountPurchasedPack {
    var id: UUID = UUID()
    var packID: String = ""
    var purchaseDate: Date = Date()
    var orderIndex: Int = 0

    var account: Account?

    init(packID: String, purchaseDate: Date = Date(), orderIndex: Int = 0, account: Account? = nil) {
        self.packID = packID
        self.purchaseDate = purchaseDate
        self.orderIndex = orderIndex
        self.account = account
    }
}
