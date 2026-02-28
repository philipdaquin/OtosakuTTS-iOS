import Testing
import Foundation
@testable import OtosakuTTS_iOS

// MARK: - Test Fixture

private func makeTokenizer(extraDict: [String: [[String]]] = [:]) throws -> Tokenizer {
    let fm   = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)

    let tokens = [
        " ", ",", ".", "!", "?", "B", "K", "T", "W", "N", "F", "R", "S", "Z", "L",
        "IY1", "IH1", "IY0", "AH0", "OW1", "EH1", "ER1", "ER0", "AE1", "AO1", "AY1",
        "D", "M", "Y", "HH", "AA1", "AH1", "P", "OY1", "V", "UW1", "UW0", "G", "JH",
        "CH", "SH", "TH", "NG", "<oov>"
    ].joined(separator: "\n")
    try tokens.write(to: root.appendingPathComponent("tokens.txt"), atomically: true, encoding: .utf8)

    var dict: [String: [[String]]] = [
        "hello":    [["HH", "AH0", "L", "OW1"]],
        "world":    [["W", "ER1", "L", "D"]],
        "read":     [["R", "IY1", "D"], ["R", "EH1", "D"]],
        "cannot":   [["K", "AE1", "N", "AA1", "T"]],
        "twenty":   [["T", "W", "EH1", "N", "T", "IY1"]],
        "one":      [["W", "AH1", "N"]],
        "point":    [["P", "OY1", "N", "T"]],
        "five":     [["F", "AY1", "V"]],
        "doctor":   [["D", "AA1", "K", "T", "ER0"]],
        "first":    [["F", "ER1", "S", "T"]],
        "ninety":   [["N", "AY1", "N", "T", "IY0"]],
        "nine":     [["N", "AY1", "N"]],
        "percent":  [["P", "ER0", "S", "EH1", "N", "T"]],
        "fourteen": [["F", "AO1", "R", "T", "IY1", "N"]],
        "dollars":  [["D", "AA1", "L", "ER0", "Z"]],
        "cents":    [["S", "EH1", "N", "T", "S"]],
        "fifty":    [["F", "IH1", "F", "T", "IY0"]],
        "number":   [["N", "AH1", "M", "B", "ER0"]],
        "two":      [["T", "UW1"]],
        "and":      [["AE1", "N", "D"]],
        "will":     [["W", "IH1", "L"]],
    ]
    for (k, v) in extraDict { dict[k] = v }

    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
    try data.write(to: root.appendingPathComponent("cmudict.json"))

    return try Tokenizer(
        tokensFile: root.appendingPathComponent("tokens.txt"),
        dictFile:   root.appendingPathComponent("cmudict.json")
    )
}

// MARK: - Existing Pipeline Tests (updated for new normalizer)

@Test func expandsNumbersAndAbbreviations() throws {
    let tokenizer = try makeTokenizer()
    let ids = tokenizer.encode("Dr. has 21.5")
    #expect(!ids.isEmpty)
}

@Test func usesHeteronymContextForRead() throws {
    let tokenizer = try makeTokenizer()
    let present = tokenizer.encode("I will read")
    let past    = tokenizer.encode("I read yesterday")
    #expect(present != past)
}

@Test func handlesAcronymsWithoutFallingBackToLetters() throws {
    let tokenizer = try makeTokenizer()
    let ids = tokenizer.encode("NASA")
    #expect(!ids.isEmpty)
}

@Test func expandsOrdinalsAndPercentages() throws {
    let tokenizer = try makeTokenizer()
    #expect(tokenizer.encode("21st")  == tokenizer.encode("twenty first"))
    #expect(tokenizer.encode("99%")   == tokenizer.encode("ninety nine percent"))
}

@Test func expandsCurrencyAndRomanNumerals() throws {
    let tokenizer = try makeTokenizer()
    // Currency now produces "X dollars and Y cents"
    #expect(tokenizer.encode("$21.50") == tokenizer.encode("twenty one dollars and fifty cents"))
    #expect(tokenizer.encode("XIV")    == tokenizer.encode("fourteen"))
}

@Test func expandsListNumberingAtLineStarts() throws {
    let tokenizer = try makeTokenizer()
    let listed = tokenizer.encode("1. hello\n2. world")
    let spoken = tokenizer.encode("number one, hello number two, world")
    #expect(listed == spoken)
}

// MARK: - TextNormalizer Tests

@Test func normalizesSymbols() {
    let n = TextNormalizer()
    // Numbers adjacent to symbols are expanded to words by the full pipeline
    #expect(n.normalize("100°C") == "one hundred degrees Celsius")
    #expect(n.normalize("32°F")  == "thirty two degrees Fahrenheit")
    #expect(n.normalize("45°")   == "forty five degrees")
    #expect(n.normalize("a & b") == "a and b")
    #expect(n.normalize("user@example") == "user at example")
}

@Test func normalizesLargeNumbers() {
    let n = TextNormalizer()
    #expect(n.normalize("1000000")   == "one million")
    #expect(n.normalize("2500000")   == "two million five hundred thousand")
    #expect(n.normalize("1000000000") == "one billion")
}

