import Foundation
import Primitives

extension PDFRectangle {
    /// Strict overlap in the same unnormalized PDF page coordinate space.
    public func intersects(_ other: PDFRectangle) -> Bool {
        x < other.x + other.width &&
        other.x < x + width &&
        y < other.y + other.height &&
        other.y < y + height
    }
}

extension PDFDocumentSnapshot {
    public func page(at index: Int) -> PDFPageRecord? {
        guard pages.indices.contains(index) else { return nil }
        return pages[index]
    }

    public func node(id: String) -> PDFStructureGraph.Node? {
        graph.nodes.first(where: { $0.id == id })
    }

    /// Node order is the canonical order retained by the graph.
    public func nodes(onPage pageIndex: Int, kind: PDFElementKind? = nil) -> [PDFStructureGraph.Node] {
        guard pages.indices.contains(pageIndex) else { return [] }
        return graph.nodes.filter { node in
            if let kind, node.value.kind != kind { return false }
            return node.value.anchors.contains { anchor in
                switch anchor {
                case .region(let region):
                    return region.pageIndex == pageIndex
                case .text(let reference):
                    return reference.pageIndex == pageIndex
                }
            }
        }
    }

    /// Retains graph edge order, including parallel edges.
    public func children(of id: String, relation: PDFRelationKind = .contains) -> [PDFStructureGraph.Node] {
        graph.edges.compactMap { edge in
            guard edge.source == id, edge.value == relation else { return nil }
            return node(id: edge.destination)
        }
    }

    /// Returns nodes with explicitly recorded page geometry, not text-only anchors.
    public func nodes(overlapping region: PDFPageRegion, kind: PDFElementKind? = nil) -> [PDFStructureGraph.Node] {
        nodes(onPage: region.pageIndex, kind: kind).filter { node in
            node.value.anchors.contains { anchor in
                guard case .region(let anchoredRegion) = anchor else { return false }
                return anchoredRegion.pageIndex == region.pageIndex &&
                    anchoredRegion.rectangle.intersects(region.rectangle)
            }
        }
    }

    /// Resolve an anchored range only against the exact page text snapshot version.
    public func resolve(_ reference: PDFTextReference) throws -> String {
        guard let page = page(at: reference.pageIndex) else {
            throw PDFModelError.invalid_page_index(reference.pageIndex)
        }
        guard let snapshot = page.textSnapshots.first(where: { $0.id == reference.snapshotID }) else {
            throw PDFModelError.missing_text_snapshot(reference.snapshotID)
        }
        guard snapshot.fingerprint == reference.snapshotFingerprint else {
            throw PDFModelError.stale_text_snapshot(reference.snapshotID)
        }
        guard reference.end.offset <= snapshot.utf16Count else {
            throw PDFModelError.text_range_out_of_bounds(reference.snapshotID)
        }
        let range = NSRange(
            location: reference.start.offset,
            length: reference.end.offset - reference.start.offset
        )
        guard let stringRange = Range(range, in: snapshot.text) else {
            throw PDFModelError.invalid_text_range
        }
        return String(snapshot.text[stringRange])
    }
}
