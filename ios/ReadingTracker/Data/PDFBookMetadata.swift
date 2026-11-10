import Foundation
import PDFKit

/// Optional bibliographic metadata; no text recognition or network lookups.
struct PDFBookMetadata {
    var description: String?
    var series: [BookSeries] = []
    var subjects: [String] = []
    var languages: [String] = []
    var editionYear: Int?
    var isbn: String?

    init(url: URL) {
        guard let document = PDFDocument(url: url), let pdf = document.documentRef else { return }
        let attributes = document.documentAttributes ?? [:]
        // PDF Subject corresponds to a short description; Keywords are topic tags.
        description = BookMetadataXML.clean(attributes[PDFDocumentAttribute.subjectAttribute] as? String)
        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            subjects = Self.unique(keywords.flatMap(Self.keywords))
        } else if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? String {
            subjects = Self.keywords(keywords)
        }
        guard let catalog = pdf.catalog else { return }
        var language: CGPDFStringRef?
        if CGPDFDictionaryGetString(catalog, "Lang", &language), let language,
           let value = CGPDFStringCopyTextString(language) as String? {
            languages = Self.unique([value])
        }
        var stream: CGPDFStreamRef?
        var dataFormat = CGPDFDataFormat.raw
        guard CGPDFDictionaryGetStream(catalog, "Metadata", &stream), let stream,
              let data = CGPDFStreamCopyData(stream, &dataFormat) as Data?,
              data.count <= 2_000_000,
              let xmp = BookMetadataXML.parse(data) else { return }

        let descriptions = xmp.nodes(namespace: BookMetadataXML.dc, name: "description")
        description = descriptions.compactMap { node in
            let alternatives = node.nodes(namespace: BookMetadataXML.rdf, name: "li")
            return BookMetadataXML.clean(alternatives.first {
                $0.attributes[BookMetadataXML.key(BookMetadataXML.xml, "lang")] == "x-default"
            }?.text) ?? alternatives.compactMap { BookMetadataXML.clean($0.text) }.first
                ?? BookMetadataXML.clean(node.text)
        }.first ?? xmp.attributeValues(namespace: BookMetadataXML.dc, name: "description").first ?? description

        let topics = xmp.values(namespace: BookMetadataXML.dc, name: "subject")
        let keywordTopics: [String] = xmp.values(namespace: BookMetadataXML.pdf, name: "Keywords")
            .flatMap { Self.keywords($0) }
        if !topics.isEmpty || !keywordTopics.isEmpty { subjects = Self.unique(topics + keywordTopics) }
        let languageTags = xmp.values(namespace: BookMetadataXML.dc, name: "language")
        if !languageTags.isEmpty { languages = Self.unique(languageTags) }

        isbn = OpenLibraryISBN.uniqueISBN(in: xmp.values(namespace: BookMetadataXML.dc, name: "identifier"))

        // Dublin Core `issued` explicitly describes publication. Generic XMP dates do not.
        let issuedDates = xmp.values(namespace: BookMetadataXML.dcterms, name: "issued")
        let years = Set(issuedDates.compactMap(Self.publicationYear))
        if years.count == 1 { editionYear = years.first }

        // Calibre uses a qualified RDF value with a series-index qualifier.
        series = xmp.nodes(namespace: BookMetadataXML.calibre, name: "series").compactMap { node in
            let value = node.values(namespace: BookMetadataXML.rdf, name: "value").first ?? BookMetadataXML.clean(node.text)
            guard let name = value else { return nil }
            let position = node.values(namespace: BookMetadataXML.calibreSI, name: "series_index")
                .first.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
            return BookSeries(name: name, position: position)
        }
    }

    private static func publicationYear(_ value: String) -> Int? {
        let pattern = #"^[0-9]{4}(-[0-9]{2}(-[0-9]{2}(T.+)?)?)?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil,
              let year = Int(value.prefix(4)), year > 0 else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let date = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        let components = DateComponents(year: year, month: date.count > 1 ? date[1] : 1,
                                        day: date.count > 2 ? date[2] : 1)
        guard components.isValidDate(in: calendar) else { return nil }
        if value.count > 10 {
            let formatter = ISO8601DateFormatter()
            if value.contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
            guard formatter.date(from: value) != nil else { return nil }
        }
        return year
    }

    private static func keywords(_ text: String) -> [String] {
        unique(text.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(BookMetadataXML.clean).filter { seen.insert($0.lowercased()).inserted }
    }
}
