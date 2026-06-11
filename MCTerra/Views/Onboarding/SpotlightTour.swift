//
//  SpotlightTour.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  A guided, game-style tutorial: it dims the whole screen, cuts a hole around
//  one real UI element at a time, and shows a bubble explaining it. Steps run
//  across the home screen and the menu; a "Passer" button skips at any point.
//
//  How it works:
//  - Tag any view with `.spotlightTarget("id")`; it reports its frame via an
//    anchor preference.
//  - `TourController` holds the ordered steps and the current index.
//  - `ContentView` hosts the overlay (reads the anchors) and reveals the right
//    surface (home vs menu) for each step.
//

import SwiftUI
import Combine

// MARK: - Model

/// Which app surface a step lives on, so the host can reveal it before showing
/// the spotlight (e.g. open the menu).
enum TourScreen {
    case home
    case menu
}

/// One tutorial step, pointing at a tagged target.
struct SpotlightStep: Identifiable {
    /// Must match a `.spotlightTarget(id)` somewhere on the step's screen.
    let id: String
    let screen: TourScreen
    let title: LocalizedStringKey
    let text: LocalizedStringKey
}

/// The full guided tour: home first, then the menu destinations.
enum SpotlightTour {
    static let steps: [SpotlightStep] = [
        .init(id: "input", screen: .home,
              title: "Écris ou parle ici",
              text: "Tape une demande (par ex. « ajoute une séance demain 14h avec Sophie »), l'app comprend et agit."),
        .init(id: "mic", screen: .home,
              title: "Dicte à la voix",
              text: "Appuie sur le micro et parle, comme un message vocal WhatsApp."),
        .init(id: "plus", screen: .home,
              title: "Raccourcis rapides",
              text: "Le plus ouvre une nouvelle séance ou un nouveau client en deux taps."),
        .init(id: "menu", screen: .home,
              title: "Le menu",
              text: "Ce bouton ouvre tout : tes clients, ton agenda, ta comptabilité."),
        .init(id: "clients", screen: .menu,
              title: "Tes clients",
              text: "Ici tu retrouves, ajoutes et contactes tes clients."),
        .init(id: "agenda", screen: .menu,
              title: "Ton agenda",
              text: "Tes séances, en vue mois ou jour, comme un agenda classique."),
        .init(id: "compta", screen: .menu,
              title: "Ta comptabilité",
              text: "Tes revenus suivis, prêts à exporter pour ta déclaration.")
    ]
}

// MARK: - Controller

@MainActor
final class TourController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var index = 0

    let steps: [SpotlightStep]

    init(steps: [SpotlightStep] = SpotlightTour.steps) {
        self.steps = steps
    }

    /// The step currently shown, or `nil` when the tour is off.
    var current: SpotlightStep? {
        guard isActive, index >= 0, index < steps.count else { return nil }
        return steps[index]
    }

    var isLast: Bool { index >= steps.count - 1 }

    func start() {
        index = 0
        isActive = true
    }

    func next() {
        if isLast { finish() } else { index += 1 }
    }

    func finish() {
        isActive = false
        index = 0
    }
}

// MARK: - Anchor plumbing

/// Collects the frame of every tagged target, keyed by id.
struct SpotlightAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as a tutorial target the spotlight can highlight.
    func spotlightTarget(_ id: String) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Punches a hole in `self` shaped like `mask` (used for the dim cutout).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .center) {
                    mask().blendMode(.destinationOut)
                }
        }
    }
}

// MARK: - Overlay

/// The dim-and-spotlight layer. Lives above everything; reads the resolved frame
/// of the current step's target and draws the cutout plus the explanation bubble.
struct SpotlightOverlay: View {
    @ObservedObject var tour: TourController
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy

    var body: some View {
        if let step = tour.current {
            let rect = anchors[step.id].map { proxy[$0] }
            ZStack {
                dim(around: rect)
                bubbleArea(for: step, rect: rect)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    /// Full-screen dim with a rounded hole around the target (if known).
    private func dim(around rect: CGRect?) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.72))
            .reverseMask {
                if let rect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .frame(width: rect.width + 16, height: rect.height + 16)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .contentShape(Rectangle())
            // Tapping the dimmed area advances, like most game tutorials.
            .onTapGesture { withAnimation { tour.next() } }
    }

    /// Places the bubble in the half of the screen opposite the target, so it
    /// never covers the highlighted element.
    private func bubbleArea(for step: SpotlightStep, rect: CGRect?) -> some View {
        let targetLow = (rect?.midY ?? proxy.size.height / 2) > proxy.size.height / 2
        return VStack(spacing: 0) {
            if targetLow {
                bubble(step)
                    .padding(.top, 80)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                bubble(step)
                    .padding(.bottom, 100)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bubble(_ step: SpotlightStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(step.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                dots
                Spacer()
                Button("Passer") { withAnimation { tour.finish() } }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation { tour.next() }
                } label: {
                    Text(tour.isLast ? "Terminer" : "Suivant")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.tint))
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        )
        .environment(\.colorScheme, .light)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(tour.steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == tour.index ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
