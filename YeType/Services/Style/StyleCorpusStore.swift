import Foundation

/// File overview:
/// Accumulates a small, rolling corpus of the user's own writing and exposes it as a compact
/// few-shot block that conditions the local model toward the user's voice. This is YeType's
/// "learn my style" feature, implemented the cheap way: instead of fine-tuning weights, we keep a
/// bounded set of recent sentences the user actually wrote and prepend them to the prompt. Because
/// the block changes rarely, it sits at a stable position in the prompt prefix and benefits from the
/// runtime's KV-prefix reuse (the corpus is processed once and cached, not re-encoded per keystroke).
///
/// Safety: this is OPT-IN. `StyleCorpusStore.isEnabled` is false unless the user turns it on, so the
/// shipping default behaviour is unchanged. When off, `record` and `styleBlock` are no-ops.
///
/// Privacy: the corpus lives only on disk in the app's Application Support directory; it never leaves
/// the device (the whole engine is local).
final class StyleCorpusStore {
    static let shared = StyleCorpusStore()

    /// UserDefaults flag the settings UI (or `defaults write`) flips. Off by default so the feature
    /// can ship dark and never alter suggestions until the user opts in.
    private static let enabledKey = "yetypeStyleLearningEnabled"

    /// Hard caps keep the injected block small so it conditions voice without crowding the caret
    /// prefix or blowing the KV budget on a fanless Mac.
    private static let maxSamples = 6
    private static let maxSampleChars = 120
    private static let minSampleChars = 25
    /// Throttle: only capture at most once per this interval so fast typing doesn't thrash the file.
    private static let captureIntervalSeconds: TimeInterval = 8

    /// Largest single-poll text growth still treated as live typing. A bigger jump means focus change,
    /// paste, or navigation into pre-existing text — never recorded, so we never learn text the user
    /// did not type this session (their own Claude messages, a note's existing body, OCR'd screen text).
    private static let maxTypingDeltaChars = 24
    /// Cap the running typed buffer so a long uninterrupted session can't grow unbounded before a
    /// sentence terminator flushes it.
    private static let maxTypedBufferChars = 600

    private let queue = DispatchQueue(label: "com.yetype.style-corpus")
    private let fileURL: URL?
    private var samples: [String]
    private var lastCaptureAt: Date?
    /// The previous `precedingText` we saw, to diff against. Only the newly-appended suffix counts as
    /// "typed". Reset (no capture) whenever the change is too large to be a keystroke.
    private var lastSeenText: String?
    /// Accumulates only the characters the user actually typed, across polls, until a sentence
    /// terminator flushes the completed sentence into `samples`.
    private var typedBuffer: String = ""

    private init() {
        fileURL = Self.makeFileURL()
        samples = Self.load(from: fileURL)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Toggle the feature from the settings UI. Turning it off leaves the stored corpus intact so the
    /// user can re-enable without losing what was learned; `clear()` is the explicit wipe.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    /// The samples currently learned, newest last. For the settings "Style memory" view so the user
    /// can see exactly what was captured.
    func currentSamples() -> [String] {
        queue.sync { samples }
    }

    /// Wipe the learned corpus (file + memory). The capture throttle resets too.
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.samples.removeAll()
            self.lastCaptureAt = nil
            self.lastSeenText = nil
            self.typedBuffer = ""
            Self.save(self.samples, to: self.fileURL)
        }
    }

    /// Feeds the latest `precedingText` (the text before the caret in the focused field) so the store
    /// can learn ONLY what the user actively types. It diffs against the previous value and keeps just
    /// the freshly-appended characters; large jumps (focus change, paste, scrolling into existing or
    /// on-screen text) reset the baseline and capture nothing. Completed sentences in the typed buffer
    /// are committed as samples. No-op when disabled.
    func record(_ text: String) {
        guard isEnabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lastSeenText = text }

            guard let previous = self.lastSeenText else {
                // First sight of this field: treat as baseline. Never record pre-existing text.
                return
            }
            if text == previous { return }

            let appended = Self.appendedSuffix(previous: previous, current: text)
            let removedCount = previous.count - Self.commonPrefixCount(previous, text)

            // Only incremental typing qualifies: a small append with little/no deletion. Anything
            // larger is a focus switch, paste, or navigation — drop it and rebaseline so its content
            // never enters the corpus.
            guard !appended.isEmpty,
                  appended.count <= Self.maxTypingDeltaChars,
                  removedCount <= 2 else {
                self.typedBuffer = ""
                return
            }

            self.typedBuffer += appended
            if self.typedBuffer.count > Self.maxTypedBufferChars {
                self.typedBuffer = String(self.typedBuffer.suffix(Self.maxTypedBufferChars))
            }

            // Flush every completed sentence in the buffer; keep the trailing in-progress fragment.
            self.flushCompletedSentences()
        }
    }

    /// Extracts completed sentences (terminated by . ! ?) from `typedBuffer`, records the ones that
    /// fit the length window, and leaves the trailing unfinished fragment in the buffer.
    private func flushCompletedSentences() {
        var fragment = ""
        var leftover = ""
        var sawTerminator = false
        for char in typedBuffer {
            if sawTerminator && !(char == "." || char == "!" || char == "?") {
                leftover.append(char)
                continue
            }
            fragment.append(char)
            if char == "." || char == "!" || char == "?" {
                let sentence = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                let count = sentence.count
                if count >= Self.minSampleChars && count <= Self.maxSampleChars, !samples.contains(sentence) {
                    samples.append(sentence)
                    if samples.count > Self.maxSamples {
                        samples.removeFirst(samples.count - Self.maxSamples)
                    }
                    Self.save(samples, to: fileURL)
                }
                fragment = ""
                sawTerminator = true
            }
        }
        // Whatever follows the last terminator (or the whole thing if no terminator) stays buffered.
        typedBuffer = leftover.isEmpty ? fragment : leftover
    }

    /// Characters of `current` that come after its common prefix with `previous` — i.e. the freshly
    /// appended text since last poll.
    static func appendedSuffix(previous: String, current: String) -> String {
        let common = commonPrefixCount(previous, current)
        let currentChars = Array(current)
        guard common <= currentChars.count else { return "" }
        return String(currentChars[common...])
    }

    static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var i = 0
        while i < aChars.count && i < bChars.count && aChars[i] == bChars[i] {
            i += 1
        }
        return i
    }

    /// A compact few-shot block for the prompt, or nil when disabled / empty. Framed as examples of
    /// the author's voice so the base model conditions on style rather than being asked to obey it.
    func styleBlock() -> String? {
        guard isEnabled else { return nil }
        let current = queue.sync { samples }
        guard !current.isEmpty else { return nil }
        let lines = current.map { "- \($0)" }.joined(separator: "\n")
        return "Examples of how this author writes:\n\(lines)"
    }

    // MARK: - Sample extraction

    /// Picks the last complete sentence in `text` that fits the length window. Sentence-final
    /// punctuation marks the boundary; the trailing in-progress fragment after the last terminator is
    /// dropped so we never store half-typed words.
    static func extractSample(from text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        var sentences: [String] = []
        var current = ""
        for char in normalized {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        for candidate in sentences.reversed() {
            let count = candidate.count
            if count >= minSampleChars && count <= maxSampleChars {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Persistence

    private static func makeFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "YeType"
        let directory = support.appendingPathComponent(bundleName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("style-corpus.txt")
    }

    private static func load(from url: URL?) -> [String] {
        guard let url, let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return contents
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private static func save(_ samples: [String], to url: URL?) {
        guard let url else { return }
        let body = samples.joined(separator: "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}
