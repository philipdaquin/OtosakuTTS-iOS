//
//  Phonemizer.swift
//  OtosakuTTS-iOS
//
//  Protocol and concrete implementations for grapheme-to-phoneme conversion.
//
//  CMUDictPhonemizer (Option B from the design doc):
//    1. CMU Pronouncing Dictionary lookup with heteronym selection
//    2. Roman-numeral detection
//    3. Acronym spelling via letter-name phonemes
//    4. Contraction expansion
//    5. Rule-based G2P fallback for truly unknown words
//

import Foundation

// MARK: - Protocol

/// Converts a single word token into a sequence of ARPAbet phoneme strings.
public protocol Phonemizer: Sendable {
    func phonemize(_ word: String, previousWord: String?, nextWord: String?) -> [String]
}

// MARK: - CMUDictPhonemizer

public struct CMUDictPhonemizer: Phonemizer {

    // MARK: - Private Data

    private let phonemeDB: [String: [[String]]]  // word → [[phoneme]]

    // MARK: - Init

    public init(dict: [String: [[String]]]) {
        self.phonemeDB = dict
    }

    // MARK: - Public

    public func phonemize(_ word: String, previousWord: String?, nextWord: String?) -> [String] {
        phonemizeWord(word, prev: previousWord, next: nextWord)
    }

    // MARK: - Core Pipeline

    private func phonemizeWord(_ rawToken: String, prev: String?, next: String?) -> [String] {
        let lowered     = rawToken.lowercased()
        let cleanedWord = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        guard !cleanedWord.isEmpty else { return [] }

        // 1. Roman numeral  (e.g. XIV → 14 → "fourteen")
        if shouldTreatAsRomanNumeral(rawToken), let romanValue = romanNumeralValue(rawToken) {
            let spoken = TextNormalizer().speakWholeNumber(String(romanValue)) ?? cleanedWord
            return phonemizePhrase(spoken, firstPrev: prev, lastNext: next)
        }

        // 2. Acronym  (e.g. NASA, iOS)
        if shouldSpellAsAcronym(rawToken) {
            return phonemizeAcronym(rawToken)
        }

        // 3. Single uppercase letter → read as letter name  (for "WWDC → W W D C" overrides)
        if rawToken.count == 1, let ch = rawToken.first, ch.isUppercase,
           phonemeDB[lowered] == nil {
            return spelledLetterPhonemes[Character(lowered)] ?? []
        }

        // 4. CMUdict lookup with heteronym selection
        if let prons = phonemeDB[cleanedWord], !prons.isEmpty {
            let idx = selectPronunciationIndex(for: cleanedWord, prev: prev, next: next)
            return prons.indices.contains(idx) ? prons[idx] : prons[0]
        }

        // 5. Contraction expansion  (e.g. can't → cannot)
        if let expanded = expandContraction(cleanedWord), expanded != cleanedWord {
            return phonemizePhrase(expanded, firstPrev: prev, lastNext: next)
        }

        // 6. Rule-based G2P fallback
        let guessed = guessPhones(for: cleanedWord)
        return guessed.isEmpty ? cleanedWord.map { String($0) } : guessed
    }

    // MARK: - Phrase Phonemizer (for multi-word expansions)

    private func phonemizePhrase(_ phrase: String, firstPrev: String?, lastNext: String?) -> [String] {
        let words = phrase.split(separator: " ").map(String.init)
        var out: [String] = []
        for (i, w) in words.enumerated() {
            if i > 0 { out.append(" ") }
            let prevWord = i == 0 ? firstPrev : words[i - 1]
            let nextWord = i + 1 < words.count ? words[i + 1] : lastNext
            out.append(contentsOf: phonemizeWord(w, prev: prevWord, next: nextWord))
        }
        return out
    }

    // MARK: - Heteronym Selection

    private func selectPronunciationIndex(for word: String, prev: String?, next: String?) -> Int {
        switch word {
        case "read":
            let pastMarkers   = Set(["yesterday", "ago", "last", "was", "were", "had"])
            let futureMarkers = Set(["to", "will", "can", "should", "might", "must"])
            if let p = prev, pastMarkers.contains(p)   { return 1 }
            if let p = prev, futureMarkers.contains(p) { return 0 }
            if let n = next, n == "book" || n == "chapter" { return 0 }
            return 0
        case "lead":
            if let n = next, ["pipe", "paint", "poisoning"].contains(n) { return 1 }
            if let p = prev, p == "to" { return 0 }
            return 0
        case "record":
            if let p = prev, ["to", "will", "can"].contains(p) { return 1 }
            return 0
        default:
            return 0
        }
    }

    // MARK: - Acronym Detection & Spelling

    private func shouldSpellAsAcronym(_ token: String) -> Bool {
        guard token.count > 1 else { return false }
        let hasUpper = token.contains { $0.isUppercase }
        let hasLower = token.contains { $0.isLowercase }
        if hasUpper && !hasLower { return true }                          // ALL-CAPS: NASA
        if hasUpper && hasLower && token.first?.isLowercase == true { return true } // camelCase: iOS
        return false
    }

