//
//  TextNormalizer.swift
//  OtosakuTTS-iOS
//
//  Converts raw text into clean, speakable English before phonemization.
//  All processing is fully offline — no network calls.
//

import Foundation

public struct TextNormalizer: Sendable {

    // MARK: - Configuration

    public var abbreviations: [String: String] = TextNormalizer.defaultAbbreviations
    public var locale: Locale = .current

    public init() {}

    // MARK: - Public API

    public func normalize(_ text: String) -> String {
        var result = text
        result = normalizeUnicode(result)
        result = expandSymbols(result)
        result = expandAbbreviationsInText(result)
        result = expandDates(result)
        result = expandPhoneNumbers(result)
        result = expandCurrencies(result)
        result = expandPercentages(result)
        result = expandListNumbering(result)
        result = expandOrdinals(result)
        result = expandNumbers(result)
        result = normalizeWhitespace(result)
        return result
    }

    // MARK: - Unicode Normalization

    private func normalizeUnicode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2014}", with: " , ")   // em dash —
            .replacingOccurrences(of: "\u{2013}", with: " , ")   // en dash –
            .replacingOccurrences(of: "\u{2026}", with: " , ")   // ellipsis …
            .replacingOccurrences(of: "\u{201C}", with: "\"")    // left double quote "
            .replacingOccurrences(of: "\u{201D}", with: "\"")    // right double quote "
            .replacingOccurrences(of: "\u{2018}", with: "'")     // left single quote '
            .replacingOccurrences(of: "\u{2019}", with: "'")     // right single quote '
    }

    // MARK: - Symbol Expansion

    private func expandSymbols(_ text: String) -> String {
        var result = text
        // Longer patterns must come before their prefixes
        result = result.replacingOccurrences(of: "°C", with: " degrees Celsius")
        result = result.replacingOccurrences(of: "°F", with: " degrees Fahrenheit")
        result = result.replacingOccurrences(of: "°",  with: " degrees")
        result = result.replacingOccurrences(of: "&",  with: " and ")
        result = result.replacingOccurrences(of: "@",  with: " at ")
        result = result.replacingOccurrences(of: "#",  with: " number ")
        result = result.replacingOccurrences(of: "+",  with: " plus ")
        return result
    }

    // MARK: - Abbreviation Expansion

    private func expandAbbreviationsInText(_ text: String) -> String {
        var result = text
        // Sort by length descending so longer abbreviations match first
        for (abbr, expansion) in abbreviations.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: abbr))",
                with: expansion,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Collapse multiple consecutive dots that survived abbreviation expansion
        result = result.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)
        return result
    }

    // MARK: - Date Expansion

    private static let monthNames: [String] = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    private static let monthAbbreviations: [String: String] = [
        "jan": "January", "feb": "February", "mar": "March",  "apr": "April",
        "may": "May",     "jun": "June",     "jul": "July",   "aug": "August",
        "sep": "September","oct": "October", "nov": "November","dec": "December"
    ]

    private func expandDates(_ text: String) -> String {
        var result = text

        // MM/DD/YYYY  or  MM/DD/YY
        result = replaceMatches(
            in: result,
            pattern: #"\b(1[0-2]|0?[1-9])/(3[01]|[12][0-9]|0?[1-9])/([0-9]{2,4})\b"#
        ) { groups in
            guard groups.count >= 3,
                  let month = Int(groups[0]),
                  let day   = Int(groups[1]) else { return nil }
            let monthName = TextNormalizer.monthNames[month - 1]
            let dayOrd    = speakOrdinal(day)
            let yearStr   = speakYear(groups[2])
            return "\(monthName) \(dayOrd), \(yearStr)"
        }

        // DD Mon YYYY  (e.g. "15 Jan 2024", "3 February 1990")
        result = replaceMatches(
            in: result,
            pattern: #"\b(3[01]|[12][0-9]|0?[1-9])\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+([0-9]{4})\b"#,
            options: [.caseInsensitive]
        ) { groups in
            guard groups.count >= 3, let day = Int(groups[0]) else { return nil }
            let abbr      = String(groups[1].prefix(3)).lowercased()
            let monthName = TextNormalizer.monthAbbreviations[abbr] ?? groups[1]
            let dayOrd    = speakOrdinal(day)
            let yearStr   = speakYear(groups[2])
            return "the \(dayOrd) of \(monthName), \(yearStr)"
        }

        return result
    }

    // MARK: - Phone Number Expansion

    private func expandPhoneNumbers(_ text: String) -> String {
        // Matches: (NXX) NXX-XXXX  |  NXX-NXX-XXXX  |  NXX.NXX.XXXX  (optionally +1 prefix)
        replaceMatches(
            in: text,
            pattern: #"(?:\+1[\s-]?)?(?:\(([2-9][0-9]{2})\)|([2-9][0-9]{2}))[.\- ]([2-9][0-9]{2})[.\- ]([0-9]{4})\b"#
        ) { groups in
            guard groups.count >= 4 else { return nil }
            // group 0 = area (from parenthesised form), group 1 = area (bare), group 2 = exchange, group 3 = number
            let area     = groups[0].isEmpty ? groups[1] : groups[0]
            let exchange = groups[2]
            let number   = groups[3]
            let spellDigits: (String) -> String = { s in
                s.compactMap { digitWordPhone(String($0)) }.joined(separator: " ")
            }
            return "\(spellDigits(area)), \(spellDigits(exchange)), \(spellDigits(number))"
        }
    }

    // MARK: - Currency Expansion

    private func expandCurrencies(_ text: String) -> String {
        var result = text

        // USD  $amount
        result = replaceMatches(
            in: result,
            pattern: #"\$([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"#
        ) { groups in
            groups.first.flatMap { speakCurrency($0, unit: ("dollar", "dollars"), cents: ("cent", "cents")) }
        }

        // GBP  £amount
        result = replaceMatches(
            in: result,
            pattern: #"£([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"#
        ) { groups in
            groups.first.flatMap { speakCurrency($0, unit: ("pound", "pounds"), cents: ("penny", "pence")) }
        }

        // EUR  €amount
        result = replaceMatches(
            in: result,
            pattern: #"€([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"#
        ) { groups in
            groups.first.flatMap { speakCurrency($0, unit: ("euro", "euros"), cents: ("cent", "cents")) }
        }

        return result
    }

    // MARK: - Percentage Expansion

    private func expandPercentages(_ text: String) -> String {
        replaceMatches(
            in: text,
            pattern: #"([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)%"#
        ) { groups in
            guard let number = groups.first else { return nil }
            return "\(expandNumberToken(number)) percent"
        }
    }

    // MARK: - List Numbering

    private func expandListNumbering(_ text: String) -> String {
        replaceMatches(
            in: text,
            pattern: #"(^|\n)\s*([0-9]{1,3})\.\s+"#,
            options: [.anchorsMatchLines]
        ) { groups in
            guard groups.count >= 2 else { return nil }
            let prefix     = groups[0]
            let numberWord = expandNumberToken(groups[1])
            return "\(prefix)number \(numberWord), "
        }
    }

    // MARK: - Ordinal Expansion

    private func expandOrdinals(_ text: String) -> String {
        replaceMatches(
            in: text,
            pattern: #"\b([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)(st|nd|rd|th)\b"#,
            options: [.caseInsensitive]
        ) { groups in
            guard groups.count >= 2 else { return nil }
            return speakOrdinalNumber(groups[0] + groups[1])
        }
    }

    // MARK: - Plain Number Expansion

    private func expandNumbers(_ text: String) -> String {
        replaceMatches(
            in: text,
            pattern: #"\b([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)\b"#
        ) { groups in
            guard let token = groups.first else { return nil }
            return expandNumberToken(token)
        }
    }

    // MARK: - Whitespace Normalization

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Number Helpers

    /// Expands a raw numeric token (possibly with decimal point or ordinal suffix) to words.
    func expandNumberToken(_ token: String) -> String {
        let cleaned = token.replacingOccurrences(of: ",", with: "")

        // Ordinal suffix already attached
        if cleaned.range(of: #"^[0-9]+(st|nd|rd|th)$"#, options: [.regularExpression, .caseInsensitive]) != nil,
           let spoken = speakOrdinalNumber(cleaned) {
            return spoken
        }

        // Decimal number
        if cleaned.contains(".") {
            let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { return token }
            let left  = speakWholeNumber(parts[0]) ?? parts[0]
            let right = parts[1].compactMap { digitWord(String($0)) }.joined(separator: " ")
            return right.isEmpty ? left : "\(left) point \(right)"
        }

        return speakWholeNumber(cleaned) ?? cleaned
    }

    /// Converts a decimal-free digit string to words. Handles up to trillions.
    func speakWholeNumber(_ digits: String) -> String? {
        let cleaned = digits.replacingOccurrences(of: ",", with: "")

        // 4-digit numbers in the year range get year-style reading
        if cleaned.count == 4, let value = Int(cleaned), (1000...2099).contains(value) {
            return speakYear(cleaned)
        }

        guard let value = Int(cleaned), value >= 0 else { return nil }
        return speakInt(value)
    }

    private func speakInt(_ value: Int) -> String? {
        if value == 0 { return "zero" }
        if value < 20 { return smallNumberWord(value) }
        if value < 100 {
            let tens      = value / 10
            let rem       = value % 10
            let tensWords = ["", "", "twenty", "thirty", "forty", "fifty",
                             "sixty", "seventy", "eighty", "ninety"]
            return rem == 0 ? tensWords[tens] : "\(tensWords[tens]) \(smallNumberWord(rem))"
        }
        if value < 1_000 {
            let h   = value / 100;  let rem = value % 100
            let head = "\(smallNumberWord(h)) hundred"
            return rem == 0 ? head : "\(head) \(speakInt(rem)!)"
        }
        if value < 1_000_000 {
            let th  = value / 1_000; let rem = value % 1_000
            let head = "\(speakInt(th)!) thousand"
            return rem == 0 ? head : "\(head) \(speakInt(rem)!)"
        }
        if value < 1_000_000_000 {
            let m   = value / 1_000_000; let rem = value % 1_000_000
            let head = "\(speakInt(m)!) million"
            return rem == 0 ? head : "\(head) \(speakInt(rem)!)"
        }
        if value < 1_000_000_000_000 {
            let b   = value / 1_000_000_000; let rem = value % 1_000_000_000
            let head = "\(speakInt(b)!) billion"
            return rem == 0 ? head : "\(head) \(speakInt(rem)!)"
        }
        return nil
    }

    /// Year-aware reading for 4-digit strings.
    private func speakYear(_ yearStr: String) -> String {
        guard let year = Int(yearStr), year >= 1000, year <= 2099 else {
            return speakWholeNumber(yearStr) ?? yearStr
        }
        // 2000–2009: "two thousand [one]"
        if (2000...2009).contains(year) {
            let rem = year % 100
            return rem == 0 ? "two thousand" : "two thousand \(smallNumberWord(rem))"
        }
        // 2010–2099 and 1000–1999: "twenty twenty-four", "nineteen ninety-five"
        let century = year / 100
        let rem     = year % 100
        if rem == 0 { return "\(speakInt(century)!) hundred" }
        return "\(speakInt(century)!) \(speakInt(rem)!)"
    }

    private func speakOrdinal(_ n: Int) -> String {
        speakOrdinalNumber("\(n)th") ?? "\(n)"
    }

    func speakOrdinalNumber(_ digitsWithSuffix: String) -> String? {
        let cleaned = digitsWithSuffix.replacingOccurrences(of: ",", with: "").lowercased()
        guard let wholeRange = cleaned.range(of: #"^[0-9]+(st|nd|rd|th)$"#, options: .regularExpression),
              wholeRange.lowerBound == cleaned.startIndex,
              wholeRange.upperBound == cleaned.endIndex,
              let digitRange = cleaned.range(of: #"^[0-9]+"#, options: .regularExpression) else {
            return nil
        }
        let digitPart = String(cleaned[digitRange])
        guard let value = Int(digitPart), value > 0 else { return nil }

        let special: [Int: String] = [
            1: "first",   2: "second",    3: "third",      4: "fourth",    5: "fifth",
            6: "sixth",   7: "seventh",   8: "eighth",     9: "ninth",    10: "tenth",
           11: "eleventh",12: "twelfth",  13: "thirteenth",14: "fourteenth",15: "fifteenth",
           16: "sixteenth",17: "seventeenth",18: "eighteenth",19: "nineteenth",
           20: "twentieth",30: "thirtieth",40: "fortieth",50: "fiftieth",
           60: "sixtieth",70: "seventieth",80: "eightieth",90: "ninetieth",
          100: "hundredth",1000: "thousandth"
        ]
        if let direct = special[value] { return direct }

        if value < 100 {
            let tens = (value / 10) * 10; let ones = value % 10
            guard let tensWord = special[tens], let onesWord = special[ones] else { return nil }
            let baseTens = tensWord.replacingOccurrences(of: "ieth", with: "y")
            return "\(baseTens) \(onesWord)"
        }

        guard let cardinal = speakWholeNumber(digitPart) else { return nil }
        let words = cardinal.split(separator: " ").map(String.init)
        guard let last = words.last else { return nil }
        return (words.dropLast() + [makeOrdinalWord(last)]).joined(separator: " ")
    }

    private func speakCurrency(_ amount: String, unit: (String, String), cents: (String, String)) -> String? {
        let cleaned = amount.replacingOccurrences(of: ",", with: "")
        let parts   = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let whole = Int(parts[0]) else { return nil }
        let wholeStr = speakInt(whole) ?? parts[0]
        let unitStr  = whole == 1 ? unit.0 : unit.1
        var phrase   = "\(wholeStr) \(unitStr)"
        if parts.count == 2, let c = Int(String(parts[1].prefix(2))), c > 0 {
            let centStr  = speakInt(c) ?? String(c)
            let centUnit = c == 1 ? cents.0 : cents.1
            phrase += " and \(centStr) \(centUnit)"
        }
        return phrase
    }

    // MARK: - Digit Words

    func smallNumberWord(_ n: Int) -> String {
        ["zero","one","two","three","four","five","six","seven","eight","nine",
         "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen",
         "seventeen","eighteen","nineteen"][n]
    }

    /// Digit to word for decimals and general use (0 → "zero").
    func digitWord(_ ch: String) -> String? {
        switch ch {
        case "0": return "zero"
        case "1": return "one";  case "2": return "two";  case "3": return "three"
        case "4": return "four"; case "5": return "five"; case "6": return "six"
        case "7": return "seven";case "8": return "eight";case "9": return "nine"
        default: return nil
        }
    }

    /// Digit to word for phone numbers (0 → "oh").
    private func digitWordPhone(_ ch: String) -> String? {
        ch == "0" ? "oh" : digitWord(ch)
    }

    private func makeOrdinalWord(_ word: String) -> String {
        switch word {
        case "one":    return "first";  case "two":    return "second"
        case "three":  return "third";  case "five":   return "fifth"
        case "eight":  return "eighth"; case "nine":   return "ninth"
        case "twelve": return "twelfth";case "twenty": return "twentieth"
        case "thirty": return "thirtieth";case "forty": return "fortieth"
        case "fifty":  return "fiftieth";case "sixty":  return "sixtieth"
        case "seventy":return "seventieth";case "eighty":return "eightieth"
        case "ninety": return "ninetieth"
        default:
            return word.hasSuffix("y") ? String(word.dropLast()) + "ieth" : word + "th"
        }
    }

    // MARK: - Abbreviations

    public static let defaultAbbreviations: [String: String] = [
        // Titles
        "mr.":    "mister",       "mrs.":   "misses",       "ms.":    "miss",
        "dr.":    "doctor",       "prof.":  "professor",    "jr.":    "junior",
        "sr.":    "senior",
        // Geographic
        "st.":    "saint",        "ave.":   "avenue",       "blvd.":  "boulevard",
        // Common
        "etc.":   "et cetera",    "vs.":    "versus",
        "e.g.":   "for example",  "i.e.":   "that is",
        "approx.":"approximately","dept.":  "department",
        "govt.":  "government",   "intl.":  "international",
        "max.":   "maximum",      "min.":   "minimum",
        "no.":    "number",       "pp.":    "pages",        "vol.":   "volume"
    ]

    // MARK: - Regex Helper

    func replaceMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: ([String]) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result  = ""
        var current = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text) else { continue }
            result += text[current..<fullRange.lowerBound]
            var groups: [String] = []
            if match.numberOfRanges > 1 {
                for i in 1..<match.numberOfRanges {
                    if let r = Range(match.range(at: i), in: text) { groups.append(String(text[r])) }
                }
            }
            result += transform(groups) ?? String(text[fullRange])
            current = fullRange.upperBound
        }
        result += text[current...]
        return result
    }
}