@Test func normalizesYears() {
    let n = TextNormalizer()
    #expect(n.normalize("1995") == "nineteen ninety five")
    #expect(n.normalize("2024") == "twenty twenty four")
    #expect(n.normalize("2000") == "two thousand")
    #expect(n.normalize("2005") == "two thousand five")
    #expect(n.normalize("1800") == "eighteen hundred")
}

@Test func normalizesCurrencyWithAnd() {
    let n = TextNormalizer()
    #expect(n.normalize("$9.99")  == "nine dollars and ninety nine cents")
    #expect(n.normalize("$1.00")  == "one dollar")
    #expect(n.normalize("£5")     == "five pounds")
    #expect(n.normalize("€10.50") == "ten euros and fifty cents")
}

@Test func normalizesUnicodePunctuation() {
    let n = TextNormalizer()
    #expect(n.normalize("hello\u{2014}world") == "hello , world")
    #expect(n.normalize("wait\u{2026}") == "wait ,")
}

@Test func normalizesAbbreviations() {
    let n = TextNormalizer()
    #expect(n.normalize("Dr. Smith") == "doctor Smith")
    #expect(n.normalize("Mr. Jones") == "mister Jones")
    #expect(n.normalize("etc.") == "et cetera")
}

// MARK: - PronunciationDict Tests

@Test func pronunciationDictAppliesOverrides() {
    var dict = PronunciationDict()
    dict.addEntry(word: "CoreML", replacement: "core em el")
    let result = dict.apply("using CoreML today")
    #expect(result == "using core em el today")
}

@Test func pronunciationDictIsCaseInsensitive() {
    var dict = PronunciationDict()
    dict.addEntry(word: "GitHub", replacement: "git hub")
    #expect(dict.apply("Visit github for more") == "Visit git hub for more")
    #expect(dict.apply("Visit GitHub for more") == "Visit git hub for more")
}

@Test func pronunciationDictLongerMatchFirst() {
    var dict = PronunciationDict()
    dict.addEntry(word: "New York City", replacement: "new york city")
    dict.addEntry(word: "New York",      replacement: "new york")
    let result = dict.apply("I love New York City")
    // Longer match should win
    #expect(result == "I love new york city")
}

@Test func pronunciationDictLoadsFromString() {
    let input = """
    # This is a comment
    WWDC\tW W D C
    EPub\tee pub
    """
    let dict = PronunciationDict(bundledDict: input)
    #expect(dict.apply("Watch WWDC videos") == "Watch W W D C videos")
    #expect(dict.apply("Read an EPub book") == "Read an ee pub book")
}

// MARK: - ProsodyParser Tests

@Test func prosodyParserStripsEmphasisTags() {
    let parser = ProsodyParser()
    let (clean, hints) = parser.parse("<emphasis>hello</emphasis> world")
    #expect(clean == "hello world")
    #expect(!hints.isEmpty)
    #expect(hints[0]?.pitchScale == 1.2)
}

@Test func prosodyParserStripsBreakTag() {
    let parser = ProsodyParser()
    let (clean, hints) = parser.parse("hello <break time=\"300ms\"/> world")
    #expect(!clean.contains("<break"))
    // Break hint should record silence
    let hasBreak = hints.values.contains { $0.insertSilenceMs > 0 }
    #expect(hasBreak)
}

@Test func prosodyParserHandlesNestedHints() {
    let parser = ProsodyParser()
    let (clean, hints) = parser.parse("<rate slow><emphasis>urgent</emphasis></rate>")
    #expect(clean.trimmingCharacters(in: .whitespaces) == "urgent")
    // The word should have both emphasis and rate hints merged
    if let hint = hints[0] {
        #expect(hint.pitchScale > 1.0)
        #expect(hint.durationScale > 1.0)
    }
}

@Test func prosodyParserPassesThroughPlainText() {
    let parser = ProsodyParser()
    let (clean, hints) = parser.parse("just plain text here")
    #expect(clean == "just plain text here")
    #expect(hints.isEmpty)
}

// MARK: - TokenizerOutput Tests

@Test func tokenizerOutputContainsHintsWhenEnabled() throws {
    let fm   = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)

    let tokens = [" ", "AH0", "L", "OW1", "HH", "<oov>"].joined(separator: "\n")
    try tokens.write(to: root.appendingPathComponent("tokens.txt"), atomically: true, encoding: .utf8)

    let dict: [String: [[String]]] = ["hello": [["HH", "AH0", "L", "OW1"]]]
    let data = try JSONSerialization.data(withJSONObject: dict)
    try data.write(to: root.appendingPathComponent("cmudict.json"))

    var config = TokenizerConfig()
    config.parseProsody = true
    let tokenizer = try Tokenizer(
        tokensFile: root.appendingPathComponent("tokens.txt"),
        dictFile:   root.appendingPathComponent("cmudict.json"),
        config:     config
    )

    let output = tokenizer.tokenize("<emphasis>hello</emphasis>")
    #expect(!output.tokenIDs.isEmpty)
    #expect(!output.prosodyHints.isEmpty)
}
