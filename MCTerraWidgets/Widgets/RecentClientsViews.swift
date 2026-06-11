//
//  RecentClientsViews.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Per-size layouts for the "Clients récents" widget. Split into small structs
//  so each body stays cheap for the Swift type-checker. French labels are
//  hard-coded (PT pass comes later).

import SwiftUI
import WidgetKit

// MARK: - Small: the most recent client

struct RecentClientsSmall: View {
    let client: ClientSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text("Client récent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let client {
                Text(client.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(ClientFormat.seances(client.seanceCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                EmptyClients()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium / Large: a list of recent clients

/// Shared list layout used by both medium (limit 3) and large (limit 6). Each
/// row is its own `Link` to `mcterra://client/<uuid>`.
struct RecentClientsList: View {
    let clients: [ClientSnapshot]
    let limit: Int

    private var shown: [ClientSnapshot] { Array(clients.prefix(limit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("Clients récents")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
            }

            if shown.isEmpty {
                EmptyClients()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(shown) { client in
                    ClientRow(client: client)
                    if client.id != shown.last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Shared row

/// One client line: avatar initial, name + session count, language tag. The whole
/// row deep-links to `mcterra://client/<uuid>`.
struct ClientRow: View {
    let client: ClientSnapshot

    var body: some View {
        Link(destination: WidgetDeepLink.client(client.id) ?? fallbackURL) {
            rowContent
        }
    }

    /// Used only if URL construction somehow fails; keeps the row tappable-safe.
    private var fallbackURL: URL { URL(string: "mcterra://client/")! }

    private var rowContent: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.15))
                Text(ClientFormat.initial(client.name))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(client.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(ClientFormat.seances(client.seanceCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(ClientFormat.languageTag(client.language))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Empty state

struct EmptyClients: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Aucun client")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Formatting

/// Client-specific formatting, mirrored from the app without depending on the
/// app-only types. Kept here so the views stay small.
enum ClientFormat {
    /// First letter of the name, uppercased, for the avatar bubble.
    static func initial(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    /// "3 séances" / "1 séance" / "Aucune séance".
    static func seances(_ count: Int) -> String {
        switch count {
        case 0: return "Aucune séance"
        case 1: return "1 séance"
        default: return "\(count) séances"
        }
    }

    /// Short language tag shown on the trailing edge ("FR"/"PT").
    static func languageTag(_ raw: String) -> String {
        switch raw {
        case "pt": return "PT"
        case "fr": return "FR"
        default: return raw.uppercased()
        }
    }
}
