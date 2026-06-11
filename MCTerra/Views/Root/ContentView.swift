//
//  ContentView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var showMenu = false
    @State private var showSplash = true
    // First-launch onboarding, shown once after the splash settles.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var message = ""
    // Sent messages (session only, no history yet).
    @State private var messages: [ChatMessage] = []
    // True while the AI is working on a reply (shows a typing indicator).
    @State private var isThinking = false
    // Shortcut sheets opened from the "+" button.
    @State private var showNewSeance = false
    @State private var showNewClient = false
    // Guided spotlight tutorial (game-style coachmarks across home + menu).
    @StateObject private var tour = TourController()
    // Drives the "start now" banner's session timer + Live Activity.
    @StateObject private var liveSession = LiveSessionManager()
    // Set by Settings ("Visite guidée") to request the tour from the home screen.
    @AppStorage("pendingTour") private var pendingTour = false
    @StateObject private var speech = SpeechRecognizer()
    @AppStorage("appLanguage") private var appLanguage = "fr"
    // Calendar chosen in Settings; lets the AI push its sessions to Google too.
    @AppStorage("googleCalendarId") private var googleCalendarId = ""
    // Live SwiftData context the AI toolbox reads/writes through.
    @Environment(\.modelContext) private var modelContext
    // Shared Google connection, passed to the AI so it can mirror to the calendar.
    @EnvironmentObject private var google: GoogleCalendarService
    // Deep-link target requested from a widget (injected by MCTerraApp). When set,
    // we present the matching screen full-screen; dismissing clears it.
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter

    // Pre-filled prompts shown on the empty home screen. `label` is localized
    // (FR/PT via the String Catalog); `command` is the canonical text sent to the
    // bilingual AI, which replies in the app's language.
    private struct QuickAction: Identifiable {
        var id: String { command }
        let label: LocalizedStringKey
        let command: String
    }

    private let quickActions: [QuickAction] = [
        .init(label: "Mes rendez-vous aujourd'hui", command: "Mes rendez-vous aujourd'hui"),
        .init(label: "Ma prochaine séance", command: "Ma prochaine séance"),
        .init(label: "Mes revenus du mois", command: "Mes revenus du mois"),
        .init(label: "Mes clients", command: "Mes clients")
    ]

    var body: some View {
        ZStack {
            chatScreen

            // Thin invisible strip on the left edge that reliably catches the
            // open swipe, even over scrollable content.
            if !showMenu {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(edgeOpenGesture)
                    Spacer()
                }
                .ignoresSafeArea()
            }

            if showMenu {
                MenuView(goHome: { closeMenu() })
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }

            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        // A widget tap arrives as a `mcterra://` URL, parsed by DeepLinkRouter into
        // a route. Present the matching screen full-screen; dismissing clears it.
        .fullScreenCover(item: $deepLinkRouter.route) { route in
            DeepLinkCover(route: route) {
                deepLinkRouter.route = nil
            }
        }
        .sheet(isPresented: $showNewSeance) {
            NewSeanceView()
        }
        .sheet(isPresented: $showNewClient) {
            NewClientView()
        }
        // First launch: once the splash is gone, show the onboarding over the home
        // screen. "Commencer" flips the stored flag so it never shows again.
        .fullScreenCover(isPresented: showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
            }
        }
        // Guided spotlight tour, drawn above everything. Reads the frames of the
        // tagged targets (home + menu) and highlights one per step.
        .overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if tour.isActive {
                    SpotlightOverlay(tour: tour, anchors: anchors, proxy: proxy)
                }
            }
            // Span the full screen so anchor positions are resolved in the same
            // coordinate space the cutout is drawn in (no safe-area offset).
            .ignoresSafeArea()
        }
        // Reveal the right surface for the current step (open the menu for menu
        // steps), and start the tour when Settings requests it.
        .onChange(of: tour.index) { syncMenuToTour() }
        .onChange(of: tour.isActive) { _, active in
            if active { syncMenuToTour() } else { withAnimation { showMenu = false } }
        }
        .onChange(of: pendingTour) { _, pending in
            guard pending else { return }
            pendingTour = false
            showMenu = false
            tour.start()
        }
    }

    /// Opens the menu for menu steps, closes it for home steps.
    private func syncMenuToTour() {
        guard tour.isActive, let screen = tour.current?.screen else { return }
        withAnimation(.snappy(duration: 0.3)) {
            showMenu = (screen == .menu)
        }
    }

    /// True only once the splash has finished and onboarding hasn't been seen yet.
    /// Bound through a derived Binding so the cover dismisses when the flag flips.
    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !showSplash && !hasSeenOnboarding },
            set: { _ in }
        )
    }

    // MARK: - Menu open/close

    private var edgeOpenGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onEnded { value in
                // The strip already constrains the start to the left edge.
                if value.translation.width > 50 {
                    openMenu()
                }
            }
    }

    private func openMenu() {
        withAnimation(.snappy(duration: 0.3)) { showMenu = true }
    }

    private func closeMenu() {
        withAnimation(.snappy(duration: 0.3)) { showMenu = false }
    }

    // MARK: - Chat (command) screen

    private var chatScreen: some View {
        VStack(spacing: 0) {
            header
            conversation
            inputBar
        }
    }

    private var header: some View {
        HStack {
            // Hamburger opens the menu.
            Button {
                openMenu()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
            }
            .spotlightTarget("menu")
            Spacer()
            // Clear the conversation, only when there are messages.
            if !messages.isEmpty {
                Button {
                    withAnimation { messages.removeAll() }
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                }
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .opacity(0)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // Empty state shows the big logo; once messages exist, show the list.
    private var conversation: some View {
        Group {
            if messages.isEmpty {
                VStack(spacing: 28) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120)
                        .opacity(0.9)
                        .padding(.top, 60)
                    StartNowBanner(liveSession: liveSession) { seance in
                        deepLinkRouter.route = .seance(seance.uuid)
                    }
                    HomeStatsView()
                    quickActionChips
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { msg in
                                VStack(alignment: .leading, spacing: 8) {
                                    bubble(msg)
                                    if !msg.suggestions.isEmpty {
                                        suggestionButtons(msg.suggestions)
                                    }
                                }
                                .id(msg.id)
                            }
                            if isThinking {
                                thinkingBubble.id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: isThinking) {
                        if isThinking {
                            withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Pre-filled suggestion chips on the empty home screen.
    private var quickActionChips: some View {
        VStack(spacing: 10) {
            ForEach(quickActions) { action in
                Button {
                    sendQuickAction(action.command)
                } label: {
                    Text(action.label)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.gray.opacity(0.12)))
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func bubble(_ msg: ChatMessage) -> some View {
        if msg.isUser {
            // User command: aligned right, tinted.
            HStack {
                Spacer(minLength: 40)
                Text(msg.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            // AI reply: aligned left, neutral. Rendered as Markdown so bold/italic
            // and simple lists look clean (newlines preserved).
            HStack {
                Text(markdown(msg.text))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 40)
            }
        }
    }

    // Parses inline Markdown while keeping line breaks; falls back to plain text.
    private func markdown(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }

    // Tappable quick-reply buttons under an AI message (e.g. choosing a client).
    private func suggestionButtons(_ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button {
                    runCommand(option)
                } label: {
                    Text(verbatim: option)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.tint.opacity(0.15)))
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.leading, 2)
    }

    // Three pulsing dots shown while the AI is composing a reply.
    private var thinkingBubble: some View {
        HStack {
            TypingDots()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 40)
        }
    }

    private var inputBar: some View {
        // Bottom-aligned so the buttons stay put as the field grows over lines.
        HStack(alignment: .bottom, spacing: 12) {
            if speech.isRecording {
                // Recording: left = stop (drops the text into the field to review),
                // center = waveform, right = send (fires the dictated text directly).
                Button {
                    stopDictation()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                RecordingWaveform(levels: speech.levels)
                    .frame(maxWidth: .infinity, maxHeight: 26)
                Button {
                    sendDictation()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
            } else {
                Menu {
                    Button {
                        showNewSeance = true
                    } label: {
                        Label("Nouvelle séance", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        showNewClient = true
                    } label: {
                        Label("Nouveau client", systemImage: "person.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
                .spotlightTarget("plus")

                // Grows like iMessage: 1 line up to 6, then scrolls inside.
                // Return inserts a newline; sending is done with the button.
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.vertical, 2)
                    .spotlightTarget("input")

                if message.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                    .spotlightTarget("mic")
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
        .padding()
    }

    // MARK: - Actions

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        message = ""
        runCommand(text)
    }

    private func sendQuickAction(_ text: String) {
        runCommand(text)
    }

    /// Shows the command as a user bubble, then asks the AI agent for a reply.
    private func runCommand(_ text: String) {
        guard !isThinking else { return }
        // Clear any previous quick-reply buttons once a new message is sent.
        for i in messages.indices { messages[i].suggestions = [] }
        withAnimation { messages.append(ChatMessage(text: text, isUser: true)) }

        // Pass the prior conversation (excluding the message just added) as context.
        let history = messages.dropLast().map {
            (role: $0.isUser ? "user" : "assistant", text: $0.text)
        }

        isThinking = true
        let agent = AIAgent(
            context: modelContext,
            language: appLanguage,
            google: google,
            googleCalendarId: googleCalendarId
        )
        Task {
            defer { isThinking = false }
            do {
                let reply = try await agent.respond(to: text, history: Array(history))
                withAnimation {
                    messages.append(ChatMessage(
                        text: reply.text,
                        isUser: false,
                        suggestions: reply.suggestions
                    ))
                }
            } catch {
                let message = String(
                    localized: "Souci de connexion, réessaie dans un instant.",
                    locale: Locale(identifier: appLanguage)
                )
                withAnimation {
                    messages.append(ChatMessage(text: message, isUser: false))
                }
            }
        }
    }

    private func startRecording() {
        Task {
            let granted = await speech.requestAuthorization()
            guard granted else { return }
            message = ""
            speech.setLanguage(appLanguage)
            speech.start()
        }
    }

    private func stopDictation() {
        speech.stop()
        // The spoken text drops into the field all at once.
        message = speech.transcript
    }

    /// Stops dictation and sends the spoken text straight to the AI, without
    /// passing through the text field.
    private func sendDictation() {
        speech.stop()
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        message = ""
        guard !text.isEmpty else { return }
        runCommand(text)
    }
}

/// One chat message. AI replies may carry tappable quick-reply buttons.
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    /// Quick-reply options shown as buttons under an AI message (Telegram style).
    var suggestions: [String] = []
}

/// Three dots that pulse in sequence while the AI composes a reply.
struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .task {
            // Cycle 0→1→2 forever; the .opacity change animates each step.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
            }
        }
    }
}

/// A live waveform driven by microphone levels (voice-reactive, dictaphone style).
struct RecordingWaveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 3) {
            if levels.isEmpty {
                // Fallback: show empty/quiet bars.
                ForEach(0..<12, id: \.self) { _ in
                    Capsule()
                        .fill(.tint)
                        .frame(width: 3, height: 4)
                }
            } else {
                // Draw bars for each level, with smooth animation.
                ForEach(0..<levels.count, id: \.self) { index in
                    Capsule()
                        .fill(.tint)
                        .frame(width: 3, height: 4 + levels[index] * 22)
                        .transition(.identity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(DeepLinkRouter())
}
