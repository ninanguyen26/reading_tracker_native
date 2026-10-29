import ReadiumNavigator
import XCTest
@testable import ReadingTracker

final class ReaderSettingsTests: XCTestCase {
    func testDefaultsKeepTheBooksOwnStyles() {
        let prefs = ReaderSettings().epubPreferences(systemDark: false)
        XCTAssertEqual(prefs.publisherStyles, true)
        XCTAssertNil(prefs.fontFamily)
        XCTAssertNil(prefs.lineHeight)
        XCTAssertEqual(prefs.fontSize, 1.0)
        XCTAssertEqual(prefs.theme, .light)
        XCTAssertEqual(prefs.scroll, false)
    }

    func testCustomTypographyTurnsOffPublisherStyles() {
        var settings = ReaderSettings()
        settings.font = .serif
        settings.spacing = .loose
        settings.margins = .wide
        settings.fontSize = 1.3
        let prefs = settings.epubPreferences(systemDark: false)
        XCTAssertEqual(prefs.publisherStyles, false)
        XCTAssertEqual(prefs.fontFamily, .iowanOldStyle)
        XCTAssertEqual(prefs.lineHeight, 1.8)
        XCTAssertEqual(prefs.pageMargins, 1.6)
        XCTAssertEqual(prefs.fontSize, 1.3)
    }

    func testAutoThemeFollowsTheSystem() {
        let auto = ReaderSettings(theme: .system)
        XCTAssertEqual(auto.epubPreferences(systemDark: true).theme, .dark)
        XCTAssertEqual(auto.epubPreferences(systemDark: false).theme, .light)
        XCTAssertTrue(auto.palette(systemDark: true).isDark)
        // A chosen theme ignores the system.
        XCTAssertEqual(ReaderSettings(theme: .sepia).epubPreferences(systemDark: true).theme, .sepia)
    }

    func testPDFUsesScrollAndThemedBackground() {
        var settings = ReaderSettings(theme: .dark)
        settings.scroll = true
        let prefs = settings.pdfPreferences(systemDark: false)
        XCTAssertEqual(prefs.scroll, true)
        XCTAssertEqual(prefs.backgroundColor, ReadiumNavigator.Color(hex: "#1C1C1E"))
    }

    func testSettingsPersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "settings-test-\(UUID())"))
        XCTAssertEqual(ReaderSettingsStore.load(from: defaults), ReaderSettings())
        var settings = ReaderSettings(theme: .sepia)
        settings.fontSize = 1.4
        settings.scroll = true
        ReaderSettingsStore.save(settings, to: defaults)
        XCTAssertEqual(ReaderSettingsStore.load(from: defaults), settings)
    }
}
