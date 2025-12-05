//
//  PotatoGameWidget.swift
//  PotatoGameWidget
//
//  Created by Mick Schroeder on 11/1/25.
//  Copyright © 2025 Mick Schroeder, LLC. All rights reserved.
//

import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in _: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), potatoCount: PotatoWidgetDataSource.placeholderCount)
    }

    func getSnapshot(in _: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), potatoCount: PotatoWidgetDataSource.currentPotatoCount()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let currentDate = Date()
        let count = PotatoWidgetDataSource.currentPotatoCount()
        // Refresh roughly every 30 minutes to stay close to in-app updates while respecting budget.
        let refreshInterval: TimeInterval = 30 * 60
        let entries = stride(from: 0, through: refreshInterval * 6, by: refreshInterval).map { offset in
            SimpleEntry(date: currentDate.addingTimeInterval(offset), potatoCount: count)
        }
        completion(Timeline(entries: entries, policy: .after(currentDate.addingTimeInterval(refreshInterval * 6))))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let potatoCount: Int
}

struct PotatoGameWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("developer.hero_link")
                    .font(.caption.bold())
                    .foregroundStyle(PotatoTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("app.name")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(PotatoTheme.text)
            }
            .foregroundStyle(PotatoTheme.text)
            Spacer()
            HStack(alignment: .center) {
                PotatoWidgetIcon()
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 0) {
                    Text(.potatoes)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .foregroundStyle(PotatoTheme.secondaryText)
                    Text(entry.potatoCount.formattedGrouped)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .monospacedDigit()
                        .accessibilityLabel("\(entry.potatoCount) potatoes")
                        .foregroundStyle(PotatoTheme.text)
                }
            }
            Spacer()
        }

        .foregroundStyle(.brown)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color("PotatoSecondaryBackground").opacity(0.95),
                    Color("PotatoBackground").opacity(0.9),
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct PotatoGameWidget: Widget {
    let kind: String = "PotatoGameWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PotatoGameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource.potatoGame)
        .description(LocalizedStringResource.seeYourCurrentPotatoCountAtAGlance)
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    PotatoGameWidget()
} timeline: {
    SimpleEntry(date: .now, potatoCount: 128)
    SimpleEntry(date: .now, potatoCount: 2568)
}

struct PotatoWidgetIcon: View {
    var body: some View {
        Image("Cool Potato")
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
            .accessibilityLabel(.potatoIcon)
    }
}

enum PotatoWidgetDataSource {
    private static let suiteName = "group.com.mickschroeder.potatogame"
    private static let potatoCountKey = "widgetPotatoCount"

    static var placeholderCount: Int { 0 }

    static func currentPotatoCount() -> Int {
        let defaults = UserDefaults(suiteName: suiteName)
        let count = defaults?.integer(forKey: potatoCountKey) ?? 0
        return max(0, count)
    }
}

private extension Int {
    var formattedGrouped: String {
        formatted(.number.grouping(.automatic))
    }
}
