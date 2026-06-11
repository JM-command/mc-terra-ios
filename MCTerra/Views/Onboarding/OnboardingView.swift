//
//  OnboardingView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

/// A simple three-page welcome shown on the very first launch. Explains the
/// command bar, the agenda, and the revenue tracking. The last page carries a
/// "Commencer" button that calls `onDone` to dismiss and never show it again.
struct OnboardingView: View {
    /// Called when Marta taps "Commencer" on the last page.
    var onDone: () -> Void

    @State private var page = 0

    /// The three intro pages, in order.
    private let pages: [OnboardingPage] = [
        .init(
            icon: "bubble.left.and.text.bubble.right",
            title: "Parle ou écris, l'app agit",
            text: "Dis ce que tu veux et l'app s'occupe du reste."
        ),
        .init(
            icon: "calendar",
            title: "Ton agenda et tes séances",
            text: "Tes rendez-vous et tes clients, toujours à portée de main."
        ),
        .init(
            icon: "francsign.circle",
            title: "Tes revenus, prêts pour la compta",
            text: "Tes revenus suivis au fil du mois, exportables en un geste."
        )
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Swipeable pages; the system dots are hidden in favour of our own
                // higher-contrast ones below (the default dots vanish on white).
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, 20)

                // Clear forward action: "Suivant" advances, last page starts the app.
                Button {
                    if isLastPage {
                        onDone()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(isLastPage ? "Commencer" : "Suivant")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.tint)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }

            // Close / skip the intro entirely.
            Button {
                onDone()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(Color.gray.opacity(0.12)))
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }

    /// Our own page indicator, tinted so it stays visible on the white background.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

/// The content of a single onboarding page.
private struct OnboardingPage {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
}

/// Renders one onboarding page: a large accent icon, a title, and a sentence.
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text(page.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(page.text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    OnboardingView(onDone: {})
}
