import Foundation
import Logging

/// File overview:
/// Owns YeType's language-specific `SymSpell` indexes and exposes synchronous correction lookups
/// for the prediction gate. Index construction is expensive, so dictionaries load on a background
/// queue only when needed. Until a requested language is ready, lookup returns nil and the caller
/// falls back to `NSSpellChecker`.
///
/// `nonisolated` + `@unchecked Sendable` (mirroring `LlamaRuntimeCore`/`FileLogWriter`) because the
/// builds run off the main actor while `bestCorrection` is called from it. The lock protects cache
/// publication, loading state, and LRU metadata. Each `SymSpell` becomes immutable before entering
/// the cache, so readers can safely query a retained instance after releasing the lock.
nonisolated final class SymSpellCorrector: @unchecked Sendable {
    private struct CacheEntry {
        let symSpell: SymSpell
        var lastAccessSequence: UInt64
    }

    typealias ResourceLoader = @Sendable (SpellingDictionaryLanguage) -> String?

    private let lock = NSLock()
    private let maxEditDistance: Int
    private let prefixLength: Int
    private let cacheLimit: Int
    private let resourceLoader: ResourceLoader
    /// All mutable fields below are guarded by `lock`.
    private var cache: [SpellingDictionaryLanguage: CacheEntry] = [:]
    private var loadingLanguages = Set<SpellingDictionaryLanguage>()
    private var accessSequence: UInt64 = 0

    /// `preloadLanguages` warms every enabled dictionary at launch so mid-word completion and
    /// correction are ready immediately — without this, the Russian index only built on the first
    /// Russian word typed and was missing for the first seconds (or longer under load), so Russian
    /// suggestions silently didn't appear right after launch. The cache bound still applies, so only
    /// the most-recently-used `cacheLimit` indexes stay resident.
    init(
        maxEditDistance: Int = 2,
        prefixLength: Int = 7,
        cacheLimit: Int = 2,
        preloadLanguages: [SpellingDictionaryLanguage] = [.english],
        resourceLoader: ResourceLoader? = nil
    ) {
        self.maxEditDistance = maxEditDistance
        self.prefixLength = prefixLength
        self.cacheLimit = max(1, cacheLimit)
        self.resourceLoader = resourceLoader ?? Self.bundledContents(for:)

        for language in preloadLanguages.prefix(self.cacheLimit) {
            requestLoad(for: language)
        }
    }

    /// The best single-word correction for `word`, recased to match it, or nil when the index is not
    /// ready yet, the word is in the dictionary, or nothing is within edit distance. The lookup is
    /// case-insensitive: the dictionary is lowercase, and `TypoCaseTransfer` reapplies the typo's case.
    func bestCorrection(
        for word: String,
        language: SpellingDictionaryLanguage = .english
    ) -> String? {
        guard let symSpell = cachedIndexOrRequestLoad(for: language) else {
            return nil
        }

        let lowered = word.lowercased()
        guard let suggestion = symSpell.bestSuggestion(for: lowered),
              suggestion.distance > 0,
              suggestion.term.lowercased() != lowered else {
            return nil
        }
        return TypoCaseTransfer.applying(caseOf: word, to: suggestion.term)
    }

    /// The best mid-word completion for `prefix` (e.g. "прив" -> "привет"), or nil when the index is
    /// not ready or `prefix` is not the start of any frequent word. Drives the gray completion the user
    /// expects while typing a correct-so-far word, and tells the gate this prefix is valid (not a typo).
    func bestCompletion(
        for prefix: String,
        language: SpellingDictionaryLanguage = .english
    ) -> String? {
        guard let symSpell = cachedIndexOrRequestLoad(for: language) else { return nil }
        return symSpell.bestCompletion(forPrefix: prefix)
    }

    /// Whether `word` is a complete word in the language's dictionary. Lets the gate distinguish a
    /// finished correct word from an unfinished one or a misspelling.
    func contains(_ word: String, language: SpellingDictionaryLanguage = .english) -> Bool {
        guard let symSpell = cachedIndexOrRequestLoad(for: language) else { return false }
        return symSpell.contains(word)
    }

    /// Conservative "is this a real typo" test for languages the OS spell checker can't judge
    /// (e.g. Russian). A bare frequency dictionary cannot distinguish a misspelling from a valid but
    /// rare/inflected word, so flagging anything merely absent from the top-N list constantly
    /// mislabels correct words as typos and buries the continuation suggestion under a green
    /// correction. We require a STRONG signal: the closest dictionary entry is exactly one edit away
    /// (one slip, not a different word form) and the word is long enough that one-edit minimal pairs
    /// (кот/код) don't trigger.
    func looksLikeTypo(for word: String, language: SpellingDictionaryLanguage = .english) -> Bool {
        guard word.count >= 5 else { return false }
        guard let symSpell = cachedIndexOrRequestLoad(for: language) else { return false }
        let lowered = word.lowercased()
        guard let suggestion = symSpell.bestSuggestion(for: lowered),
              suggestion.distance == 1,
              suggestion.term.lowercased() != lowered else {
            return false
        }
        return true
    }

    /// Test seam: synchronously publishes a small in-memory dictionary without touching the bundle.
    func loadForTesting(
        contents: String,
        language: SpellingDictionaryLanguage = .english
    ) {
        let symSpell = makeEmptyIndex()
        symSpell.loadDictionary(contents: contents)

        lock.lock()
        publish(symSpell, for: language)
        loadingLanguages.remove(language)
        lock.unlock()
    }

    /// Test-only visibility into the bounded cache. The sorted result avoids exposing LRU order.
    var cachedLanguagesForTesting: [SpellingDictionaryLanguage] {
        lock.lock()
        let languages = cache.keys.sorted { $0.rawValue < $1.rawValue }
        lock.unlock()
        return languages
    }

    private func cachedIndexOrRequestLoad(for language: SpellingDictionaryLanguage) -> SymSpell? {
        lock.lock()
        if var entry = cache[language] {
            accessSequence &+= 1
            entry.lastAccessSequence = accessSequence
            cache[language] = entry
            lock.unlock()
            return entry.symSpell
        }
        let shouldLoad = loadingLanguages.insert(language).inserted
        lock.unlock()

        if shouldLoad {
            loadInBackground(language)
        }
        return nil
    }

    private func requestLoad(for language: SpellingDictionaryLanguage) {
        lock.lock()
        let shouldLoad = cache[language] == nil
            && loadingLanguages.insert(language).inserted
        lock.unlock()
        if shouldLoad {
            loadInBackground(language)
        }
    }

    private func loadInBackground(_ language: SpellingDictionaryLanguage) {
        DispatchQueue.global(qos: .utility).async { [self] in
            guard let contents = resourceLoader(language) else {
                lock.lock()
                loadingLanguages.remove(language)
                lock.unlock()
                YeTypeLogger.app.error(
                    "SymSpell dictionary resource \(language.resourceName).txt not found in bundle"
                )
                return
            }

            let symSpell = makeEmptyIndex()
            symSpell.loadDictionary(contents: contents)

            lock.lock()
            publish(symSpell, for: language)
            loadingLanguages.remove(language)
            lock.unlock()
            YeTypeLogger.app.info(
                "SymSpell loaded \(symSpell.wordCount) \(language.displayName) words for correction"
            )
        }
    }

    /// Must be called with `lock` held. The newly loaded index is newest, so eviction removes the
    /// least recently used older language and keeps memory bounded even for multilingual users.
    private func publish(_ symSpell: SymSpell, for language: SpellingDictionaryLanguage) {
        accessSequence &+= 1
        cache[language] = CacheEntry(
            symSpell: symSpell,
            lastAccessSequence: accessSequence
        )

        while cache.count > cacheLimit,
              let leastRecentlyUsed = cache.min(by: {
                  $0.value.lastAccessSequence < $1.value.lastAccessSequence
              })?.key {
            cache.removeValue(forKey: leastRecentlyUsed)
        }
    }

    private func makeEmptyIndex() -> SymSpell {
        SymSpell(
            maxDictionaryEditDistance: maxEditDistance,
            prefixLength: prefixLength
        )
    }

    private static func bundledContents(for language: SpellingDictionaryLanguage) -> String? {
        guard let url = resourceURL(for: language) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Xcode may flatten resources or preserve their source folder, so probe both bundle layouts.
    private static func resourceURL(
        for language: SpellingDictionaryLanguage,
        in bundle: Bundle = .main
    ) -> URL? {
        bundle.url(forResource: language.resourceName, withExtension: "txt")
            ?? bundle.url(
                forResource: language.resourceName,
                withExtension: "txt",
                subdirectory: "SpellingDictionaries"
            )
            ?? bundle.url(
                forResource: language.resourceName,
                withExtension: "txt",
                subdirectory: "Resources/SpellingDictionaries"
            )
    }
}
