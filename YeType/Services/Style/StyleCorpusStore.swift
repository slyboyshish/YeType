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

    private let queue = DispatchQueue(label: "com.yetype.style-corpus")
    private let fileURL: URL?
    private var samples: [String]
    private var lastCaptureAt: Date?

    private init() {
        fileURL = Self.makeFileURL()
        samples = Self.load(from: fileURL)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Records a candidate sample drawn from the user's surrounding text. No-op when the feature is
    /// off or when called again inside the throttle window. The newest complete sentence in `text`
    /// is preferred; we never store the in-progress trailing fragment.
    func record(_ text: String) {
        guard isEnabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            if let last = self.lastCaptureAt, now.timeIntervalSince(last) < Self.captureIntervalSeconds {
                return
            }
            guard let sample = Self.extractSample(from: text) else { return }
            guard !self.samples.contains(sample) else { return }
            self.lastCaptureAt = now
            self.samples.append(sample)
            if self.samples.count > Self.maxSamples {
                self.samples.removeFirst(self.samples.count - Self.maxSamples)
            }
            Self.save(self.samples, to: self.fileURL)
        }
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
