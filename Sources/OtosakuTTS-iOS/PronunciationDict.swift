//
//  PronunciationDict.swift
//  OtosakuTTS-iOS
//
//  Word-level pronunciation overrides applied after TextNormalizer and before the Phonemizer.
//  Entries map a surface word/phrase to its preferred spoken form (plain English or custom
//  phonetic spelling that the Phonemizer can process).
//
//  File format (tab-separated, UTF-8):
//
//      # Lines starting with # are comments
//      # word<TAB>replacement
//      CoreML    core em el
//      WWDC      W W D C
//      GitHub    git hub
//      EPub      ee pub
//

import Foundation

public struct PronunciationDict: Sendable {

    // MARK: - Storage

    // Sorted by length descending so longer phrases are matched first.
    private var entries: [(word: String, replacement: String)] = []

    // MARK: - Init

    public init() {}

    /// Initialise from a bundled string (e.g. loaded from a resource file).
    public init(bundledDict: String) {
        loadFromString(bundledDict)
    }

    // MARK: - Public API

    /// Replace all known words/phrases in `text` with their pronunciation overrides.
    /// Matching is case-insensitive and honours word boundaries.
    public func apply(_ text: String) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for entry in entries {
            let escaped = NSRegularExpression.escapedPattern(for: entry.word)
            let pattern = "(?i)\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: entry.replacement
            )
        }
        return result
    }

    /// Add or overwrite a single entry at runtime.
    public mutating func addEntry(word: String, replacement: String) {
        // Remove existing entry for this word (case-insensitive)
        entries.removeAll { $0.word.lowercased() == word.lowercased() }
        entries.append((word: word, replacement: replacement))
        sortEntries()
    }

    /// Load additional entries from a tab-separated file on disk.
    public mutating func loadFromFile(_ url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        loadFromString(contents)
    }

    // MARK: - Private Helpers

    private mutating func loadFromString(_ contents: String) {
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let word        = parts[0].trimmingCharacters(in: .whitespaces)
            let replacement = parts[1...].joined(separator: "\t").trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty, !replacement.isEmpty else { continue }
            // Remove any existing duplicate
            entries.removeAll { $0.word.lowercased() == word.lowercased() }
            entries.append((word: word, replacement: replacement))
        }
        sortEntries()
    }

    /// Longer entries must be tried before shorter ones to avoid partial matches.
    private mutating func sortEntries() {
        entries.sort { $0.word.count > $1.word.count }
    }
}
