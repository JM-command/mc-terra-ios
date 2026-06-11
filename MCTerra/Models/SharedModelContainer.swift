//
//  SharedModelContainer.swift
//  MCTerra / MCTerraWidgetsExtension
//
//  Created by Jaime Coelho on 05.06.2026.
//

// ⚠️ This file MUST belong to BOTH targets: MCTerra AND MCTerraWidgetsExtension.
// The widget extension runs in a separate process and needs the same SwiftData
// store as the app. Both processes open it through the App Group container.
//
// ⚠️ REQUIRED CAPABILITY — the app will crash at runtime without it:
// In Xcode → select the MCTerra target → Signing & Capabilities → + Capability →
// "App Groups" → add `group.ch.irixiagroup.MCTerra`. Repeat for the
// MCTerraWidgetsExtension target. BOTH targets must enable the SAME group id.

import Foundation
import SwiftData

/// Central place for the App Group identifier so the app and the widget never
/// drift apart. Both processes build their `ModelContainer` from this value.
enum AppGroup {
    /// Shared App Group id. Must match the capability enabled on BOTH targets.
    static let identifier = "group.ch.irixiagroup.MCTerra"
}

/// Builds the shared SwiftData `ModelContainer` backed by the App Group store.
///
/// The app injects this container into its scene; each widget timeline provider
/// opens it to read the same `Client`/`Seance` data the app writes. Because both
/// processes point `ModelConfiguration` at the same App Group container, the
/// widget always sees the latest saved data.
enum SharedModelContainer {
    /// The schema shared by the app and the widget.
    static let schema = Schema([Client.self, Seance.self, Forfait.self, Note.self])

    /// Lazily-built, shared container. Built once per process.
    static let shared: ModelContainer = {
        let configuration: ModelConfiguration
        // Only use the App Group store if the capability is actually enabled —
        // otherwise SwiftData crashes hard. When it's missing we fall back to a
        // local store so the app still runs; the widget only sees the data once
        // the App Group is added to both targets.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil {
            configuration = ModelConfiguration(
                schema: schema,
                groupContainer: .identifier(AppGroup.identifier)
            )
        } else {
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to build ModelContainer: \(error)")
        }
    }()
}
