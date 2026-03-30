import Foundation

struct TextPostProcessor {
    let enabled: Bool
    let customFillerWords: [String]

    private static let multiWordFillers: [(pattern: String, flags: String)] = [
        ("\\balso\\s+ähm\\b", "i"),
        ("\\bja\\s+also\\b", "i"),
        ("\\byou\\s+know\\b", "i"),
        ("\\bI\\s+mean\\b", "i"),
    ]

    private static let singleWordFillers: Set<String> = [
        "ähm", "äh", "öhm", "hmm", "mhm",
        "uhm", "uh", "um",
    ]

    private static let trailingFillerPatterns: [String] = [
        ",?\\s*ne\\?$",
    ]

    init(enabled: Bool = true, customFillerWords: [String] = []) {
        self.enabled = enabled
        self.customFillerWords = customFillerWords
    }

    func process(_ text: String) -> String {
        guard enabled else { return text }
        var result = text

        // Remove multi-word fillers
        for filler in Self.multiWordFillers {
            if let regex = try? NSRegularExpression(pattern: filler.pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Remove single-word fillers (as whole words)
        let allSingleFillers = Self.singleWordFillers.union(
            Set(customFillerWords.map { $0.lowercased() })
        )
        let words = result.components(separatedBy: .whitespaces)
        result = words.filter { word in
            let cleaned = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return !cleaned.isEmpty && !allSingleFillers.contains(cleaned)
        }.joined(separator: " ")

        // Remove trailing fillers
        for pattern in Self.trailingFillerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }
}
