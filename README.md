# Reading Tracker — native apps

Native iPhone/iPad and Android versions of [Reading Tracker](https://github.com/ninanguyen26/reading_tracker), a Kindle-style reader for your own EPUB and PDF books. Books stay on the device.

Both apps are built on the open-source [Readium](https://readium.org) toolkits, the same architecture as Apple Books: native screens around the book, with EPUB pages drawn by the system's web engine and PDFs by the platform's PDF engine.

| | iOS / iPadOS | Android |
| --- | --- | --- |
| Folder | [`ios/`](ios) | `android/` (planned) |
| Language / UI | Swift, SwiftUI | Kotlin, Jetpack Compose |
| Reading engine | Readium Swift toolkit 3.11 | Readium Kotlin toolkit |
| Storage | SQLite (GRDB) + files in Application Support | SQLite (Room) + app files |
| Minimum OS | iOS 16 | Android 8 |

## Status

**Phase 1 — iOS foundation (done)**
- Add books from Files (several at once) or with **Open in Reading Tracker** from Files, Mail, Safari or AirDrop
- Native library: cover grid (adapts to iPhone and iPad), title and author read from the book, progress on each cover, search, sort (recently read, recently added, title, author), long-press to delete
- New imports also store embedded descriptions, series names and positions, subjects, and language tags when present. EPUBs use their publication metadata. PDFs use XMP Dublin Core fields, Calibre XMP series metadata, and fallback document Subject, Keywords, and catalog language. Long-press a library book and choose **Book Details**, or tap the reader's Info button, to see available metadata. Empty fields are hidden. Existing library entries receive empty defaults; their files are not rescanned.
- Imports automatically look up missing descriptions, series, subjects, and languages through Open Library in the background. ISBN matches use the exact edition; without an ISBN, a unique exact title/author match supplies work-level details without guessing an edition's language. Existing useful metadata and covers are preserved, with individual source links for additions. Descriptions reject single-word text and format-only placeholders such as Hardcover or Kindle edition; an unusable edition description falls back to the work synopsis. Previously stored placeholders are hidden and retried from their linked Open Library work when Book Details opens. Single-word subjects and series names remain valid. Offline, unavailable, or ambiguous lookups never block importing or reading. **Find Missing Details** in Book Details remains available for retries and manual matching. Searches send only lookup text, never book files; requests are cached and spaced at least 1.1 seconds apart. Open Library's [API usage guidelines](https://openlibrary.org/developers/api) apply.
- Books are classified automatically after import enrichment into a fixed set of 16 fiction/nonfiction genres. Clear subject phrases map locally; ambiguous books can use Apple's on-device Foundation Model on iOS 26+ when Apple Intelligence is available. No classification server, API key, or cloud fallback is used. Insufficient, conflicting, unavailable-model, and out-of-taxonomy cases remain Unclassified. Book Details → **Edit Genres** supports one primary genre and up to two secondary genres; manual selections (including Unclassified) survive later enrichment. **Use Automatic Classification** explicitly restores automatic classification. Older library entries start unclassified and can use that action without reimporting.
- Reader for EPUB (Readium navigator) and PDF (PDFKit): tap the left or right edge, swipe, or use arrow keys to turn pages; tap the middle to show or hide the toolbar
- Opens where you left off, even after quitting the app
- Footer with chapter, location or page, and percent
- Follows the system light/dark appearance

**Next**
- Phase 2 — iOS reading features: contents, bookmarks, themes and fonts, scroll mode, search, highlights and notes, notes page, shelves, time left, backup and restore (compatible with the web app's backups), Look Up dictionary
- Phase 3 — Android app with the same features
- Phase 4 — App Store and Google Play preparation

## iOS: building and running

Requires Xcode 26 or newer.

```bash
open ios/ReadingTracker.xcodeproj
```

Choose an iPhone or iPad simulator and press Run. To try the app with the two sample books, edit the scheme's *Run → Arguments* and add `-reset-library` and `-import-samples` (debug builds only).

For everyday development, use the scheme's **Debug Run** action and SwiftUI previews (including the navigation preview in `AppNavigationBar.swift`). Debug signing is configured for the Apphibian development team. Xcode Run builds incrementally and updates the selected device automatically; archive/export is for distribution, not each UI edit. SwiftUI source changes still need compilation on a physical device; the preview canvas provides the faster layout feedback loop.

To build and open the latest changes on Ngoc's connected iPhone in one command:

```bash
bash scripts/run-ios-device.sh
```

This reuses `/private/tmp/ReadingTracker-Debug-build`, updates the installed app
without deleting its data, and launches it automatically. Keep the phone connected
and unlocked. Override `READING_TRACKER_DEVICE_ID` for another device, or
`READING_TRACKER_DERIVED_DATA` for a different build-cache location. Build output
is saved as `device-build.log` in that cache. Signing still requires an unlocked
signing keychain; no passwords are stored by the script.

The Xcode project is generated from [`ios/project.yml`](ios/project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding, removing or renaming files:

```bash
brew install xcodegen
```

```bash
cd ios && xcodegen
```

### Tests

```bash
cd ios && xcodebuild test -project ReadingTracker.xcodeproj -scheme ReadingTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```

- **Unit tests** (`ReadingTrackerTests`): importing EPUB and PDF files (metadata, covers, cleanup on failure, rejecting other files), deleting, saving progress, sorting and search, tap zones.
- **UI tests** (`ReadingTrackerUITests`): the library lists imported books; reading an EPUB and resuming at the same place after quitting; turning PDF pages by tapping; showing and hiding the toolbar.

### Layout

```
ios/
  project.yml               XcodeGen project definition
  ReadingTracker/
    App/                    app entry point, shared services, Info.plist
    Data/                   Book model, database, file storage, importer, Readium setup
    Library/                library screen
    Reader/                 reader screen and the Readium navigator host
    Resources/              assets; DebugFixtures holds sample books for debug builds
  ReadingTrackerTests/      unit tests and fixtures
  ReadingTrackerUITests/    UI tests
```

## Notes

- **PDF taps:** Readium's PDF navigator waits for PDFKit's own tap recognizers to fail before reporting a tap, which doesn't happen on recent iOS versions, so the app recognizes PDF taps itself ([`ReaderHostViewController`](ios/ReadingTracker/Reader/ReaderHostViewController.swift)).
- **Positions:** EPUB "locations" come from Readium, which counts them from the book's compressed size, so short books have few locations; the percentage is always accurate.
