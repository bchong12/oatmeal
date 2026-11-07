import Foundation
import AppKit

/// Snippet: say the cue, get the expansion.
struct Snippet: Codable, Hashable, Identifiable {
    var id = UUID()
    var cue: String
    var text: String
}

/// Dictionary entry: what the model hears → how it should be written.
struct DictionaryWord: Codable, Hashable, Identifiable {
    var id = UUID()
    var heard: String
    var written: String
}

/// User-editable dictation preferences, stored in UserDefaults.
@MainActor
final class VoiceSettings: ObservableObject {
    static let shared = VoiceSettings()

    @Published var removeFillers: Bool { didSet { save() } }
    @Published var backtrack: Bool { didSet { save() } }
    @Published var spokenPunctuation: Bool { didSet { save() } }
    @Published var lists: Bool { didSet { save() } }
    @Published var appStyles: Bool { didSet { save() } }
    @Published var codeAware: Bool { didSet { save() } }
    @Published var sounds: Bool { didSet { save() } }
    @Published var words: [DictionaryWord] { didSet { save() } }
    @Published var snippets: [Snippet] { didSet { save() } }

    static let starterWords: [DictionaryWord] = [
        ("supabase", "Supabase"), ("cloudflare", "Cloudflare"), ("vercel", "Vercel"), ("swift ui", "SwiftUI"),
        ("swiftui", "SwiftUI"), ("github", "GitHub"), ("open ai", "OpenAI"), ("javascript", "JavaScript"),
        ("typescript", "TypeScript"), ("oat meal", "Oatmeal"), ("purist", "Purist"),
        ("mac os", "macOS"), ("ios", "iOS"), ("figma", "Figma"), ("notion", "Notion"),
    ].map { DictionaryWord(heard: $0.0, written: $0.1) }

    private let d = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        func flag(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
        removeFillers = flag("v.fillers", true)
        backtrack = flag("v.backtrack", true)
        spokenPunctuation = flag("v.punct", true)
        lists = flag("v.lists", true)
        appStyles = flag("v.styles", true)
        codeAware = flag("v.code", true)
        sounds = flag("v.sounds", true)
        words = (d.data(forKey: "v.words")).flatMap { try? JSONDecoder().decode([DictionaryWord].self, from: $0) } ?? Self.starterWords
        snippets = (d.data(forKey: "v.snippets")).flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
    }

    private func save() {
        d.set(removeFillers, forKey: "v.fillers"); d.set(backtrack, forKey: "v.backtrack")
        d.set(spokenPunctuation, forKey: "v.punct"); d.set(lists, forKey: "v.lists")
        d.set(appStyles, forKey: "v.styles"); d.set(codeAware, forKey: "v.code"); d.set(sounds, forKey: "v.sounds")
        d.set(try? JSONEncoder().encode(words), forKey: "v.words")
        d.set(try? JSONEncoder().encode(snippets), forKey: "v.snippets")
    }

    var options: TextFormatter.Options {
        .init(removeFillers: removeFillers, backtrack: backtrack, spokenPunctuation: spokenPunctuation, lists: lists,
              appStyles: appStyles, codeAware: codeAware, words: words, snippets: snippets)
    }
}

/// Turns raw transcripts into finished text, the way Wispr Flow's auto-edits do,
/// with plain rules (no model): fillers, self-corrections, spoken punctuation,
/// numbered lists, your dictionary and snippets, and per-app style.
enum TextFormatter {
    struct Options {
        var removeFillers = true
        var backtrack = true
        var spokenPunctuation = true
        var lists = true
        var appStyles = true
        var codeAware = true
        var words: [DictionaryWord] = []
        var snippets: [Snippet] = []
    }

    enum AppKind { case standard, casual, code }

    static let casualApps: Set<String> = ["com.apple.MobileSMS", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "net.whatsapp.WhatsApp",
                                          "WhatsApp", "ru.keepcoder.Telegram", "com.facebook.archon", "com.apple.iChat"]
    static let codeApps: Set<String> = ["com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.apple.dt.Xcode", "dev.warp.Warp-Stable",
                                        "com.apple.Terminal", "com.googlecode.iterm2", "com.exafunction.windsurf", "dev.zed.Zed", "com.sublimetext.4",
                                        "com.jetbrains.intellij", "com.mitchellh.ghostty"]

    static func kind(for bundleID: String?) -> AppKind {
        guard let b = bundleID else { return .standard }
        if codeApps.contains(b) { return .code }
        if casualApps.contains(b) { return .casual }
        return .standard
    }

