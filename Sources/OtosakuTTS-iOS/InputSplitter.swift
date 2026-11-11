import Foundation

/// The FastPitch Core ML graph takes 2...240 phoneme tokens (`x` is a `1 × N` Int32 array).
/// The tokenizer only produces ids; the limit is the model's input shape. `OtosakuTTS.generate`
/// uses this to cut a longer text into pieces the graph accepts.
enum InputSplitter {

    /// Core ML input range of `x`, dimension 1.
    static let maxTokens = 240
    static let minTokens = 2

    struct Piece: Equatable {
        let text: String
        /// The cut fell after punctuation, so a short pause belongs after this piece.
        let endsOnPunctuation: Bool
    }

    /// Whole text when it fits; otherwise pieces cut after the last clause punctuation that fits,
    /// else after the last word that fits. A single word over the limit stays whole.
    static func pieces(
        for text: String,
        maxTokens: Int = InputSplitter.maxTokens,
        countTokens: (String) -> Int
    ) -> [Piece] {
        if countTokens(text) <= maxTokens {
            return [Piece(text: text, endsOnPunctuation: false)]
        }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else { return [Piece(text: text, endsOnPunctuation: false)] }

        func tokens(_ range: Range<Int>) -> Int { countTokens(words[range].joined(separator: " ")) }

        var pieces: [Piece] = []
        var start = 0
        while start < words.count {
            if tokens(start..<words.count) <= maxTokens {
                pieces.append(Piece(text: words[start...].joined(separator: " "), endsOnPunctuation: false))
                break
            }
            // Longest run of words that fits. One word is the floor.
            var low = start + 1
            var high = words.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if tokens(start..<mid) <= maxTokens { low = mid } else { high = mid - 1 }
            }
            // Cut after the last clause punctuation in the run, never leaving a remainder
            // under `minTokens`. Else cut at the last word that fits.
            var end = low
            var onPunctuation = false
            var k = low
            while k > start {
                if endsWithClausePunctuation(words[k - 1]), tokens(k..<words.count) >= minTokens {
                    end = k
                    onPunctuation = true
                    break
                }
                k -= 1
            }
            if !onPunctuation, end < words.count, tokens(end..<words.count) < minTokens, end - 1 > start {
                end -= 1
            }
            pieces.append(
                Piece(
                    text: words[start..<end].joined(separator: " "),
                    endsOnPunctuation: onPunctuation
                )
            )
            start = end
        }
        return pieces
    }

    static func endsWithClausePunctuation(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last(where: { !closingMarks.contains($0) }) else { return false }
        return clauseMarks.contains(last)
    }

    private static let clauseMarks = CharacterSet(charactersIn: ".!?;:,—–")
    private static let closingMarks = CharacterSet(charactersIn: "\"'”’)]»")
}
