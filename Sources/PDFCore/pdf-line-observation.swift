import Foundation
import Primitives

/// An immutable, non-authoritative projection of a graph line node.
/// Original anchors remain available in PDFDocumentSnapshot.graph.
public struct PDFLineObservation: Sendable, Hashable, Encodable {
    public let id: String
    public let text: String?
    public let origin: PDFElementOrigin
    public let confidence: Double?
    public let textReferences: [PDFTextReference]
    public let regions: [PDFPageRegion]

    public init?(node: PDFStructureGraph.Node) {
        guard node.value.kind == .line else { return nil }
        self.id = node.id
        self.text = node.value.text
        self.origin = node.value.origin
        self.confidence = node.value.confidence
        self.textReferences = node.value.anchors.compactMap { anchor in
            guard case .text(let reference) = anchor else { return nil }
            return reference
        }
        self.regions = node.value.anchors.compactMap { anchor in
            guard case .region(let region) = anchor else { return nil }
            return region
        }
    }
}

public extension PDFDocumentSnapshot {
    /// Graph order, without synthesizing layout order or collapsing OCR alternatives.
    func lines(onPage index: Int) -> [PDFLineObservation] {
        nodes(onPage: index, kind: .line).compactMap { PDFLineObservation(node: $0) }
    }

    /// Returns full line observations when at least one region anchor intersects.
    func lines(overlapping region: PDFPageRegion) -> [PDFLineObservation] {
        nodes(overlapping: region, kind: .line).compactMap { PDFLineObservation(node: $0) }
    }
}