    static func format(_ raw: String, app: AppKind = .standard, options o: Options) -> String {
        var s = " " + raw.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        guard s.trimmingCharacters(in: .whitespaces).count > 0 else { return "" }

        // Snippets first: a cue on its own becomes the whole expansion.
        let bare = norm(raw)
        if let sn = o.snippets.first(where: { norm($0.cue) == bare }) { return sn.text }
        // "5 p.m." → "5 pm", so the dots don't read as sentence ends.
        s = s.replacingOccurrences(of: #"(?i)\b([ap])\.\s?m\.?(?=\s|$|[,!?])"#, with: "$1m", options: .regularExpression)
        // Snippet text and links pass through untouched (no added spaces or capitals).
        var vault: [String] = []
        func stash(_ t: String) -> String { vault.append(t); return "\u{E000}\(vault.count - 1)\u{E001}" }
        for sn in o.snippets where !sn.cue.isEmpty {
            s = replace(in: s, word: sn.cue, with: stash(sn.text))
        }
        let linkRe = try! NSRegularExpression(pattern: #"(?i)\b(?:https?://)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:/[^\s]*)?(?:@[a-z0-9.-]+)?"#)
        for m in linkRe.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)).reversed() {
            let link = (s as NSString).substring(with: m.range)
            guard link.contains("."), !link.hasSuffix(".") else { continue }
            s = (s as NSString).replacingCharacters(in: m.range, with: stash(link))
        }

        if o.removeFillers { s = removeFillers(s) }
        if o.backtrack { s = backtrack(s) }
        if o.spokenPunctuation { s = spokenPunctuation(s) }
        for w in o.words where !w.heard.isEmpty { s = replace(in: s, word: w.heard, with: w.written) }
        if app == .code && o.codeAware { s = codeCase(s) }
        s = tidy(s)
        if o.lists { s = numberedList(s) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("\n1. "), s.hasSuffix(".") { s.removeLast() }
        for (i, t) in vault.enumerated() { s = s.replacingOccurrences(of: "\u{E000}\(i)\u{E001}", with: t) }

        if o.appStyles {
            switch app {
            case .casual:
                // Messages read better without the full stop at the end.
                if s.hasSuffix("."), !s.hasSuffix("..."), s.filter({ $0 == "." }).count == 1 { s.removeLast() }
            case .code:
                if s.hasSuffix("."), !s.contains("\n") { s.removeLast() }
            case .standard: break
            }
        }
        return s
    }

    // MARK: Steps

    private static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func removeFillers(_ s: String) -> String {
        var out = s
        // Take the comma before a filler with it, so "should, uh, ship" → "should ship".
        let pattern = #"(?i)(?:,\s*)?(?<![\w'])(?:u+m+|u+h+|e+r+m*|a+h+|h+m+|m+h*m+)(?![\w'])[,.]?\s*"#
        out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        // "like, you know," as pure filler between commas
        out = out.replacingOccurrences(of: #"(?i),\s*you know,\s*"#, with: ", ", options: .regularExpression)
        return out
    }

    /// "Let's meet at 2, actually 3" → "Let's meet at 3"; "…, scratch that." drops the sentence before it.
    static func backtrack(_ s: String) -> String {
        var out = s
        // scratch that / delete that: drop the sentence (or clause) before it.
        while let r = out.range(of: #"(?i)[^.!?]*?[,.]?\s*\b(scratch that|delete that|never ?mind that)\b[,.!]?\s*"#, options: .regularExpression) {
            out.replaceSubrange(r, with: " ")
        }
        // "<x>, actually <y>" / "<x>, I mean <y>" / "<x>, no wait <y>" where x and y are the same kind of thing.
        let cue = #"(?:actually|i mean|no wait|no,|sorry|make that)"#
        let unit = #"(\d{1,2}(?::\d{2})?\s?(?:am|pm|a\.m\.|p\.m\.)?|monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight|\d+)"#
        let re = try! NSRegularExpression(pattern: "(?i)\\b" + unit + "[,]?\\s+" + cue + "[,]?\\s+" + unit + "\\b")
        let ns = out as NSString
        var result = out
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
            let replacement = ns.substring(with: m.range(at: 2))
            result = (result as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return result
    }

    static func spokenPunctuation(_ s: String) -> String {
        var out = s
        let marks: [(String, String)] = [
            ("new paragraph", "\n\n"), ("new line", "\n"), ("next line", "\n"),
            ("question mark", "?"), ("exclamation point", "!"), ("exclamation mark", "!"),
            ("full stop", "."), ("period", "."), ("comma", ","), ("colon", ":"), ("semicolon", ";"),
            ("open quote", "\u{201C}"), ("close quote", "\u{201D}"), ("dash", " \u{2013}"),
        ]
        for (word, mark) in marks {
            // Only when spoken as its own word, and strip the space before the mark.
            // The speech model often adds its own mark too ("question mark?"), so eat that.
            out = out.replacingOccurrences(of: "(?i)[,.]?\\s*\\b" + word + "\\b[,.?!]?", with: mark, options: .regularExpression)
        }
        return out
    }

    static func codeCase(_ s: String) -> String {
        var out = s
        func join(_ words: [String], _ style: String) -> String {
            let w = words.map { $0.lowercased() }
            switch style {
            case "camel": return (w.first ?? "") + w.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            case "pascal": return w.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            case "snake": return w.joined(separator: "_")
            case "kebab": return w.joined(separator: "-")
            default: return w.joined(separator: "_").uppercased()
            }
        }
        let re = try! NSRegularExpression(pattern: #"(?i)\b(camel|pascal|snake|kebab|constant) case\s+((?:[a-z0-9]+\s?){1,5}?)(?=[,.!?]|\s(?:and|then|to|in|of|with)\b|\s*$)"#)
        let ns = out as NSString
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
            let style = ns.substring(with: m.range(at: 1)).lowercased()
            let words = ns.substring(with: m.range(at: 2)).split(separator: " ").map(String.init)
            out = (out as NSString).replacingCharacters(in: m.range, with: join(words, style))
        }
        return out
    }

    /// "first buy milk second call mum third…" or "one, … two, …" → a numbered list.
    static func numberedList(_ s: String) -> String {
        let ordinals = [["first", "one", "number one"], ["second", "two", "number two"], ["third", "three", "number three"],
                        ["fourth", "four", "number four"], ["fifth", "five", "number five"], ["sixth", "six", "number six"]]
        let lower = s.lowercased()
        var cuts: [(Range<String.Index>, Int)] = []
        var searchFrom = lower.startIndex
        for (i, forms) in ordinals.enumerated() {
            var found: Range<String.Index>?
            for f in forms.sorted(by: { $0.count > $1.count }) {
                if let r = lower.range(of: "(?<![\\w])" + f + "[,:]?\\s", options: .regularExpression, range: searchFrom..<lower.endIndex) {
                    if found == nil || r.lowerBound < found!.lowerBound { found = r }
                }
            }
            guard let r = found else { break }
            cuts.append((r, i + 1)); searchFrom = r.upperBound
        }
        guard cuts.count >= 2 else { return s }
        // The first marker has to start the text or follow a colon/full stop,
        // otherwise "one" is just a word in a sentence.
        let before = s[s.startIndex..<cuts[0].0.lowerBound].trimmingCharacters(in: .whitespaces)
        guard before.isEmpty || before.hasSuffix(":") || before.hasSuffix(".") else { return s }
        var lines: [String] = []
        if !before.isEmpty { lines.append(before) }
        for (k, cut) in cuts.enumerated() {
            let end = k + 1 < cuts.count ? cuts[k + 1].0.lowerBound : s.endIndex
            var item = s[cut.0.upperBound..<end].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            if item.hasSuffix(".") && k + 1 < cuts.count { item.removeLast() }
            item = item.prefix(1).uppercased() + item.dropFirst()
            lines.append("\(cut.1). \(item)")
        }
        return lines.joined(separator: "\n")
    }

    private static func replace(in s: String, word: String, with repl: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return s.replacingOccurrences(of: "(?i)(?<![\\w])" + escaped + "(?![\\w])", with: NSRegularExpression.escapedTemplate(for: repl), options: .regularExpression)
    }

    /// Spacing and capitals after the edits above.
    static func tidy(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"([,.!?;:])(?=[A-Za-z])"#, with: "$1 ", options: .regularExpression)
        out = out.replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)
        out = out.replacingOccurrences(of: #"([.!?])\s*[,.]"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
        // Capital after sentence ends and line breaks.
        var chars = Array(out)
        var cap = true
        for i in chars.indices {
            if cap, chars[i].isLetter { chars[i] = Character(chars[i].uppercased()); cap = false }
            else if chars[i].isLetter || chars[i].isNumber { cap = false }
            if ".!?\n".contains(chars[i]) { cap = true }
        }
        return String(chars)
    }

    static func wordCount(_ s: String) -> Int { s.split { $0.isWhitespace }.count }
}

/// Calm mallet tones for the pill (made by scripts/make_sounds.py), not the system Tink and Pop.
enum DictationSounds {
    static func start() { play("pill-start") }
    static func stop() { play("pill-stop") }
    static func cancel() { play("pill-cancel") }

    private static var cache: [String: NSSound] = [:]

    private static func play(_ name: String) {
        guard UserDefaults.standard.object(forKey: "v.sounds") as? Bool ?? true else { return }
        if cache[name] == nil, let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") {
            cache[name] = NSSound(contentsOf: url, byReference: true)
        }
        guard let sound = cache[name] else { return }
        sound.stop()
        sound.volume = 0.45
        sound.play()
    }
}
