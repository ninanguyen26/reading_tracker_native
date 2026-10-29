import Foundation

/// The app's shared services, created once at launch.
@MainActor
final class AppEnvironment: ObservableObject {
    let database: AppDatabase
    let storage: BookStorage
    let importer: BookImporter

    init(database: AppDatabase, storage: BookStorage) {
        self.database = database
        self.storage = storage
        self.importer = BookImporter(database: database, storage: storage)
    }

    static func live() -> AppEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        // UI tests start from an empty library.
        if ProcessInfo.processInfo.arguments.contains("-reset-library") {
            try? FileManager.default.removeItem(at: support)
        }
        #endif
        do {
            return AppEnvironment(database: try .onDisk(directory: support), storage: .default)
        } catch {
            // Without its database the app can't work at all; this only happens
            // if the device is out of space or the file is damaged.
            fatalError("Could not open the library database: \(error)")
        }
    }

    #if DEBUG
    /// Adds the bundled sample books, for UI tests and previews.
    func importDebugFixtures() async {
        let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "DebugFixtures") ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            _ = try? await importer.importBook(from: url)
        }
    }
    #endif
}
