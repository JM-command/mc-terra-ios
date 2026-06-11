//
//  SplashView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var logoScale: CGFloat = 2.3
    @State private var showProgressBar = false
    @State private var progress: CGFloat = 0.0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100)
                    .scaleEffect(logoScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)) {
                            logoScale = 1.0
                        }
                    }

                if showProgressBar {
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                        .frame(width: 160)
                        .transition(.opacity)
                }

                Spacer()
            }
        }
        .task {
            // Wait for logo to settle, then show progress bar.
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeInOut(duration: 0.2)) {
                showProgressBar = true
            }

            // Fill the progress bar over ~1 second.
            let steps = 50
            let stepDuration = 1.0 / Double(steps)
            for i in 0...steps {
                try? await Task.sleep(for: .milliseconds(Int(stepDuration * 1000)))
                withAnimation(.linear(duration: 0.05)) {
                    progress = CGFloat(i) / CGFloat(steps)
                }
            }

            // Call onFinished when done.
            try? await Task.sleep(for: .milliseconds(200))
            onFinished()
        }
    }
}

#Preview {
    SplashView {
        print("Splash finished")
    }
}
