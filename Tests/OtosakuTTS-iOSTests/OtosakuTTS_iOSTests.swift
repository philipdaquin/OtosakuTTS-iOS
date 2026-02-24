import Testing
import Foundation
@testable import OtosakuTTS_iOS

private func makeTokenizer() throws -> Tokenizer {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)

    let tokens = [
        " ", ",", ".", "!", "?", "B", "K", "T", "W", "N", "F", "R", "S", "Z", "L",
        "IY1", "IH1", "IY0", "AH0", "OW1", "EH1", "ER1", "ER0", "AE1", "AO1", "AY1",
        "D", "M", "Y", "HH", "AA1", "AH1", "P", "OY1", "V", "UW1", "<oov>"
    ].joined(separator: "\n")
    try tokens.write(to: root.appendingPathComponent("tokens.txt"), atomically: true, encoding: .utf8)

    let dict: [String: [[String]]] = [
        "hello": [["HH", "AH0", "L", "OW1"]],
        "world": [["W", "ER1", "L", "D"]],
        "read": [["R", "IY1", "D"], ["R", "EH1", "D"]],
        "cannot": [["K", "AE1", "N", "AA1", "T"]],
        "twenty": [["T", "W", "EH1", "N", "T", "IY1"]],
        "one": [["W", "AH1", "N"]],
        "point": [["P", "OY1", "N", "T"]],
        "five": [["F", "AY1", "V"]],
        "doctor": [["D", "AA1", "K", "T", "ER0"]],
        "first": [["F", "ER1", "S", "T"]],
        "ninety": [["N", "AY1", "N", "T", "IY0"]],
        "nine": [["N", "AY1", "N"]],
        "percent": [["P", "ER0", "S", "EH1", "N", "T"]],
        "fourteen": [["F", "AO1", "R", "T", "IY1", "N"]],
        "dollars": [["D", "AA1", "L", "ER0", "Z"]],
        "cents": [["S", "EH1", "N", "T", "S"]],
        "fifty": [["F", "IH1", "F", "T", "IY0"]],
        "number": [["N", "AH1", "M", "B", "ER0"]],
        "two": [["T", "UW1"]]
    ]
    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
    try data.write(to: root.appendingPathComponent("cmudict.json"))

    return try Tokenizer(
        tokensFile: root.appendingPathComponent("tokens.txt"),
        dictFile: root.appendingPathComponent("cmudict.json")
    )
}

@Test func expandsNumbersAndAbbreviations() throws {
    let tokenizer = try makeTokenizer()
    let ids = tokenizer.encode("Dr. has 21.5")
    #expect(!ids.isEmpty)
}

@Test func usesHeteronymContextForRead() throws {
    let tokenizer = try makeTokenizer()
    let present = tokenizer.encode("I will read")
    let past = tokenizer.encode("I read yesterday")
    #expect(present != past)
}

@Test func handlesAcronymsWithoutFallingBackToLetters() throws {
    let tokenizer = try makeTokenizer()
    let ids = tokenizer.encode("NASA")
    #expect(!ids.isEmpty)
}

@Test func expandsOrdinalsAndPercentages() throws {
    let tokenizer = try makeTokenizer()
    #expect(tokenizer.encode("21st") == tokenizer.encode("twenty first"))
    #expect(tokenizer.encode("99%") == tokenizer.encode("ninety nine percent"))
}

@Test func expandsCurrencyAndRomanNumerals() throws {
    let tokenizer = try makeTokenizer()
    #expect(tokenizer.encode("$21.50") == tokenizer.encode("twenty one dollars fifty cents"))
    #expect(tokenizer.encode("XIV") == tokenizer.encode("fourteen"))
}

@Test func expandsListNumberingAtLineStarts() throws {
    let tokenizer = try makeTokenizer()
    let listed = tokenizer.encode("1. hello\n2. world")
    let spoken = tokenizer.encode("number one, hello number two, world")
    #expect(listed == spoken)
}
