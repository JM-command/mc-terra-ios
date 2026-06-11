//
//  StartNowBanner.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  A home-screen shortcut that only shows up when a session is due right now.
//  Tapping it starts the session in one tap (in-app timer + lock-screen Live
//  Activity), since iOS won't let the app start that on its own at a set time.
//

import SwiftUI
import SwiftData

struct StartNowBanner: View {
    @ObservedObject var liveSession: LiveSessionManager
    /// Tapping the "séance en cours" card opens that session's detail screen.
    /// Wired by the parent (via the deep-link router); no-op by default.
    var onOpenSeance: (Seance) -> Void = { _ in }
    @Query(sort: \Seance.date) private var seances: [Seance]

    var body: some View {
        // Re-checks every 30s so the banner appears around the session's time
        // even if the home screen was already open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let seance = dueSession(at: context.date) {
                banner(for: seance)
            }
        }
    }

    /// The planned session happening right now: from 15 min before its start
    /// until its scheduled end. Nil when nothing is due.
    private func dueSession(at now: Date) -> Seance? {
        seances.first { seance in
            guard seance.status == SeanceStatus.planned else { return false }
            let start = seance.date.addingTimeInterval(-15 * 60)
            let end = seance.date.addingTimeInterval(Double(max(seance.durationMinutes, 30)) * 60)
            return now >= start && now <= end
        }
    }

    @ViewBuilder
    private func banner(for seance: Seance) -> some View {
        if liveSession.isRunning(seance), liveSession.isLive {
            runningCard(for: seance)
        } else {
            startButton(for: seance)
        }
    }

    private func startButton(for seance: Seance) -> some View {
        Button {
            liveSession.start(for: seance)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Démarrer la séance")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: subtitle(for: seance))
                        .font(.caption)
                        .opacity(0.9)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.tint)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func runningCard(for seance: Seance) -> some View {
        // Tappable: opens the session detail. `.plain` keeps the card's look.
        Button {
            onOpenSeance(seance)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Séance en cours")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: clientName(for: seance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let start = liveSession.activeStart {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tint)
                }
                // Discreet hint that the card is tappable.
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func clientName(for seance: Seance) -> String {
        seance.client?.name ?? String(localized: "Sans client")
    }

    private func subtitle(for seance: Seance) -> String {
        let time = seance.date.formatted(date: .omitted, time: .shortened)
        return "\(clientName(for: seance)) · \(time)"
    }
}
