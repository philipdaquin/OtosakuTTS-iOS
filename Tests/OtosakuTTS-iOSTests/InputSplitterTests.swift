import Testing
import Foundation
@testable import OtosakuTTS_iOS

/// One token per character stands in for the tokenizer; the splitter only needs a count.
private func pieces(_ text: String, max: Int) -> [InputSplitter.Piece] {
    InputSplitter.pieces(for: text, maxTokens: max, countTokens: { $0.count })
}

@Suite("InputSplitter")
struct InputSplitterTests {

    @Test func textThatFitsIsNotSplit() {
        #expect(pieces("Short one, fits.", max: 40) == [.init(text: "Short one, fits.", endsOnPunctuation: false)])
    }

    @Test func cutsAfterTheLastPunctuationThatFits() {
        let result = pieces("aaa bbb, ccc ddd, eee fff ggg hhh.", max: 20)
        #expect(result.map(\.text) == ["aaa bbb, ccc ddd,", "eee fff ggg hhh."])
        #expect(result.first?.endsOnPunctuation == true)
    }

    @Test func prefersAPauseOverAFullerPiece() {
        let result = pieces("aaa bbb, ccc ddd eee fff ggg", max: 20)
        #expect(result.map(\.text) == ["aaa bbb,", "ccc ddd eee fff ggg"])
    }

    @Test func cutsAtAWordWithoutPunctuation() {
        let result = pieces("aaa bbb ccc ddd eee fff", max: 12)
        #expect(result.map(\.text) == ["aaa bbb ccc", "ddd eee fff"])
        #expect(result.first?.endsOnPunctuation == false)
    }

    @Test func everyPieceFitsAndNothingIsLost() {
        let text = (0..<60).map { "w\($0)\($0 % 7 == 0 ? "," : "")" }.joined(separator: " ")
        let result = pieces(text, max: 30)
        #expect(result.allSatisfy { $0.text.count <= 30 })
        #expect(result.map(\.text).joined(separator: " ") == text)
    }

    @Test func neverLeavesARemainderUnderTwoTokens() {
        let result = pieces("aaa bbb. .", max: 8)
        #expect(result.allSatisfy { $0.text.count >= InputSplitter.minTokens })
    }

    @Test func aClosingQuoteAfterPunctuationStillCounts() {
        #expect(InputSplitter.endsWithClausePunctuation("said.\u{201D}"))
        #expect(!InputSplitter.endsWithClausePunctuation("word"))
    }

    @Test func oneOverlongWordStaysWhole() {
        #expect(pieces("aaaaaaaaaaaaaaaaaaaa", max: 5).map(\.text) == ["aaaaaaaaaaaaaaaaaaaa"])
    }
}
