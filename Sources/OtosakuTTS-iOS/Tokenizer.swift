//
//  Tokenizer.swift
//  OtosakuTTS-iOS
//


import Foundation

public final class Tokenizer {
    // MARK: ––– Public Interface
    public init(tokensFile: URL, dictFile: URL) throws {
        self.tokenToId = try Tokenizer.loadTokens(tokensFile)
        self.idSpace   = tokenToId[" "]            // space
        self.idOOV     = tokenToId["<oov>"]        // unknown
        self.phonemeDB = try Tokenizer.loadDict(dictFile)
    }
    
    /// Encode string → array of indices
    public func encode(_ text: String) -> [Int] {
        var ids: [Int] = []
        let cleaned = normalizeText(text)

        let pattern = #"[A-Za-z]+(?:'[A-Za-z]+)?|[0-9]+(?:\.[0-9]+)?|[^A-Za-z0-9\s]|\s+"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))

        var previousWord: String?
        var nextWordIndex = 0
        let lowerWords = extractWords(from: cleaned)

        for m in matches {
            let token = String(cleaned[Range(m.range, in: cleaned)!])

            if token.trimmingCharacters(in: .whitespaces).isEmpty {
                append(" ", to: &ids)
                continue
            }

            if tokenToId[token] != nil {
                append(token, to: &ids)
                continue
            }

            if token.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil {
                let spoken = expandNumberToken(token)
                appendWordLikeToken(spoken, previousWord: previousWord, nextWord: nil, to: &ids)
                previousWord = spoken.lowercased()
                continue
            }

            if token.range(of: #"^[A-Za-z]+(?:'[A-Za-z]+)?$"#, options: .regularExpression) != nil {
                let nextWord = (nextWordIndex + 1 < lowerWords.count) ? lowerWords[nextWordIndex + 1] : nil
                appendWordLikeToken(token, previousWord: previousWord, nextWord: nextWord, to: &ids)
                previousWord = token.lowercased()
                nextWordIndex += 1
            }
        }
        // remove trailing spaces
        while ids.last == idSpace { _ = ids.popLast() }
        return ids
    }
    
    // MARK: ––– Private Part
    
    private let tokenToId: [String:Int]          // "token → id"
    private let phonemeDB: [String:[[String]]]   // JSON dictionary
    private let idSpace: Int?                    // space index
    private let idOOV:   Int?                    // <oov> index
    private let commonAbbreviations: [String:String] = [
        "mr.": "mister",
        "mrs.": "missus",
        "ms.": "miss",
        "dr.": "doctor",
        "st.": "saint",
        "jr.": "junior",
        "sr.": "senior",
        "etc.": "et cetera",
        "vs.": "versus"
    ]
    private let contractionExpansion: [String:String] = [
        "can't": "cannot",
        "won't": "will not",
        "n't": " not",
        "'re": " are",
        "'ve": " have",
        "'ll": " will",
        "'d": " would",
        "'m": " am"
    ]
    private let spelledLetterPhonemes: [Character:[String]] = [
        "a": ["EY1"], "b": ["B", "IY1"], "c": ["S", "IY1"], "d": ["D", "IY1"],
        "e": ["IY1"], "f": ["EH1", "F"], "g": ["JH", "IY1"], "h": ["EY1", "CH"],
        "i": ["AY1"], "j": ["JH", "EY1"], "k": ["K", "EY1"], "l": ["EH1", "L"],
        "m": ["EH1", "M"], "n": ["EH1", "N"], "o": ["OW1"], "p": ["P", "IY1"],
        "q": ["K", "Y", "UW1"], "r": ["AA1", "R"], "s": ["EH1", "S"], "t": ["T", "IY1"],
        "u": ["Y", "UW1"], "v": ["V", "IY1"], "w": ["D", "AH1", "B", "AH0", "L", "Y", "UW0"],
        "x": ["EH1", "K", "S"], "y": ["W", "AY1"], "z": ["Z", "IY1"]
    ]
    private let heteronymRules: [String: (String?, String?) -> Int] = [
        "read": { previous, next in
            let pastMarkers = Set(["yesterday", "ago", "last", "was", "were", "had"])
            let futureMarkers = Set(["to", "will", "can", "should", "might", "must"])
            if let previous, pastMarkers.contains(previous) { return 1 }   // past-tense pronunciation
            if let previous, futureMarkers.contains(previous) { return 0 }
            if let next, next == "book" || next == "chapter" { return 0 }
            return 0
        },
        "lead": { previous, next in
            if let next, next == "pipe" || next == "paint" || next == "poisoning" { return 1 } // metal
            if let previous, previous == "to" { return 0 } // verb
            return 0
        },
        "record": { previous, _ in
            if let previous, previous == "to" || previous == "will" || previous == "can" { return 1 } // verb
            return 0 // noun
        }
    ]
    
