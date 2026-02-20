//
//  TTSViewModel.swift
//  Example
//

import Foundation
import OtosakuTTS_iOS

@MainActor
class TTSViewModel: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var canSynthesize = false
    @Published var selectedSpeaker: FastPitchSpeaker = .coriSamuel
    @Published var pace: Float = 1.0

    private var tts: OtosakuTTS?
    private let modelManager = ModelManager.shared
    private let audioPlayer = AudioPlayer()
    private var hasGeneratedInitialSequence = false
    private let initialSentences = [
        "Morning light spilled across the floor as I opened my laptop, determined to focus, yet already drifting toward ideas I hadn’t finished yesterday.",
        
        "Rain tapped softly against the window while I tried to concentrate, but my thoughts kept wandering to future plans and conversations I hadn’t yet had.",
        
        "The room was quiet except for the steady hum of the fan, and in that stillness I felt both calm and strangely aware of how much there was left to do."
    ]
    func initialize() async {
        errorMessage = nil

        if !modelManager.isModelDownloaded {
            await downloadModels()
        }

        if modelManager.isModelDownloaded {
            await loadTTS()
        }

        await generateInitialSentencesIfNeeded()
    }

    private func downloadModels() async {
        isDownloading = true
        downloadProgress = 0

        do {
            try await modelManager.downloadModels { [weak self] progress in
                self?.downloadProgress = progress
            }
            await loadTTS()
        } catch {
            errorMessage = "Failed to download models: \(error.localizedDescription)"
        }

        isDownloading = false
    }

    private func loadTTS() async {
        do {
            tts = try OtosakuTTS(modelDirectoryURL: modelManager.modelsDirectory, computeUnits: .cpuAndNeuralEngine)
            canSynthesize = true
        } catch {
            errorMessage = "Failed to load TTS: \(error.localizedDescription)"
            canSynthesize = false
        }
    }

    func synthesizeSpeech(
        from text: String,
        speaker: FastPitchSpeaker? = nil,
        pace: Float? = nil
    ) async {
        guard let tts = tts else {
            errorMessage = "TTS not initialized"
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter some text"
            return
        }

        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let config = MultispeakerTTSConfig(
                speaker: speaker ?? selectedSpeaker
            )

            let buffer = try await Task.detached(priority: .userInitiated) {
                try tts.generate(text: text, config: config)
            }.value

            try await audioPlayer.play(buffer: buffer)
        } catch {
            let nsError = error as NSError
            print("SYNTHESIZE ERROR: \(nsError.domain) code \(nsError.code) userInfo: \(nsError.userInfo)")
            errorMessage = "Failed to synthesize speech: \(error.localizedDescription)"
        }
    }

    private func generateInitialSentencesIfNeeded() async {
        guard canSynthesize, !hasGeneratedInitialSequence else { return }
        hasGeneratedInitialSequence = true

        for sentence in initialSentences {
            await synthesizeSpeech(from: sentence)

            if errorMessage != nil {
                break
            }
        }
    }
}
