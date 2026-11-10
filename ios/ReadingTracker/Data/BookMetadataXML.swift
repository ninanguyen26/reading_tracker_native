import Foundation

/// Reads namespaced publication metadata without resolving external entities.
final class BookMetadataXML: NSObject, XMLParserDelegate {
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let dcterms = "http://purl.org/dc/terms/"
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
            let own = BookMetadataXML.clean(attributes[BookMetadataXML.key(namespace, name)]).map { [$0] } ?? []
            return own + children.flatMap { $0.attributeValues(namespace: namespace, name: name) }
        }

        func values(namespace: String, name: String) -> [String] {
            nodes(namespace: namespace, name: name).flatMap { node -> [String] in
                let items = node.nodes(namespace: BookMetadataXML.rdf, name: "li")
                return (items.isEmpty ? [node.text] : items.map(\.text)).compactMap(BookMetadataXML.clean)
            } + attributeValues(namespace: namespace, name: name)
        }
    }

    static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private let root = Node()
    private var stack: [Node] = []
    private var namespaces = ["xml": [BookMetadataXML.xml]]
    private var nodeCount = 0

    static func parse(_ data: Data) -> Node? {
        let delegate = BookMetadataXML()
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
