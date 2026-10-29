import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit

enum OpenBookError: LocalizedError {
    case unreadable(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): "This book couldn’t be opened. \(detail)"
        case .unsupported: "Only EPUB and PDF books are supported."
        }
    }
}

/// Opens book files with the Readium toolkit.
@MainActor
final class ReadiumServices {
    static let shared = ReadiumServices()

    private let httpClient = DefaultHTTPClient()
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    private lazy var opener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )

    func openPublication(at url: URL) async throws -> Publication {
        guard let fileURL = FileURL(url: url) else { throw OpenBookError.unsupported }
        let asset: Asset
        switch await assetRetriever.retrieve(url: fileURL) {
        case .success(let a): asset = a
        case .failure(let error): throw OpenBookError.unreadable(error.localizedDescription)
        }
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let publication):
            guard publication.conforms(to: .epub) || publication.conforms(to: .pdf) else {
                throw OpenBookError.unsupported
            }
            return publication
        case .failure(let error):
            throw OpenBookError.unreadable(error.localizedDescription)
        }
    }
}
