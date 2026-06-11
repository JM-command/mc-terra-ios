//
//  SpeechRecognizer.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import Combine
import Speech
import AVFoundation

/// Live microphone-to-text using Apple's on-device Speech framework.
/// Free, no API key, works in FR and PT.
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var levels: [CGFloat] = []

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Set the language code (e.g., "fr" or "pt") and update the recognizer.
    func setLanguage(_ code: String) {
        let locale = Locale(identifier: code == "pt" ? "pt-PT" : "fr-FR")
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Ask for microphone + speech permission. Returns true if both granted.
    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        #if os(iOS)
        let micGranted = await AVAudioApplication.requestRecordPermission()
        #else
        let micGranted = true
        #endif
        return speechGranted && micGranted
    }

    /// Start listening and transcribing into `transcript`.
    func start() {
        reset()
        DispatchQueue.main.async {
            self.transcript = ""
            self.levels = []
        }

        guard let recognizer, recognizer.isAvailable else { return }

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = audioEngine.inputNode
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    DispatchQueue.main.async {
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }

            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)

                // Calculate RMS level and publish.
                self?.updateLevels(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            reset()
        }
    }

    /// Stop listening. The last `transcript` stays available to send.
    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task = nil
        DispatchQueue.main.async { self.isRecording = false }
    }

    private func reset() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    /// Calculate RMS (amplitude) from buffer and update the levels rolling array.
    private func updateLevels(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = floatData[i]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(frameLength))
        let normalized = min(1.0, CGFloat(rms) * 12.0) // Scale for visibility.

        DispatchQueue.main.async {
            self.levels.append(normalized)
            // Keep only the last ~32 samples for a rolling waveform.
            if self.levels.count > 32 {
                self.levels.removeFirst()
            }
        }
    }
}
