// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import Observation
import OSLog
import SwiftData
#if canImport(WidgetKit)
    import WidgetKit
#endif

private let logger = Logger(subsystem: "PotatoGame", category: "Account")

@Model public class Account {
    static let widgetSuiteName = "group.com.mickschroeder.potatogame"
    static let widgetPotatoCountKey = "widgetPotatoCount"
    public static let defaultUserID = "local-user"

    public var id: String = "local-user"
    public var joinDate: Date = Date.now
    public var potatoCount: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \AccountPurchasedPack.account)
    var purchasedPackEntries: [AccountPurchasedPack]?

    public init(id: String = "local-user", joinDate: Date = .now, purchasedLevelPackIDs: [String] = []) {
        self.id = id
        self.joinDate = joinDate
        self.purchasedLevelPackIDs = Array(Set(purchasedLevelPackIDs)).sorted()
    }

    // Increment potato count
    public func addPotatoes(by amount: Int = 1) {
        guard amount > 0 else { return }
        potatoCount += amount
        let newTotal = potatoCount
        logger.debug("Potato count incremented by \(amount). New count: \(newTotal)")
        updateWidgetPotatoCount()
    }
}

public extension Account {
    var purchasedLevelPackIDs: [String] {
        get {
            (purchasedPackEntries ?? [])
                .sorted { lhs, rhs in
                    if lhs.orderIndex == rhs.orderIndex {
                        return lhs.purchaseDate < rhs.purchaseDate
                    }
                    return lhs.orderIndex < rhs.orderIndex
                }
                .map(\.packID)
        }
        set {
            let sanitized = Array(NSOrderedSet(array: newValue)).compactMap { $0 as? String }
            purchasedPackEntries = sanitized.enumerated().map { index, packID in
                AccountPurchasedPack(packID: packID, purchaseDate: Date.now, orderIndex: index, account: self)
            }
        }
    }

    var ownedLevelPackIDs: Set<String> {
        Set(purchasedLevelPackIDs)
    }

    func ownsLevelPack(withID id: String) -> Bool {
        ownedLevelPackIDs.contains(id)
    }

    func ownsRequiredLevelPack(for levelNumber: Int) -> Bool {
        guard let pack = LevelPackRegistry.definition(forLevel: levelNumber) else {
            return true
        }
        return ownsLevelPack(withID: pack.id)
    }

    func registerPurchase(for productID: String) {
        guard let definition = LevelPackRegistry.definition(forProductID: productID) else { return }
        addLevelPackID(definition.id)
    }

    private func addLevelPackID(_ packID: String) {
        guard purchasedLevelPackIDs.contains(packID) == false else { return }
        var ids = purchasedLevelPackIDs
        ids.append(packID)
        purchasedLevelPackIDs = ids
    }

    internal func updateWidgetPotatoCount() {
        guard let defaults = UserDefaults(suiteName: Self.widgetSuiteName) else { return }
        defaults.set(potatoCount, forKey: Self.widgetPotatoCountKey)
        Self.reloadPotatoWidgetTimeline()
    }
}

extension Account {
    static func reloadPotatoWidgetTimeline() {
        #if canImport(WidgetKit)
            if #available(iOS 14.0, macOS 11.0, watchOS 7.0, *) {
                Task { @MainActor in
                    WidgetCenter.shared.reloadTimelines(ofKind: "PotatoGameWidget")
                }
            }
        #endif
    }
}
