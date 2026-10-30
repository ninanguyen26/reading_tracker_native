import SwiftUI

@main
struct ReadingTrackerApp: App {
    @StateObject private var environment: AppEnvironment
    @StateObject private var library: LibraryModel

    init() {
        let environment = AppEnvironment.live()
        _environment = StateObject(wrappedValue: environment)
        _library = StateObject(wrappedValue: LibraryModel(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(model: library)
                .tint(AppPalette.accent)
                .environmentObject(environment)
                #if DEBUG
                .preferredColorScheme(testAppearance)
                #endif
                // "Open in Reading Tracker" from Files, Mail, Safari or AirDrop.
                .onOpenURL { url in library.importFiles([url]) }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-import-samples") {
                        await environment.importDebugFixtures()
                    }
                    #endif
                }
        }
    }

    #if DEBUG
    private var testAppearance: ColorScheme? {
        switch ProcessInfo.processInfo.environment["UITEST_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    #endif
}
