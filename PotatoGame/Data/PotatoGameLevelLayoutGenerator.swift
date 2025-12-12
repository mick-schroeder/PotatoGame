// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import CoreGraphics
import Foundation

enum PotatoGameLevelLayoutGenerator {
    static func layoutObjects(for levelNumber: Int) -> [SchmojiBoardObject] {
        guard let template = LevelTemplateByNumber[levelNumber] else { return [] }
        let rows = template.rows
        guard rows.isEmpty == false else { return [] }

        let usableRect = safeRect(playableFrame().insetBy(dx: 40, dy: 80))
        let maxColumns = rows.map(\.count).max() ?? 0
        guard maxColumns > 0 else { return [] }

        let rowCount = rows.count
        let stepY = rowCount > 0 ? usableRect.height / CGFloat(rowCount) : 0
        let stepX = max(usableRect.width / CGFloat(maxColumns), 0)

        var objects: [SchmojiBoardObject] = []
        objects.reserveCapacity(rows.reduce(0) { $0 + $1.compactMap(\.self).count })

        for (rowIndex, row) in rows.enumerated() {
            let rowColumnCount = row.count
            guard rowColumnCount > 0 else { continue }

            let offsetX = usableRect.minX + (CGFloat(maxColumns - rowColumnCount) / 2.0) * stepX
            let centerY = usableRect.maxY - (CGFloat(rowIndex) + 0.5) * stepY

            for (columnIndex, maybeID) in row.enumerated() {
                guard
                    let order = maybeID,
                    let color = PotatoColor(order: order)
                else { continue }

                let centerX = offsetX + (CGFloat(columnIndex) + 0.5) * stepX
                let rawPoint = CGPoint(x: centerX, y: centerY)
                let object = SchmojiBoardObject(
                    color: color,
                    positionX: Double(rawPoint.x),
                    positionY: Double(rawPoint.y)
                )
                objects.append(object)
            }
        }

        return objects
    }
}

private extension PotatoGameLevelLayoutGenerator {
    static var stageRect: CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(PotatoGameOptions.width), height: CGFloat(PotatoGameOptions.height))
    }

    static func playableFrame() -> CGRect {
        let inset: CGFloat = 40
        let width = CGFloat(PotatoGameOptions.width)
        let height = CGFloat(PotatoGameOptions.height)
        return CGRect(
            x: inset,
            y: inset,
            width: max(20, width - inset * 2),
            height: max(20, height - inset * 2)
        )
    }

    static func safeRect(_ rect: CGRect) -> CGRect {
        let width = max(rect.width, 20)
        let height = max(rect.height, 20)
        var adjustedRect = CGRect(x: rect.minX, y: rect.minY, width: width, height: height)

        if adjustedRect.maxX > stageRect.maxX {
            adjustedRect.origin.x = stageRect.maxX - adjustedRect.width
        }
        if adjustedRect.maxY > stageRect.maxY {
            adjustedRect.origin.y = stageRect.maxY - adjustedRect.height
        }
        adjustedRect.origin.x = max(stageRect.minX, adjustedRect.origin.x)
        adjustedRect.origin.y = max(stageRect.minY, adjustedRect.origin.y)
        return adjustedRect
    }
}
