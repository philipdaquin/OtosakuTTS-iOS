// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import CoreML
import AVFoundation



public enum FastPitchSpeaker: Int, CaseIterable, Identifiable {
    case emma     = 92      // female
    case james    = 6097    // male
    case daniel   = 9017    // male
    case michael  = 6670    // male
    case ryan     = 6671    // male
    case sophia   = 8051    // female
    case claire   = 9136    // female
    case olivia   = 11614   // female
    case celine   = 11697   // female
    case grace    = 12787   // female

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .emma:    return "Emma"
        case .james:   return "James"
        case .daniel:  return "Daniel"
        case .michael: return "Michael"
        case .ryan:    return "Ryan"
        case .sophia:  return "Sophia"
        case .claire:  return "Claire"
        case .olivia:  return "Olivia"
        case .celine:  return "Celine"
        case .grace:   return "Grace"
        }
    }

    public var gender: Gender {
        switch self {
        case .james, .daniel, .michael, .ryan:
            return .male
        case .emma, .sophia, .claire, .olivia, .celine, .grace:
            return .female
        }
    }

    public var description: String {
        switch self {
        case .emma:    return "Warm & clear"
        case .james:   return "Confident & smooth"
        case .daniel:  return "Deep & measured"
        case .michael: return "Crisp & energetic"
        case .ryan:    return "Natural & conversational"
        case .sophia:  return "Bright & expressive"
        case .claire:  return "Soft & articulate"
        case .olivia:  return "Friendly & warm"
        case .celine:  return "Rich & refined"
        case .grace:   return "Calm & soothing"
        }
    }

    public static var males: [FastPitchSpeaker] { allCases.filter { $0.gender == .male } }
    public static var females: [FastPitchSpeaker] { allCases.filter { $0.gender == .female } }

    public enum Gender {
        case male, female
        public var displayName: String {
            switch self {
            case .male:   return "Male"
            case .female: return "Female"
            }
        }
    }
}
// MARK: - Config

public struct MultispeakerTTSConfig {
    /// Which voice to use.
    public var speaker: FastPitchSpeaker = .emma
    /// Silence in seconds after a piece cut at punctuation, when the text is over the model's input limit.
    public var splitPause: TimeInterval = 0.15

    public init(speaker: FastPitchSpeaker = .emma, splitPause: TimeInterval = 0.15) {
        self.speaker = speaker
        self.splitPause = splitPause
    }
}


public class OtosakuTTS {
    
    private let fastPitch: MLModel
    private let hifiGAN: MLModel
    private let tokenizer: Tokenizer
    private let audioFormat: AVAudioFormat
    private let fastPitchInputFeatureNames: Set<String>
    
    public init(modelDirectoryURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        
        do {
            let fastPitchURL = try Self.modelURL(named: "FastPitch", in: modelDirectoryURL)
            fastPitch = try MLModel(
                contentsOf: fastPitchURL,
                configuration: configuration
            )
        } catch {
            throw OtosakuTTSError.modelLoadingFailed("FastPitch")
        }
        
        do {
            let hifiGanURL = try Self.modelURL(named: "HiFiGan", in: modelDirectoryURL)
            hifiGAN = try MLModel(
                contentsOf: hifiGanURL,
                configuration: configuration
            )
        } catch {
            throw OtosakuTTSError.modelLoadingFailed("HiFiGAN")
        }
        
        do {
            tokenizer = try Tokenizer(
                tokensFile: modelDirectoryURL.appendingPathComponent("tokens.txt"),
                dictFile: modelDirectoryURL.appendingPathComponent("cmudict.json")
            )
        } catch {
            throw OtosakuTTSError.tokenizerInitializationFailed(error.localizedDescription)
        }
        
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22_050,
            channels: 1,
            interleaved: false
        ) else {
            throw OtosakuTTSError.audioFormatCreationFailed
        }
        audioFormat = format

