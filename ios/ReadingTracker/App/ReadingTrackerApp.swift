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
                .environmentObject(environment)
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
}
