//
//  ProsodyParser.swift
//  OtosakuTTS-iOS
//
//  Parses an SSML-lite subset of inline markup, strips tags from the text,
//  and returns a per-word-index hint dictionary for use by ProsodyApplicator.
//
//  Supported tags
//  ──────────────
//  <emphasis>…</emphasis>                 pitch ×1.2, duration ×1.1
//  <emphasis level="strong">…</emphasis>  pitch ×1.4, duration ×1.2
//  <emphasis level="reduced">…</emphasis> pitch ×0.8, duration ×0.9
//  <break time="300ms"/>                  insert silence (ms)
//  <break time="0.5s"/>                   insert silence (seconds → ms)
//  <rate slow>…</rate>                    duration ×1.3
//  <rate fast>…</rate>                    duration ×0.8
//  <pitch high>…</pitch>                  pitch offset +2 semitones
//  <pitch low>…</pitch>                   pitch offset −2 semitones
//

import Foundation

// MARK: - ProsodyHint

public struct ProsodyHint: Sendable {
    public var pitchScale:         Float = 1.0
    public var durationScale:      Float = 1.0
    public var pitchOffsetSemitones: Float = 0.0
    public var insertSilenceMs:    Int   = 0

    public static let identity = ProsodyHint()

    /// Merge another hint on top of this one (multiplicative for scales, additive for offsets).
    func merged(with other: ProsodyHint) -> ProsodyHint {
        var result = self
        result.pitchScale          *= other.pitchScale
        result.durationScale       *= other.durationScale
        result.pitchOffsetSemitones += other.pitchOffsetSemitones
        result.insertSilenceMs     += other.insertSilenceMs
        return result
    }
}

// MARK: - ProsodyParser

public struct ProsodyParser: Sendable {

    public init() {}

    /// Parse `text`, strip all recognised tags, and return:
    ///   - `cleanText`: the tag-free text ready for phonemization
    ///   - `hints`: a mapping from word index (0-based) to the combined ProsodyHint for that word
    public func parse(_ text: String) -> (cleanText: String, hints: [Int: ProsodyHint]) {
        var hints: [Int: ProsodyHint] = [:]
        let clean = processSegment(text, activeHints: [], wordCounter: &hints, wordIndex: Counter())
        return (cleanText: clean, hints: hints)
    }

    // MARK: - Private

    private class Counter { var value: Int = 0 }

    private func processSegment(
        _ text: String,
        activeHints: [ProsodyHint],
        wordCounter: inout [Int: ProsodyHint],
        wordIndex: Counter
    ) -> String {
        // Quick exit if no tags
        guard text.contains("<") else {
            if !activeHints.isEmpty {
                let merged = activeHints.reduce(ProsodyHint.identity) { $0.merged(with: $1) }
                let words  = wordCount(in: text)
                for i in 0..<words {
                    let idx = wordIndex.value + i
                    wordCounter[idx] = wordCounter[idx]?.merged(with: merged) ?? merged
                }
                wordIndex.value += words
            } else {
                wordIndex.value += wordCount(in: text)
            }
            return stripRemainingTags(text)
        }

        // Find the first tag
        guard let tagRange = firstTagRange(in: text) else {
            // No valid tag found — treat as plain text
            return processSegment(text.replacingOccurrences(of: "<", with: ""),
                                  activeHints: activeHints,
                                  wordCounter: &wordCounter,
                                  wordIndex: wordIndex)
        }

        var result   = ""
        let before   = String(text[text.startIndex..<tagRange.lowerBound])
        let tagStr   = String(text[tagRange])
        let after    = String(text[tagRange.upperBound...])

        // Process text before the tag
        result += processSegment(before,
                                 activeHints: activeHints,
                                 wordCounter: &wordCounter,
                                 wordIndex: wordIndex)

        // Self-closing tags (<break …/>)
        if tagStr.hasSuffix("/>") {
            if let hint = parseSelfClosingTag(tagStr) {
                let idx = wordIndex.value
                wordCounter[idx] = wordCounter[idx]?.merged(with: hint) ?? hint
            }
            result += processSegment(after,
                                     activeHints: activeHints,
                                     wordCounter: &wordCounter,
                                     wordIndex: wordIndex)
            return result
        }

        // Opening tag — find matching close tag and recurse
        let tagName = extractTagName(from: tagStr)
        let hint    = parseOpeningTag(tagStr)
        let newHints = hint.map { activeHints + [$0] } ?? activeHints

        let closePattern = "</\(tagName)>"
        if let closeRange = after.range(of: closePattern, options: .caseInsensitive) {
            let inner = String(after[after.startIndex..<closeRange.lowerBound])
            let rest  = String(after[closeRange.upperBound...])
            result += processSegment(inner,
                                     activeHints: newHints,
                                     wordCounter: &wordCounter,
                                     wordIndex: wordIndex)
            result += processSegment(rest,
                                     activeHints: activeHints,
                                     wordCounter: &wordCounter,
                                     wordIndex: wordIndex)
        } else {
            // No closing tag — treat rest as inside the hint
            result += processSegment(after,
                                     activeHints: newHints,
                                     wordCounter: &wordCounter,
                                     wordIndex: wordIndex)
        }

        return result
    }