    private func append(_ tok: String, to arr: inout [Int]) {
        if let id = tokenToId[tok]        { arr.append(id) }
        else if let id = idOOV            { arr.append(id) }
        // otherwise ignore character
    }

    private func appendPhones(_ phones: [String], to arr: inout [Int]) {
        for phone in phones { append(phone, to: &arr) }
    }

    private func appendWordLikeToken(_ rawToken: String, previousWord: String?, nextWord: String?, to arr: inout [Int]) {
        let lowered = rawToken.lowercased()
        let cleanedWord = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        guard !cleanedWord.isEmpty else { return }

        if shouldSpellAsAcronym(rawToken) {
            appendAcronym(rawToken, to: &arr)
            return
        }

        if let prons = phonemeDB[cleanedWord], !prons.isEmpty {
            let selected = selectPronunciation(word: cleanedWord, pronunciations: prons, previousWord: previousWord, nextWord: nextWord)
            appendPhones(selected, to: &arr)
            return
        }

        if let expanded = expandContraction(cleanedWord), expanded != cleanedWord {
            let splitWords = expanded.split(separator: " ").map(String.init)
            for (i, item) in splitWords.enumerated() {
                let next = i + 1 < splitWords.count ? splitWords[i + 1] : nextWord
                appendWordLikeToken(item, previousWord: i == 0 ? previousWord : splitWords[i - 1], nextWord: next, to: &arr)
                if i + 1 < splitWords.count { append(" ", to: &arr) }
            }
            return
        }

        let guessed = guessPhones(for: cleanedWord)
        if guessed.isEmpty {
            for ch in cleanedWord { append(String(ch), to: &arr) }
        } else {
            appendPhones(guessed, to: &arr)
        }
    }