        fastPitchInputFeatureNames = Set(fastPitch.modelDescription.inputDescriptionsByName.keys)
    }
    
    public func generate(text: String) throws -> AVAudioPCMBuffer {
        try generate(text: text, config: MultispeakerTTSConfig())
    }
    
    private func makeMultiArray(from ints: [Int]) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: [1, NSNumber(value: ints.count)], dataType: .int32)
        for (i, v) in ints.enumerated() { 
            arr[i] = NSNumber(value: Int32(v)) 
        }
        return arr
    }

    private static func modelURL(named modelName: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let compiledURL = directory.appendingPathComponent("\(modelName).mlmodelc")
        if fileManager.fileExists(atPath: compiledURL.path) {
            return compiledURL
        }

        let packageURL = directory.appendingPathComponent("\(modelName).mlpackage")
        if fileManager.fileExists(atPath: packageURL.path) {
            return packageURL
        }

        throw OtosakuTTSError.modelLoadingFailed(modelName)
    }
    
    private func createAudioBuffer(from array: MLMultiArray) throws -> AVAudioPCMBuffer {
        let length = array.count
        var floats = [Float](repeating: 0, count: length)
        for i in 0..<length { 
            floats[i] = array[i].floatValue 
        }
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(length)
        ) else {
            throw OtosakuTTSError.audioBufferCreationFailed
        }
        
        buffer.frameLength = buffer.frameCapacity
        guard let channelData = buffer.floatChannelData else {
            throw OtosakuTTSError.audioBufferCreationFailed
        }
        channelData.pointee.update(from: &floats, count: length)
        
        return buffer
    }
}


extension OtosakuTTS {

    /// Core ML takes 2...240 tokens per prediction. Text over that is split (after the last
    /// punctuation that fits, else at a word) and the pieces are joined into one buffer.
    public static let maxInputTokens = InputSplitter.maxTokens

    /// Token count the model would see for `text`.
    public func tokenCount(for text: String) -> Int {
        tokenizer.encode(text).count
    }

    /// Generate speech with explicit speaker selection.
    /// - Throws: `OtosakuTTSError.inputTooLong` when one word alone is over `maxInputTokens`.
    public func generate(text: String, config: MultispeakerTTSConfig) throws -> AVAudioPCMBuffer {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OtosakuTTSError.emptyInput
        }

        let pieces = InputSplitter.pieces(for: text, countTokens: { tokenizer.encode($0).count })
        var samples: [Float] = []
        for (index, piece) in pieces.enumerated() {
            let phoneIds = tokenizer.encode(piece.text)
            guard phoneIds.count <= InputSplitter.maxTokens else {
                throw OtosakuTTSError.inputTooLong(tokens: phoneIds.count, max: InputSplitter.maxTokens)
            }
            samples += try predictSamples(phoneIds: phoneIds, speaker: config.speaker)
            if index < pieces.count - 1, piece.endsOnPunctuation, config.splitPause > 0 {
                samples += [Float](repeating: 0, count: Int(config.splitPause * 44_100))
            }
        }
        return try createAudioBuffer44k(from: samples)
    }

    private func predictSamples(phoneIds: [Int], speaker: FastPitchSpeaker) throws -> [Float] {
        let phones = try makeMultiArray(from: phoneIds)

        // Speaker ID input — shape [1], int32
        let speakerArray = try MLMultiArray(shape: [1], dataType: .int32)
        speakerArray[0]  = NSNumber(value: Int32(speaker.rawValue))

        let fastPitchInput = try MLDictionaryFeatureProvider(dictionary: [
            "x":       phones,
            "speaker": speakerArray
        ])
        let fastPitchOutput = try fastPitch.prediction(from: fastPitchInput)

        guard let spec = fastPitchOutput.featureValue(for: "spec")?.multiArrayValue else {
            throw OtosakuTTSError.specGenerationFailed
        }

        let hifiGANInput = try MLDictionaryFeatureProvider(dictionary: ["x": spec])
        let hifiGANOutput = try hifiGAN.prediction(from: hifiGANInput)

        guard let waveform = hifiGANOutput.featureValue(for: "waveform")?.multiArrayValue else {
            throw OtosakuTTSError.waveformGenerationFailed
        }

        var floats = [Float](repeating: 0, count: waveform.count)
        for i in 0..<waveform.count { floats[i] = waveform[i].floatValue }
        return floats
    }

    /// Convenience — generate with just a speaker.
    public func generate(text: String, speaker: FastPitchSpeaker) throws -> AVAudioPCMBuffer {
        try generate(text: text, config: MultispeakerTTSConfig(speaker: speaker))
    }

    // 44100 Hz buffer for the multispeaker models
    private func createAudioBuffer44k(from samples: [Float]) throws -> AVAudioPCMBuffer {
        let length = samples.count
        var floats = samples

        guard let format44k = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ) else {
            throw OtosakuTTSError.audioFormatCreationFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format44k,
            frameCapacity: AVAudioFrameCount(length)
        ) else {
            throw OtosakuTTSError.audioBufferCreationFailed
        }

        buffer.frameLength = buffer.frameCapacity
        guard let channelData = buffer.floatChannelData else {
            throw OtosakuTTSError.audioBufferCreationFailed
        }
        channelData.pointee.update(from: &floats, count: length)
        return buffer
    }
}
