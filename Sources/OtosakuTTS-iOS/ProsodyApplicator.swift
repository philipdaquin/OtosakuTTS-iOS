//
//  ProsodyApplicator.swift
//  OtosakuTTS-iOS
//
//  Applies per-word ProsodyHints to FastPitch's duration and pitch tensors
//  after inference but before the vocoder.
//
//  Usage
//  ─────
//  After FastPitch returns duration and pitch arrays (one element per input
//  phoneme), map each phoneme back to its source word index, then call:
//
//      let applicator = ProsodyApplicator()
//      applicator.apply(hints: hints,
//                       wordToPhonemeRanges: ranges,
//                       toPitches: &pitches,
//                       durations: &durations)
//
//  Note: ProsodyApplicator requires FastPitch to expose separate "pitch" and
//  "duration" output tensors. The current bundled model may only expose "spec".
//  The struct is fully functional and ready to wire in once those tensors are
//  available.
//

import Foundation

public struct ProsodyApplicator: Sendable {

    public init() {}

    /// Apply hints using word-to-phoneme range mappings.
    ///
    /// - Parameters:
    ///   - hints:               Word-index → ProsodyHint dictionary from ProsodyParser.
    ///   - wordToPhonemeRanges: Array where index `i` gives the phoneme-index range
    ///                          that corresponds to word `i`.
    ///   - pitches:             Mutable pitch array (one value per phoneme).
    ///   - durations:           Mutable duration array (one value per phoneme).
    public func apply(
        hints: [Int: ProsodyHint],
        wordToPhonemeRanges: [Range<Int>],
        toPitches pitches: inout [Float],
        durations: inout [Float]
    ) {
        for (wordIdx, hint) in hints {
            guard wordIdx < wordToPhonemeRanges.count else { continue }
            let range = wordToPhonemeRanges[wordIdx]

            for i in range {
                guard i < pitches.count   else { continue }
                guard i < durations.count else { continue }

                // Apply pitch scale and semitone offset
                if hint.pitchScale != 1.0 {
                    pitches[i] *= hint.pitchScale
                }
                if hint.pitchOffsetSemitones != 0.0 {
                    // Convert semitone offset to Hz multiplicative factor at current pitch
                    let factor = powf(2.0, hint.pitchOffsetSemitones / 12.0)
                    pitches[i] *= factor
                }

                // Apply duration scale
                if hint.durationScale != 1.0 {
                    durations[i] *= hint.durationScale
                }
            }
        }
    }

    /// Simplified overload when phoneme ranges are not available — applies hints
    /// uniformly across the whole pitch/duration arrays.
    public func apply(
        hints: [Int: ProsodyHint],
        toPitches pitches: inout [Float],
        durations: inout [Float]
    ) {
        guard !hints.isEmpty else { return }

        // Merge all hints into a single aggregate
        let merged = hints.values.reduce(ProsodyHint.identity) { $0.merged(with: $1) }

        if merged.pitchScale != 1.0 {
            for i in pitches.indices { pitches[i] *= merged.pitchScale }
        }
        if merged.pitchOffsetSemitones != 0.0 {
            let factor = powf(2.0, merged.pitchOffsetSemitones / 12.0)
            for i in pitches.indices { pitches[i] *= factor }
        }
        if merged.durationScale != 1.0 {
            for i in durations.indices { durations[i] *= merged.durationScale }
        }
    }
}
