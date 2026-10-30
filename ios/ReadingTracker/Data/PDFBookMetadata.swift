import Foundation
import PDFKit

/// Optional bibliographic metadata; no text recognition or network lookups.
struct PDFBookMetadata {
    var description: String?
    var series: [BookSeries] = []
    var subjects: [String] = []
    var languages: [String] = []

    init(url: URL) {
        guard let document = PDFDocument(url: url), let pdf = document.documentRef else { return }
        let attributes = document.documentAttributes ?? [:]
        // PDF Subject corresponds to a short description; Keywords are topic tags.
        description = Self.clean(attributes[PDFDocumentAttribute.subjectAttribute] as? String)
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
              let xmp = PDFXMP.parse(data) else { return }

        let descriptions = xmp.nodes(namespace: PDFXMP.dc, name: "description")
        description = descriptions.compactMap { node in
            let alternatives = node.nodes(namespace: PDFXMP.rdf, name: "li")
            return Self.clean(alternatives.first {
                $0.attributes[PDFXMP.key(PDFXMP.xml, "lang")] == "x-default"
            }?.text) ?? alternatives.compactMap { Self.clean($0.text) }.first
                ?? Self.clean(node.text)
        }.first ?? xmp.attributeValues(namespace: PDFXMP.dc, name: "description").first ?? description

        let topics = xmp.values(namespace: PDFXMP.dc, name: "subject")
        let keywordTopics: [String] = xmp.values(namespace: PDFXMP.pdf, name: "Keywords")
            .flatMap { Self.keywords($0) }
        if !topics.isEmpty || !keywordTopics.isEmpty { subjects = Self.unique(topics + keywordTopics) }
        let languageTags = xmp.values(namespace: PDFXMP.dc, name: "language")
        if !languageTags.isEmpty { languages = Self.unique(languageTags) }

        // Calibre uses a qualified RDF value with a series-index qualifier.
        series = xmp.nodes(namespace: PDFXMP.calibre, name: "series").compactMap { node in
            let value = node.values(namespace: PDFXMP.rdf, name: "value").first ?? Self.clean(node.text)
            guard let name = value else { return nil }
            let position = node.values(namespace: PDFXMP.calibreSI, name: "series_index")
                .first.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
            return BookSeries(name: name, position: position)
        }
    }

    fileprivate static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func keywords(_ text: String) -> [String] {
        unique(text.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(clean).filter { seen.insert($0.lowercased()).inserted }
    }
}

/// A small namespace-aware XMP reader. RDF arrays remain separate values.
private final class PDFXMP: NSObject, XMLParserDelegate {
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let xml = "http://www.w3.org/XML/1998/namespace"
    static let pdf = "http://ns.adobe.com/pdf/1.3/"
    static let calibre = "http://calibre-ebook.com/xmp-namespace"
    static let calibreSI = "http://calibre-ebook.com/xmp-namespace-series-index"

    static func key(_ namespace: String, _ name: String) -> String { namespace + "|" + name }

    final class Node {
        let namespace: String
        let name: String
        var attributes: [String: String] = [:]
        var text = ""
        var children: [Node] = []

        init(namespace: String = "", name: String = "") {
            self.namespace = namespace
            self.name = name
        }

        func nodes(namespace: String, name: String) -> [Node] {
            children.flatMap { child in
                (child.namespace == namespace && child.name == name ? [child] : [])
                    + child.nodes(namespace: namespace, name: name)
            }
        }

        func attributeValues(namespace: String, name: String) -> [String] {
            let own = PDFBookMetadata.clean(attributes[PDFXMP.key(namespace, name)]).map { [$0] } ?? []
            return own + children.flatMap { $0.attributeValues(namespace: namespace, name: name) }
        }

        func values(namespace: String, name: String) -> [String] {
            nodes(namespace: namespace, name: name).flatMap { node -> [String] in
                let items = node.nodes(namespace: PDFXMP.rdf, name: "li")
                return (items.isEmpty ? [node.text] : items.map(\.text)).compactMap(PDFBookMetadata.clean)
            } + attributeValues(namespace: namespace, name: name)
        }
    }

    private let root = Node()
    private var stack: [Node] = []
    private var namespaces = ["xml": [PDFXMP.xml]]
    private var nodeCount = 0

    static func parse(_ data: Data) -> Node? {
        let delegate = PDFXMP()
        delegate.stack = [delegate.root]
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() ? delegate.root : nil
    }

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        namespaces[prefix, default: []].append(namespaceURI)
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        _ = namespaces[prefix]?.popLast()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        nodeCount += 1
        guard stack.count < 32, nodeCount <= 10_000 else { parser.abortParsing(); return }
        let node = Node(namespace: namespaceURI ?? "", name: elementName)
        for (name, value) in attributeDict {
            let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
            let namespace = parts.count == 2 ? namespaces[parts[0]]?.last ?? "" : ""
            node.attributes[Self.key(namespace, parts.last ?? name)] = value
        }
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if stack.count > 1 { stack.removeLast() }
    }
}