    private func phonemizeAcronym(_ token: String) -> [String] {
        let letters = token.lowercased().filter { $0.isLetter }
        var out: [String] = []
        for (idx, ch) in letters.enumerated() {
            if idx > 0 { out.append(" ") }
            out.append(contentsOf: spelledLetterPhonemes[ch] ?? [String(ch)])
        }
        return out
    }

    // MARK: - Roman Numeral Detection

    private func shouldTreatAsRomanNumeral(_ token: String) -> Bool {
        guard token.count >= 2, token == token.uppercased() else { return false }
        let romanSet = CharacterSet(charactersIn: "IVXLCDM")
        return token.unicodeScalars.allSatisfy { romanSet.contains($0) }
    }

    private func romanNumeralValue(_ token: String) -> Int? {
        let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50,
                                        "C": 100, "D": 500, "M": 1000]
        var total = 0; var prev = 0
        for ch in token.uppercased().reversed() {
            guard let v = values[ch] else { return nil }
            total += v < prev ? -v : v
            prev = v
        }
        return total > 0 ? total : nil
    }

    // MARK: - Contraction Expansion

    private let contractionExpansion: [String: String] = [
        "can't": "cannot",   "won't": "will not",
        "n't":   " not",     "'re":   " are",
        "'ve":   " have",    "'ll":   " will",
        "'d":    " would",   "'m":    " am"
    ]

    private func expandContraction(_ lowered: String) -> String? {
        if let exact = contractionExpansion[lowered] { return exact }
        for (suffix, expansion) in contractionExpansion
            where lowered.hasSuffix(suffix) && suffix != lowered {
            return String(lowered.dropLast(suffix.count)) + expansion
        }
        return lowered
    }

    // MARK: - Rule-Based G2P Fallback

    private func guessPhones(for word: String) -> [String] {
        // Ordered digraph clusters — tried before single-character rules
        let clusters: [(String, [String])] = [
            ("tion", ["SH", "AH0", "N"]),
            ("sion", ["ZH", "AH0", "N"]),
            ("ch",   ["CH"]),
            ("sh",   ["SH"]),
            ("th",   ["TH"]),
            ("ph",   ["F"]),
            ("ng",   ["NG"]),
            ("qu",   ["K", "W"]),
            ("ck",   ["K"])
        ]

        var phones: [String] = []
        var index = word.startIndex

        while index < word.endIndex {
            let remaining = String(word[index...])
            var matched   = false

            for (cluster, clusterPhones) in clusters {
                if remaining.hasPrefix(cluster) {
                    phones.append(contentsOf: clusterPhones)
                    index   = word.index(index, offsetBy: cluster.count)
                    matched = true
                    break
                }
            }
            if matched { continue }

            let ch = word[index]
            switch ch {
            case "b": phones.append("B")
            case "c": phones.append("K")
            case "d": phones.append("D")
            case "f": phones.append("F")
            case "g": phones.append("G")
            case "h": phones.append("HH")
            case "j": phones.append("JH")
            case "k": phones.append("K")
            case "l": phones.append("L")
            case "m": phones.append("M")
            case "n": phones.append("N")
            case "p": phones.append("P")
            case "q": phones.append("K")
            case "r": phones.append("R")
            case "s": phones.append("S")
            case "t": phones.append("T")
            case "v": phones.append("V")
            case "w": phones.append("W")
            case "x": phones.append(contentsOf: ["K", "S"])
            case "z": phones.append("Z")
            case "a": phones.append("AE1")
            case "e": phones.append("EH1")
            case "i": phones.append("IH1")
            case "o": phones.append("OW1")
            case "u": phones.append("AH1")
            case "y": phones.append("IY1")
            default:  break
            }
            index = word.index(after: index)
        }
        return phones
    }

    // MARK: - Letter-Name Phonemes (ARPAbet)

    let spelledLetterPhonemes: [Character: [String]] = [
        "a": ["EY1"],                         "b": ["B",  "IY1"],
        "c": ["S",  "IY1"],                   "d": ["D",  "IY1"],
        "e": ["IY1"],                         "f": ["EH1","F"],
        "g": ["JH", "IY1"],                   "h": ["EY1","CH"],
        "i": ["AY1"],                         "j": ["JH", "EY1"],
        "k": ["K",  "EY1"],                   "l": ["EH1","L"],
        "m": ["EH1","M"],                     "n": ["EH1","N"],
        "o": ["OW1"],                         "p": ["P",  "IY1"],
        "q": ["K",  "Y",  "UW1"],             "r": ["AA1","R"],
        "s": ["EH1","S"],                     "t": ["T",  "IY1"],
        "u": ["Y",  "UW1"],                   "v": ["V",  "IY1"],
        "w": ["D",  "AH1","B","AH0","L","Y","UW0"],
        "x": ["EH1","K",  "S"],               "y": ["W",  "AY1"],
        "z": ["Z",  "IY1"]
    ]
}
