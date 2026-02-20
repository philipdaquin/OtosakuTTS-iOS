import AVFoundation
import Foundation

@MainActor
final class AudioPlayer {
    enum AudioPlayerError: LocalizedError {
        case emptyBuffer
        case stepFailed(step: String, underlying: NSError)

        var errorDescription: String? {
            switch self {
            case .emptyBuffer:
                return "Audio buffer was empty."
            case let .stepFailed(step, underlying):
                return "Audio playback failed at '\(step)' (\(underlying.domain) code \(underlying.code)): \(underlying.localizedDescription)"
            }
        }
    }

    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var hasConfiguredAudioSession = false
    private var currentConnectionFormat: AVAudioFormat?

    init() {
        setupAudioEngine()
        print("Intialising the audio manager")
        registerForAudioSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func play(buffer: AVAudioPCMBuffer, completion: @escaping () -> Void) throws {
        guard buffer.frameLength > 0 else {
            throw AudioPlayerError.emptyBuffer
        }

        try performStep("configureAudioSessionIfNeeded") {
            try configureAudioSessionIfNeeded()
        }
        try performStep("ensureAudioSessionActive") {
            try ensureAudioSessionActive()
        }
        try performStep("ensureGraphConfigured") {
            ensureGraphConfigured(for: buffer.format)
        }
        try performStep("ensureEngineRunning") {
            try ensureEngineRunning()
        }

        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.reset()

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in
                completion()
            }
        }
        playerNode.play()
    }

    func play(buffer: AVAudioPCMBuffer) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try play(buffer: buffer) {
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
    }

    private func ensureGraphConfigured(for format: AVAudioFormat) {
        let shouldReconnect: Bool
        if let currentConnectionFormat {
            shouldReconnect = !currentConnectionFormat.isEqual(format)
        } else {
            shouldReconnect = true
        }

        guard shouldReconnect else { return }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        currentConnectionFormat = format
        audioEngine.prepare()

        print("Audio graph configured with format: \(format)")
    }

    private func configureAudioSessionIfNeeded() throws {
        guard !hasConfiguredAudioSession else { return }

        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
        } catch {
            let nsError = error as NSError
            print("Failed to set .spokenAudio mode: \(nsError.domain) code \(nsError.code). Retrying with simpler playback category.")

            do {
                try audioSession.setCategory(
                    .playback,
                    mode: .default,
                    options: [.allowBluetoothA2DP, .allowAirPlay]
                )
            } catch {
                let fallbackError = error as NSError
                print("Failed to set playback with options: \(fallbackError.domain) code \(fallbackError.code). Retrying without options.")
                try audioSession.setCategory(.playback, mode: .default, options: [])
            }
        }

        // This is a preference only; continue if hardware rejects it.
        do {
//            try audioSession.setPreferredSampleRate(22_050)
            
            try audioSession.setPreferredSampleRate(44_100)

            
        } catch {
            let nsError = error as NSError
            print("Failed to set preferred sample rate: \(nsError.domain) code \(nsError.code)")
        }

        hasConfiguredAudioSession = true
    }

    private func ensureAudioSessionActive() throws {
        try audioSession.setActive(true, options: [])
        print("Audio session active. Route: \(audioSession.currentRoute)")
    }

    private func ensureEngineRunning() throws {
        guard !audioEngine.isRunning else { return }
        audioEngine.prepare()
        try audioEngine.start()
        print("Audio engine started. Running: \(audioEngine.isRunning)")
    }

    private func performStep(_ step: String, _ block: () throws -> Void) throws {
        do {
            try block()
        } catch {
            let nsError = error as NSError
            print("AudioPlayer step '\(step)' failed: \(nsError.domain) code \(nsError.code) userInfo: \(nsError.userInfo)")
            throw AudioPlayerError.stepFailed(step: step, underlying: nsError)
        }
    }

    private func registerForAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else {
            return
        }

        switch type {
        case .began:
            playerNode.pause()
        case .ended:
            do {
                try ensureAudioSessionActive()
                try ensureEngineRunning()
                playerNode.play()
            } catch {
                // Keep interruption handling non-fatal.
            }
        @unknown default:
            break
        }
    }

    @objc private func handleMediaServicesReset() {
        hasConfiguredAudioSession = false
        currentConnectionFormat = nil

        audioEngine.stop()
        audioEngine.detach(playerNode)
        setupAudioEngine()

        do {
            try configureAudioSessionIfNeeded()
            try ensureAudioSessionActive()
        } catch {
            // Keep media service reset handling non-fatal.
        }
    }
}
