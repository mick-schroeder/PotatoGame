//
//  AppIntent.swift
//  PotatoGameWidget
//
//  Created by Mick Schroeder on 11/1/25.
//  Copyright © 2025 Mick Schroeder, LLC. All rights reserved.
//

import AppIntents
import WidgetKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "LocalizedStringResource.potatoWidget" }
    static var description: IntentDescription { "LocalizedStringResource.keepAnEyeOnYourPotatoCount" }
}