    private func normalizeText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "—", with: " , ")
            .replacingOccurrences(of: "–", with: " , ")
            .replacingOccurrences(of: "…", with: " ... ")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")

        for (abbr, expansion) in commonAbbreviations {
            normalized = normalized.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: abbr))",
                with: expansion,
                options: .regularExpression
            )
        }

        normalized = normalized.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }

    private func extractWords(from text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"[A-Za-z]+(?:'[A-Za-z]+)?"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return String(text[range]).lowercased()
        }
    }

    private func selectPronunciation(word: String, pronunciations: [[String]], previousWord: String?, nextWord: String?) -> [String] {
        if let chooser = heteronymRules[word] {
            let idx = chooser(previousWord, nextWord)
            if pronunciations.indices.contains(idx) {
                return pronunciations[idx]
            }
        }
        return pronunciations[0]
    }

    private func shouldSpellAsAcronym(_ token: String) -> Bool {
        if token.count <= 1 { return false }
        let hasUpper = token.contains(where: { $0.isUppercase })
        let hasLower = token.contains(where: { $0.isLowercase })
        if hasUpper && !hasLower { return true }
        if hasUpper && hasLower && token.first?.isLowercase == true { return true } // e.g. iOS
        return false
    }

    private func appendAcronym(_ token: String, to arr: inout [Int]) {
        let letters = token.lowercased().filter { $0.isLetter }
        for (idx, ch) in letters.enumerated() {
            if let phones = spelledLetterPhonemes[ch] {
                appendPhones(phones, to: &arr)
            } else {
                append(String(ch), to: &arr)
            }
            if idx + 1 < letters.count { append(" ", to: &arr) }
        }
    }

    private func expandContraction(_ lowered: String) -> String? {
        if let exact = contractionExpansion[lowered] { return exact }
        for (suffix, expansion) in contractionExpansion where lowered.hasSuffix(suffix) && suffix != lowered {
            return String(lowered.dropLast(suffix.count)) + expansion
        }
        return lowered
    }

    private func expandNumberToken(_ token: String) -> String {
        guard token.contains(".") else {
            return speakWholeNumber(token) ?? token
        }
        let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count != 2 { return token }
        let left = speakWholeNumber(parts[0]) ?? parts[0]
        let right = parts[1].map { String($0) }.compactMap { digitWord($0) }.joined(separator: " ")
        return right.isEmpty ? left : "\(left) point \(right)"
    }

    private func speakWholeNumber(_ digits: String) -> String? {
        guard let value = Int(digits), value >= 0 else { return nil }
        if value == 0 { return "zero" }
        if value < 20 {
            return smallNumberWord(value)
        }
        if value < 100 {
            let tens = value / 10
            let remainder = value % 10
            let tensWord = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"][tens]
            return remainder == 0 ? tensWord : "\(tensWord) \(smallNumberWord(remainder))"
        }
        if value < 1000 {
            let hundreds = value / 100
            let remainder = value % 100
            let head = "\(smallNumberWord(hundreds)) hundred"
            return remainder == 0 ? head : "\(head) \(speakWholeNumber(String(remainder))!)"
        }
        if value < 1_000_000 {
            let thousands = value / 1000
            let remainder = value % 1000
            let head = "\(speakWholeNumber(String(thousands))!) thousand"
            return remainder == 0 ? head : "\(head) \(speakWholeNumber(String(remainder))!)"
        }
        return nil
    }

    private func smallNumberWord(_ n: Int) -> String {
        [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
            "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
            "seventeen", "eighteen", "nineteen"
        ][n]
    }

    private func digitWord(_ ch: String) -> String? {
        switch ch {
        case "0": return "zero"
        case "1": return "one"
        case "2": return "two"
        case "3": return "three"
        case "4": return "four"
        case "5": return "five"
        case "6": return "six"
        case "7": return "seven"
        case "8": return "eight"
        case "9": return "nine"
        default: return nil
        }
    }

    private func guessPhones(for word: String) -> [String] {
        let clusters: [(String, [String])] = [
            ("tion", ["SH", "AH0", "N"]),
            ("sion", ["ZH", "AH0", "N"]),
            ("ch", ["CH"]),
            ("sh", ["SH"]),
            ("th", ["TH"]),
            ("ph", ["F"]),
            ("ng", ["NG"]),
            ("qu", ["K", "W"]),
            ("ck", ["K"])
        ]

        var phones: [String] = []
        var index = word.startIndex

        func addVowel(_ letter: Character, stress: String = "1") {
            switch letter {
            case "a": phones.append("AE\(stress)")
            case "e": phones.append("EH\(stress)")
            case "i": phones.append("IH\(stress)")
            case "o": phones.append("OW\(stress)")
            case "u": phones.append("AH\(stress)")
            case "y": phones.append("IY\(stress)")
            default: break
            }
        }

        while index < word.endIndex {
            let remaining = String(word[index...])
            var matched = false
            for (cluster, clusterPhones) in clusters {
                if remaining.hasPrefix(cluster) {
                    phones.append(contentsOf: clusterPhones)
                    index = word.index(index, offsetBy: cluster.count)
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
            case "y", "a", "e", "i", "o", "u": addVowel(ch)
            case "z": phones.append("Z")
            default: break
            }
            index = word.index(after: index)
        }
        return phones
    }
    
    private static func loadTokens(_ url: URL) throws -> [String:Int] {
        let lines: [String]
        do {
            lines = try String(contentsOf: url)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
        } catch {
            throw OtosakuTTSError.invalidTokensFile
        }
        var map = [String:Int]()
        for (i,t) in lines.enumerated() { map[t] = i }
        return map
    }
    private static func loadDict(_ url: URL) throws -> [String:[[String]]] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw OtosakuTTSError.invalidDictionaryFile
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String:[[String]]] else {
            throw OtosakuTTSError.invalidDictionaryFile
        }
        return obj
    }
}
