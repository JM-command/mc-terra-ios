//
//  WidgetSupport.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Shared helpers for the home-screen widgets: a snapshot value type read from
//  SwiftData (so timeline entries stay lightweight and Sendable), date/CHF
//  formatting, the location icon, and the timeline refresh cadence.

import Foundation
import SwiftData
import SwiftUI

// MARK: - Lightweight session snapshot

/// A plain value copied out of a `Seance` `@Model`. Timeline entries must be
/// simple value types (the `@Model` object is bound to its `ModelContext`), so
/// providers read the rows then map them into this struct.
struct SessionSnapshot: Identifiable, Hashable {
    let id: String
    let date: Date
    let clientName: String
    let serviceName: String
    let durationMinutes: Int
    let priceCHF: Double
    /// Raw `SessionLocation` value ("cabinet"/"zoom"), or "" when unset.
    let location: String
    /// Raw `PaymentMethod` value ("twint"/"carte"/"cash"), or "" when unpaid.
    let paymentMethod: String

    /// SF Symbol for the stored `location` string. Mirrors the app's
    /// `SessionLocation.icon` without depending on the app-only enum.
    var locationIcon: String {
        switch location {
        case "cabinet": return "house"
        case "zoom": return "video"
        default: return "calendar"
        }
    }
}

extension Seance {
    /// Maps a fetched `Seance` into a process-safe snapshot for timeline entries.
    /// Uses the model's stable `uuid` as identity so the widget can build a
    /// deep-link URL (`mcterra://seance/<uuid>`) that resolves back to this row.
    func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            id: uuid.uuidString,
            date: date,
            clientName: client?.name ?? "Sans client",
            serviceName: serviceName,
            durationMinutes: durationMinutes,
            priceCHF: priceCHF,
            location: location,
            paymentMethod: paymentMethod
        )
    }
}

// MARK: - Lightweight client snapshot

/// A plain value copied out of a `Client` `@Model`, mirroring `SessionSnapshot`.
/// Timeline entries must be simple value types, so the "Clients récents" provider
/// reads the rows then maps them into this struct.
struct ClientSnapshot: Identifiable, Hashable {
    /// The client's stable `uuid` string; used for identity and the deep-link URL.
    let id: String
    let name: String
    /// Raw language value ("fr"/"pt"), shown as a small flag/label in the widget.
    let language: String
    let createdAt: Date
    /// Number of sessions booked for this client, shown as a subtitle.
    let seanceCount: Int
}

extension Client {
    /// Maps a fetched `Client` into a process-safe snapshot for timeline entries.
    /// Uses the model's stable `uuid` so the widget can build a deep-link URL
    /// (`mcterra://client/<uuid>`) that resolves back to this row.
    func clientSnapshot() -> ClientSnapshot {
        ClientSnapshot(
            id: uuid.uuidString,
            name: name,
            language: language,
            createdAt: createdAt,
            seanceCount: seances.count
        )
    }
}

// MARK: - Deep links

/// Builds `mcterra://` deep-link URLs shared by every widget. Centralized so the
/// host/path scheme stays in sync with the app's router (`DeepLinkRouter`).
enum WidgetDeepLink {
    /// `mcterra://seance/<uuid>` — opens a session's detail screen.
    static func seance(_ uuidString: String) -> URL? {
        URL(string: "mcterra://seance/\(uuidString)")
    }

    /// `mcterra://client/<uuid>` — opens a client's detail screen.
    static func client(_ uuidString: String) -> URL? {
        URL(string: "mcterra://client/\(uuidString)")
    }

    /// `mcterra://compta` — opens the accounting dashboard.
    static var compta: URL? {
        URL(string: "mcterra://compta")
    }
}

// MARK: - SwiftData access

/// Reads the shared App Group store from a widget process. Returns a fresh
/// `ModelContext` each call; providers fetch synchronously off it.
enum WidgetStore {
    /// A `ModelContext` on the shared App Group container, or `nil` if the store
    /// can't be opened (most likely the App Groups capability is missing).
    static func context() -> ModelContext? {
        ModelContext(SharedModelContainer.shared)
    }
}

// MARK: - Formatting

/// Formatting helpers shared across widget views, kept here so the SwiftUI
/// views stay small and the compiler doesn't time out type-checking them.
enum WidgetFormat {
    /// "14:30" — time only, current locale.
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "lun. 9 juin" — short weekday + day + month.
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "9 juin, 14:30" — compact date + time for list rows.
    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// "120.–" CHF amount, no decimals when whole, two otherwise.
    static func chf(_ amount: Double) -> String {
        if amount.rounded() == amount {
            return "\(Int(amount)).–"
        }
        return String(format: "%.2f", amount)
    }
}

// MARK: - Refresh cadence

/// How often a widget timeline should rebuild. Sessions move slowly, so a
/// 20-minute cadence keeps things fresh without burning the system budget.
enum WidgetRefresh {
    static let interval: TimeInterval = 20 * 60

    /// The next refresh date from `now`.
    static func next(after now: Date = .now) -> Date {
        now.addingTimeInterval(interval)
    }
}
