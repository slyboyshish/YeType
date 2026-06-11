import XCTest
@testable import YeType

final class YeTypePermissionKindTests: XCTestCase {

    func test_allCases_containsExactlyThreePermissions() {
        XCTAssertEqual(YeTypePermissionKind.allCases.count, 3)
    }

    func test_rawValues_matchExpectedPrivacyKeys() {
        XCTAssertEqual(YeTypePermissionKind.accessibility.rawValue, "Privacy_Accessibility")
        XCTAssertEqual(YeTypePermissionKind.inputMonitoring.rawValue, "Privacy_ListenEvent")
        XCTAssertEqual(YeTypePermissionKind.screenRecording.rawValue, "Privacy_ScreenCapture")
    }

    func test_allCases_haveTitles() {
        for kind in YeTypePermissionKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind) should have a non-empty title")
        }
        XCTAssertEqual(YeTypePermissionKind.accessibility.title, "Accessibility")
        XCTAssertEqual(YeTypePermissionKind.inputMonitoring.title, "Input Monitoring")
        XCTAssertEqual(YeTypePermissionKind.screenRecording.title, "Screen Recording")
    }

    func test_allCases_haveSystemImageNames() {
        for kind in YeTypePermissionKind.allCases {
            XCTAssertFalse(
                kind.systemImageName.isEmpty,
                "\(kind) should have a non-empty systemImageName"
            )
        }
    }

    func test_allCases_haveOnboardingSubtitles() {
        for kind in YeTypePermissionKind.allCases {
            XCTAssertFalse(
                kind.onboardingSubtitle.isEmpty,
                "\(kind) should have a non-empty onboardingSubtitle"
            )
        }
    }

    func test_settingsURL_usesExpectedDeepLinkFormat() {
        for kind in YeTypePermissionKind.allCases {
            let expected = "x-apple.systempreferences:com.apple.preference.security?\(kind.rawValue)"
            XCTAssertEqual(kind.settingsURL.absoluteString, expected)
        }
    }

    func test_guidanceStyle_isGuidedOverlayForAllCases() {
        for kind in YeTypePermissionKind.allCases {
            XCTAssertEqual(kind.guidanceStyle, .guidedOverlay)
        }
    }

    func test_isRequiredForAutocomplete_isTrueOnlyForCoreInputPermissions() {
        XCTAssertTrue(YeTypePermissionKind.accessibility.isRequiredForAutocomplete)
        XCTAssertTrue(YeTypePermissionKind.inputMonitoring.isRequiredForAutocomplete)
        // Screen Recording is optional: missing it forces the text-only Fast Mode path rather than
        // disabling autocomplete.
        XCTAssertFalse(YeTypePermissionKind.screenRecording.isRequiredForAutocomplete)
    }

    func test_isOptionalEnhancement_isTrueOnlyForScreenRecording() {
        XCTAssertTrue(YeTypePermissionKind.screenRecording.isOptionalEnhancement)
        XCTAssertFalse(YeTypePermissionKind.accessibility.isOptionalEnhancement)
        XCTAssertFalse(YeTypePermissionKind.inputMonitoring.isOptionalEnhancement)
    }

    func test_guidanceHint_isNonEmptyForAllCases() {
        for kind in YeTypePermissionKind.allCases {
            XCTAssertFalse(
                kind.guidanceHint.isEmpty,
                "\(kind) should have a non-empty guidanceHint"
            )
        }
    }
}

final class VisualContextModelTests: XCTestCase {

    func test_status_detail_returnsNonEmptyStringForEachCase() {
        let cases: [VisualContextStatus] = [
            .idle, .capturing, .extractingText, .ready,
            .unavailable("no permission"), .failed("timeout")
        ]
        let details = cases.map(\.detail)
        for detail in details {
            XCTAssertFalse(detail.isEmpty)
        }
        // All distinct
        XCTAssertEqual(Set(details).count, details.count, "Each status case should have a unique detail")
    }

    func test_status_unavailableAndFailed_includeAssociatedReasonInDetail() {
        let reason = "Screen recording denied"
        XCTAssertEqual(VisualContextStatus.unavailable(reason).detail, reason)
        XCTAssertEqual(VisualContextStatus.failed(reason).detail, reason)
    }

    func test_defaultConfiguration_hasExpectedValues() {
        let config = VisualContextConfiguration.default
        XCTAssertEqual(config.snapshotDimension, 700)
        XCTAssertEqual(config.maxImageDimension, 1600)
        XCTAssertEqual(config.minRecognizedCharacterCount, 12)
        XCTAssertEqual(config.maxRecognizedCharacters, 5000)
        XCTAssertEqual(config.maxSummaryCharacters, 1500)
    }

    func test_focusedInputAugmentationSession_equatableConformance() {
        let id = UUID()
        let sessionA = FocusedInputAugmentationSession(
            sessionID: id,
            elementIdentifier: "field1",
            focusChangeSequence: 1,
            status: .idle,
            excerpt: nil
        )
        var sessionB = FocusedInputAugmentationSession(
            sessionID: id,
            elementIdentifier: "field1",
            focusChangeSequence: 1,
            status: .idle,
            excerpt: nil
        )
        XCTAssertEqual(sessionA, sessionB)

        sessionB.status = .ready
        XCTAssertNotEqual(sessionA, sessionB)
    }
}
