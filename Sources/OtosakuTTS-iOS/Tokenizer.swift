//
//  Tokenizer.swift
//  OtosakuTTS-iOS
//
//  Full text → token-ID pipeline for FastPitch CoreML inference.
//
//  Architecture:
//    Raw Text
//      → TextNormalizer       (numbers, dates, abbreviations, symbols)
//      → PronunciationDict    (custom word-level overrides)
//      → ProsodyParser        (optional SSML-lite markup)
//      → word tokenisation
//      → CMUDictPhonemizer    (CMUdict lookup + rule-based G2P fallback)
//      → SymbolEncoder        (phoneme strings → token IDs)
//      → TokenizerOutput

import Foundation

// MARK: - Output

public struct TokenizerOutput: Sendable {
    /// Integer token IDs ready for the FastPitch CoreML model input tensor.
    public let tokenIDs: [Int]
    /// Per-word prosody hints produced by ProsodyParser (empty if parseProsody is false).
    public let prosodyHints: [Int: ProsodyHint]
}

// MARK: - Config

public struct TokenizerConfig: Sendable {
    public var normalizer:        TextNormalizer   = .init()
    public var pronunciationDict: PronunciationDict = .init()
    /// When true, `<emphasis>`, `<break>`, `<rate>`, and `<pitch>` tags are parsed and stripped.
    public var parseProsody:      Bool             = false

    public init() {}
}

// MARK: - Tokenizer

public struct Tokenizer: Sendable {

    // MARK: - Private State

    private let tokenToId:        [String: Int]
    private let idSpace:          Int?
    private let idOOV:            Int?
    private let normalizer:       TextNormalizer
    private let pronunciationDict: PronunciationDict
    private let phonemizer:       CMUDictPhonemizer
    private let prosodyParser:    ProsodyParser
    private let parseProsody:     Bool

    // MARK: - Init

    /// Primary initialiser — loads token vocabulary and CMU Pronouncing Dictionary from disk.
    public init(
        tokensFile: URL,
        dictFile:   URL,
        config:     TokenizerConfig = .init()
    ) throws {
        self.tokenToId        = try Tokenizer.loadTokens(tokensFile)
        let phonemeDB         = try Tokenizer.loadDict(dictFile)
        self.idSpace          = tokenToId[" "]
        self.idOOV            = tokenToId["<oov>"]
        self.normalizer       = config.normalizer
        self.pronunciationDict = config.pronunciationDict
        self.phonemizer       = CMUDictPhonemizer(dict: phonemeDB)
        self.prosodyParser    = ProsodyParser()
        self.parseProsody     = config.parseProsody
    }

    // MARK: - Public API

    /// Full pipeline → returns token IDs plus optional prosody hints.
    public func tokenize(_ text: String) -> TokenizerOutput {
        var normalizedText = normalizer.normalize(text)
        normalizedText     = pronunciationDict.apply(normalizedText)

        var prosodyHints: [Int: ProsodyHint] = [:]
        if parseProsody {
            let parsed     = prosodyParser.parse(normalizedText)
            normalizedText = parsed.cleanText
            prosodyHints   = parsed.hints
        }

        let ids = encodeNormalized(normalizedText)
        return TokenizerOutput(tokenIDs: ids, prosodyHints: prosodyHints)
    }

    /// Backward-compatible convenience method — returns token IDs only.
    public func encode(_ text: String) -> [Int] {
        tokenize(text).tokenIDs
    }

    // MARK: - Core Encoding

    private func encodeNormalized(_ text: String) -> [Int] {
        guard !text.isEmpty else { return [] }

        var ids: [Int] = []

        // Tokenise into words, punctuation, and whitespace runs
        let pattern = #"[A-Za-z]+(?:'[A-Za-z]+)?|[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?(?:st|nd|rd|th)?|[0-9]+(?:\.[0-9]+)?(?:st|nd|rd|th)?|[^A-Za-z0-9\s]|\s+"#
        let regex   = try! NSRegularExpression(pattern: pattern)
        let nsText  = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Gather lowercase words for previous/next context
        let lowerWords = extractWords(from: text)
        var wordIndex  = 0

        for m in matches {
            guard let range = Range(m.range, in: text) else { continue }
            let token = String(text[range])

            // Whitespace
            if token.trimmingCharacters(in: .whitespaces).isEmpty {
                appendSymbol(" ", to: &ids)
                continue
            }

            // Punctuation / symbol already in the vocabulary
            if tokenToId[token] != nil && !token.first!.isLetter && !token.first!.isNumber {
                appendSymbol(token, to: &ids)
                continue
            }

            // Numeric token that TextNormalizer didn't catch (safety net)
            if token.first?.isNumber == true {
                let spoken = normalizer.expandNumberToken(token)
                let prev   = wordIndex > 0 ? lowerWords[wordIndex - 1] : nil
                let next   = wordIndex < lowerWords.count ? lowerWords[wordIndex] : nil
                appendPhrase(spoken, prev: prev, next: next, to: &ids)
                continue
            }

            // Word token
            if token.first?.isLetter == true {
                let prev = wordIndex > 0 ? lowerWords[wordIndex - 1] : nil
                let next = wordIndex + 1 < lowerWords.count ? lowerWords[wordIndex + 1] : nil
                let phones = phonemizer.phonemize(token, previousWord: prev, nextWord: next)
                for phone in phones { appendSymbol(phone, to: &ids) }
                wordIndex += 1
            }
        }

        // Strip trailing spaces
        while ids.last == idSpace { _ = ids.popLast() }
        return ids
    }

    // MARK: - Helpers

    private func appendSymbol(_ sym: String, to arr: inout [Int]) {
        if let id = tokenToId[sym]   { arr.append(id) }
        else if let id = idOOV       { arr.append(id) }
    }

    private func appendPhrase(_ phrase: String, prev: String?, next: String?, to arr: inout [Int]) {
        let words = phrase.split(separator: " ").map(String.init)
        for (i, w) in words.enumerated() {
            if i > 0 { appendSymbol(" ", to: &arr) }
            let p = i == 0 ? prev : words[i - 1]
            let n = i + 1 < words.count ? words[i + 1] : next
            for phone in phonemizer.phonemize(w, previousWord: p, nextWord: n) {
                appendSymbol(phone, to: &arr)
            }
        }
    }

    private func extractWords(from text: String) -> [String] {
        let wordRegex = try! NSRegularExpression(pattern: #"[A-Za-z]+(?:'[A-Za-z]+)?"#)
        return wordRegex
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]).lowercased() } }
    }

    // MARK: - File Loading

    private static func loadTokens(_ url: URL) throws -> [String: Int] {
        let lines: [String]
        do {
            lines = try String(contentsOf: url)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
        } catch {
            throw OtosakuTTSError.invalidTokensFile
        }
        var map = [String: Int]()
        for (i, t) in lines.enumerated() { map[t] = i }
        return map
    }

    private static func loadDict(_ url: URL) throws -> [String: [[String]]] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw OtosakuTTSError.invalidDictionaryFile }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [[String]]] else {
            throw OtosakuTTSError.invalidDictionaryFile
        }
        return obj
    }
}
