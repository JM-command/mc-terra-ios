//
//  NextSessionViews.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Per-size layouts for the "Prochaine séance / Agenda" widget. Kept in their
//  own small structs so each body stays cheap for the Swift type-checker.
//  French labels are hard-coded (PT pass comes later).

import SwiftUI
import WidgetKit

// MARK: - Small: the single next session

struct NextSessionSmall: View {
    let next: SessionSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("Prochaine séance")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let next {
                Text(next.clientName)
                    .font(.headline)
                    .lineLimit(2)
                Label {
                    Text(WidgetFormat.time(next.date))
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: next.locationIcon)
                }
                .foregroundStyle(.tint)
                Text(next.serviceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                EmptyAgenda()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium: today's sessions

struct NextSessionMedium: View {
    let today: [SessionSnapshot]
    let fallback: SessionSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aujourd'hui")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                if !today.isEmpty {
                    Text("\(today.count) séance\(today.count > 1 ? "s" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if today.isEmpty {
                if let fallback {
                    Text("Rien aujourd'hui · prochaine :")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SessionRow(session: fallback, showDay: true)
                } else {
                    EmptyAgenda()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ForEach(today.prefix(3)) { session in
                    SessionRow(session: session, showDay: false)
                }
                if today.count > 3 {
                    Text("+\(today.count - 3) autres")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large: the next several sessions

struct NextSessionLarge: View {
    let sessions: [SessionSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text("Prochaines séances")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }

            if sessions.isEmpty {
                EmptyAgenda()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(sessions.prefix(6)) { session in
                    SessionRow(session: session, showDay: true)
                    if session.id != sessions.prefix(6).last?.id {
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

/// One session line: location icon, client + service, time (and optional day).
/// Each row is its own deep link (`mcterra://seance/<uuid>`) so tapping a session
/// in the medium/large layouts opens exactly that session in the app.
struct SessionRow: View {
    let session: SessionSnapshot
    let showDay: Bool

    var body: some View {
        Link(destination: WidgetDeepLink.seance(session.id) ?? fallbackURL) {
            rowContent
        }
    }

    /// Used only if URL construction somehow fails; keeps the row tappable-safe.
    private var fallbackURL: URL { URL(string: "mcterra://seance/")! }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: session.locationIcon)
                .font(.callout)
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.clientName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(session.serviceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(WidgetFormat.time(session.date))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if showDay {
                    Text(WidgetFormat.dayMonth(session.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyAgenda: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Aucune séance à venir")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
