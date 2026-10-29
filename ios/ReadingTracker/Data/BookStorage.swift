import Foundation

/// Where book files and covers are kept: a folder inside Application Support,
/// which is backed up with the device and never purged by iOS.
struct BookStorage: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var `default`: BookStorage {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BookStorage(directory: support.appendingPathComponent("Books", isDirectory: true))
    }

    func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func removeFiles(of book: Book) {
        try? FileManager.default.removeItem(at: url(for: book.fileName))
        if let cover = book.coverFileName {
            try? FileManager.default.removeItem(at: url(for: cover))
        }
    }
}
