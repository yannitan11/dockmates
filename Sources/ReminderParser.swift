import Foundation

/// Turns free text like "remind me to drink water every 30 mins" or
/// "exercise at 6pm" into a Reminder, without needing the Claude CLI.
/// Returns nil when the text doesn't look like a reminder request, so the
/// caller can fall back to asking Claude a real question.
enum ReminderParser {
    static func parse(_ raw: String) -> Reminder? {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = original.lowercased()
        guard !text.isEmpty else { return nil }

        let hasRemind = text.hasPrefix("remind") || text.hasPrefix("please remind")

        for prefix in ["please remind me to ", "please remind me ", "remind me to ",
                       "remind me that ", "remind me ", "remind to ", "remind "] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }

        // Interval: "every 30 mins", "every 1 hour", "every hour", "every 90 minutes"
        if let m = firstMatch(text, #"\bevery\s+(?:(\d+)\s*)?(minutes?|mins?|m|hours?|hrs?|h)\b"#) {
            let n = Int(m.group(1) ?? "") ?? 1
            let unit = (m.group(2) ?? "").lowercased()
            let minutes = unit.hasPrefix("h") ? n * 60 : n
            guard minutes > 0 else { return nil }
            guard let message = message(from: text, removing: m.range, hasRemind: hasRemind) else { return nil }
            return Reminder(message: message, isInterval: true,
                            intervalMinutes: min(minutes, 1440), hour: 9, minute: 0)
        }

        // Daily time: "at 6pm", "at 6:30 pm", "at 18:00", "at 6"
        if let m = firstMatch(text, #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b"#) {
            var hour = Int(m.group(1) ?? "") ?? -1
            let minute = Int(m.group(2) ?? "0") ?? 0
            let meridiem = (m.group(3) ?? "").replacingOccurrences(of: ".", with: "")

            if meridiem == "pm" { if hour < 12 { hour += 12 } }
            else if meridiem == "am" { if hour == 12 { hour = 0 } }
            else if hour >= 1 && hour <= 11 { hour += 12 }  // bare "at 6" → 6pm

            guard hour >= 0 && hour <= 23, minute >= 0 && minute <= 59 else { return nil }
            guard let message = message(from: text, removing: m.range, hasRemind: hasRemind) else { return nil }
            return Reminder(message: message, isInterval: false,
                            intervalMinutes: 60, hour: hour, minute: minute)
        }

        return nil
    }

    // MARK: - Message extraction

    private static let questionWords: Set<String> = [
        "what", "what's", "whats", "why", "how", "how's", "when", "who", "where",
        "which", "is", "are", "was", "were", "can", "could", "should", "would",
        "do", "does", "did", "will", "tell", "write", "explain", "give", "make",
        "show", "find", "search", "summarize", "summarise", "translate", "list",
        "generate", "create", "help", "define",
    ]

    private static func message(from text: String, removing range: Range<String.Index>,
                                hasRemind: Bool) -> String? {
        var s = text
        s.removeSubrange(range)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))

        for lead in ["to ", "me ", "that ", "about "] where s.hasPrefix(lead) {
            s = String(s.dropFirst(lead.count))
        }
        if s.hasSuffix(" please") { s = String(s.dropLast(7)) }
        for tail in [" every day", " everyday", " each day", " daily"] where s.hasSuffix(tail) {
            s = String(s.dropLast(tail.count))
        }
        s = s.trimmingCharacters(in: .whitespaces)

        guard !s.isEmpty else { return nil }

        // Without an explicit "remind", guard against hijacking real questions.
        if !hasRemind, let first = s.split(separator: " ").first,
           questionWords.contains(String(first)) {
            return nil
        }
        return s
    }

    // MARK: - Regex helper

    private struct Match {
        let range: Range<String.Index>
        private let groups: [String?]
        init(range: Range<String.Index>, groups: [String?]) {
            self.range = range
            self.groups = groups
        }
        func group(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> Match? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let full = Range(m.range, in: text) else { return nil }
        var groups: [String?] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append(nil)
            }
        }
        return Match(range: full, groups: groups)
    }
}
