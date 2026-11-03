import Primitives

public typealias PDFStructureGraph = Graph<String, PDFElement, String, PDFRelationKind>

/// Immutable interpretation of one PDF source version. Graph node and edge IDs
/// are deterministic, source-scoped IDs supplied by the extraction producer.
public struct PDFDocumentSnapshot: Sendable {
    public let source: PDFSource
    public let pages: [PDFPageRecord]
    public let graph: PDFStructureGraph

    public init(source: PDFSource, pages: [PDFPageRecord], graph: PDFStructureGraph) throws {
        for (index, page) in pages.enumerated() {
            guard page.index == index else { throw PDFModelError.noncontiguous_pages }
            var ids = Set<String>()
            for text in page.textSnapshots {
                guard ids.insert(text.id).inserted else {
                    throw PDFModelError.duplicate_text_snapshot(text.id)
                }
            }
        }

        for node in graph.nodes {
            guard !node.id.isEmpty else { throw PDFModelError.invalid_node_identity }
            for anchor in node.value.anchors {
                switch anchor {
                case .region(let region):
                    guard pages.indices.contains(region.pageIndex) else {
                        throw PDFModelError.invalid_page_index(region.pageIndex)
                    }
                case .text(let reference):
                    guard pages.indices.contains(reference.pageIndex) else {
                        throw PDFModelError.invalid_page_index(reference.pageIndex)
                    }
                    guard let snapshot = pages[reference.pageIndex].textSnapshots.first(where: {
                        $0.id == reference.snapshotID
                    }) else {
                        throw PDFModelError.missing_text_snapshot(reference.snapshotID)
                    }
                    guard snapshot.fingerprint == reference.snapshotFingerprint else {
                        throw PDFModelError.stale_text_snapshot(reference.snapshotID)
                    }
                    guard reference.end.offset <= snapshot.utf16Count else {
                        throw PDFModelError.text_range_out_of_bounds(reference.snapshotID)
                    }
                }
            }
        }

        self.source = source
        self.pages = pages
        self.graph = graph
    }
}
