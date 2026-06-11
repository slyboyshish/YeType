import CoreGraphics
import Foundation

/// Pure caret-geometry trust policy used by `FocusSnapshotResolver`.
///
/// Two decisions live here, kept free of live Accessibility objects so they can be unit tested:
///   1. `shouldSearchDeep` — whether the focused input's own caret geometry is too weak to trust,
///      so the resolver should run the expensive deep AX-tree walk for a better source.
///   2. `select` — given the primary candidate's geometry and an optional deep-walk result, which
///      rect to actually ship, following a fixed precedence.
///
/// The regression these protect against is trusting a descendant rect over the focused input's own
/// usable rect (or vice versa). Chrome's AXTextArea answers BoundsForRange with a multi-line union
/// rect — labelled `.derived` but unusable for precise caret placement — while the leaf AXStaticText
/// holding the active line carries a real `.exact` rect that the deep walk can recover.
enum CaretGeometrySelector {
    /// The caret geometry chosen to ship, plus a human-readable source label for diagnostics.
    struct Selected: Equatable {
        let rect: CGRect
        let source: String
        let quality: CaretGeometryQuality
        let observedCharWidth: CGFloat?
    }

    /// Whether the primary (focused-input) caret geometry is too weak to trust, so the resolver
    /// should run the deep AX-tree walk for a more precise source.
    ///
    /// `.exact` and `.derived` are trusted as-is; only `.estimated`, unknown quality, or a missing
    /// rect justify the ~200-node walk. The walk pins a CPU core when run on every keystroke, so we
    /// avoid it whenever the primary geometry is already good enough.
    /// A `.derived` rect taller than this is treated as a multi-line union (e.g. Chrome / Claude
    /// AXTextArea answering BoundsForRange with the bounds of the whole wrapped field) rather than a
    /// single caret line. Single-line carets stay well under this even at large font sizes, so the
    /// expensive deep walk remains skipped for them and only runs to recover the active line once the
    /// field has actually wrapped — exactly the case where ghost text was being misplaced below.
    static let multiLineDerivedHeightThreshold: CGFloat = 50

    static func shouldSearchDeep(
        primaryRect: CGRect?,
        primaryQuality: CaretGeometryQuality?
    ) -> Bool {
        guard let primaryRect else {
            return true
        }
        switch primaryQuality {
        case .exact:
            return false
        case .derived:
            // Single-line derived rect is trusted as-is; a multi-line union rect is unusable for
            // caret placement, so run the walk to recover the active line's exact rect.
            return primaryRect.height > multiLineDerivedHeightThreshold
        default:
            return true
        }
    }

    /// Chooses the caret geometry to ship from the primary candidate and the optional deep-tree
    /// result. Returns `nil` when neither source produced a rect, which the caller maps to an
    /// unsupported snapshot.
    ///
    /// Precedence:
    ///   1. primary `.exact`    (single API call, perfect — no walk needed)
    ///   2. primary `.derived`  (trusted; `shouldSearchDeep` skips the walk entirely for it)
    ///   3. deep (any)          (only reached when primary is `.estimated`/unknown)
    ///   4. primary (any, fallback)
    static func select(
        primaryRect: CGRect?,
        primaryQuality: CaretGeometryQuality?,
        primaryObservedCharWidth: CGFloat?,
        deepResult: CaretGeometryResult?
    ) -> Selected? {
        if let primary = primaryRect, primaryQuality == .exact {
            return Selected(
                rect: primary, source: "exact primary", quality: .exact,
                observedCharWidth: primaryObservedCharWidth
            )
        }
        if let primary = primaryRect, primaryQuality == .derived {
            // A multi-line derived rect is a union of all wrapped lines (`shouldSearchDeep` ran the
            // walk for it). The deep walk recovers the active line's exact leaf rect, which is what
            // we want for caret placement — prefer it over the unusable union bounds. A single-line
            // derived rect has no deep walk (or no better exact result), so it ships as-is.
            if primary.height > multiLineDerivedHeightThreshold,
               let deep = deepResult, deep.quality == .exact {
                return Selected(
                    rect: deep.rect, source: "exact deep (multiline derived)", quality: .exact,
                    observedCharWidth: deep.observedCharWidth
                )
            }
            return Selected(
                rect: primary, source: "derived primary", quality: .derived,
                observedCharWidth: primaryObservedCharWidth
            )
        }
        if let deep = deepResult {
            return Selected(
                rect: deep.rect, source: "\(deep.quality.label) deep", quality: deep.quality,
                observedCharWidth: deep.observedCharWidth
            )
        }
        if let primary = primaryRect {
            return Selected(
                rect: primary,
                source: "\(primaryQuality?.label ?? "unknown") primary-fallback",
                quality: primaryQuality ?? .estimated,
                observedCharWidth: primaryObservedCharWidth
            )
        }
        return nil
    }
}