    // MARK: - Tag Parsing

    private func firstTagRange(in text: String) -> Range<String.Index>? {
        guard let lt = text.firstIndex(of: "<") else { return nil }
        guard let gt = text[lt...].firstIndex(of: ">") else { return nil }
        return lt..<text.index(after: gt)
    }

    private func extractTagName(from tag: String) -> String {
        let inner = tag.trimmingCharacters(in: CharacterSet(charactersIn: "<>/"))
        return inner.split(separator: " ").first.map(String.init) ?? inner
    }

    private func parseSelfClosingTag(_ tag: String) -> ProsodyHint? {
        // <break time="300ms"/> or <break time="0.5s"/>
        guard tag.lowercased().contains("break") else { return nil }
        var hint = ProsodyHint()
        if let msRange  = tag.range(of: #"time="([0-9]+(?:\.[0-9]+)?)(ms|s)""#, options: .regularExpression) {
            let part    = String(tag[msRange])
            if let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)(ms|s)"#),
               let m = regex.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)) {
                let numStr = Range(m.range(at: 1), in: part).map { String(part[$0]) } ?? ""
                let unit   = Range(m.range(at: 2), in: part).map { String(part[$0]) } ?? ""
                if let v = Double(numStr) {
                    hint.insertSilenceMs = unit == "ms" ? Int(v) : Int(v * 1000)
                }
            }
        }
        return hint
    }

    private func parseOpeningTag(_ tag: String) -> ProsodyHint? {
        let lower = tag.lowercased()
        var hint  = ProsodyHint()

        if lower.contains("emphasis") {
            if lower.contains("level=\"strong\"") {
                hint.pitchScale    = 1.4
                hint.durationScale = 1.2
            } else if lower.contains("level=\"reduced\"") {
                hint.pitchScale    = 0.8
                hint.durationScale = 0.9
            } else {
                hint.pitchScale    = 1.2
                hint.durationScale = 1.1
            }
            return hint
        }

        if lower.contains("<rate") {
            if lower.contains("slow") { hint.durationScale = 1.3 }
            else if lower.contains("fast") { hint.durationScale = 0.8 }
            else { return nil }
            return hint
        }

        if lower.contains("<pitch") {
            if lower.contains("high") { hint.pitchOffsetSemitones =  2.0 }
            else if lower.contains("low") { hint.pitchOffsetSemitones = -2.0 }
            else { return nil }
            return hint
        }

        return nil
    }

    // MARK: - Helpers

    private func wordCount(in text: String) -> Int {
        let pattern = #"[A-Za-z]+"#
        let regex   = try? NSRegularExpression(pattern: pattern)
        return regex?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }

    private func stripRemainingTags(_ text: String) -> String {
        (try? NSRegularExpression(pattern: #"<[^>]+>"#))
            .map { $0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "") }
            ?? text
    }
}
