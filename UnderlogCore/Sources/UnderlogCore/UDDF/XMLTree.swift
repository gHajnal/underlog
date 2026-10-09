import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A minimal in-memory XML element tree, enough for reading interchange files.
public final class XMLElementNode: @unchecked Sendable {
    public let name: String
    public let attributes: [String: String]
    public private(set) var children: [XMLElementNode] = []
    public fileprivate(set) var text: String = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    fileprivate func append(_ child: XMLElementNode) { children.append(child) }

    /// The first direct child with this name (case-insensitive, namespace prefix ignored).
    public func child(_ name: String) -> XMLElementNode? {
        children.first { $0.localName == name.lowercased() }
    }

    public func children(_ name: String) -> [XMLElementNode] {
        children.filter { $0.localName == name.lowercased() }
    }

    /// Follows a path of child names, for example `path("informationafterdive", "greatestdepth")`.
    public func path(_ names: String...) -> XMLElementNode? {
        var node: XMLElementNode? = self
        for name in names { node = node?.child(name) }
        return node
    }

    /// All descendants with this name, depth first.
    public func descendants(_ name: String) -> [XMLElementNode] {
        var result: [XMLElementNode] = []
        for child in children {
            if child.localName == name.lowercased() { result.append(child) }
            result += child.descendants(name)
        }
        return result
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The text as a finite number, or nil. UDDF never uses NaN or infinity, and accepting them would
    /// let a damaged file put impossible values into the log.
    public var doubleValue: Double? { Double(trimmedText).flatMap { $0.isFinite ? $0 : nil } }

    var localName: String {
        let lower = name.lowercased()
        if let colon = lower.lastIndex(of: ":") { return String(lower[lower.index(after: colon)...]) }
        return lower
    }
}

enum XMLTreeParser {
    enum ParseError: Error {
        case invalidXML(String)
    }

    static func parse(_ data: Data) throws -> XMLElementNode {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw ParseError.invalidXML(parser.parserError?.localizedDescription ?? "Unreadable XML")
        }
        return root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: XMLElementNode?
        var stack: [XMLElementNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLElementNode(name: elementName, attributes: attributeDict)
            if let parent = stack.last { parent.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let string = String(data: CDATABlock, encoding: .utf8) { stack.last?.text += string }
        }
    }
}
