import Foundation
import PDFKit
import IO
import Readers
import Position
import Primitives
import PDFCore

public enum PDFReadError: Error, Sendable, Equatable {
    case invalid_document
    case missing_page(Int)
}

/// Native PDF text-layer ingestion only. OCR and layout recovery are separate passes.
public struct PDFNativeReader: Sendable {
    public init() {}

    public func read(_ url: URL) throws -> PDFDocumentSnapshot {
        let result = try DataFileReader(url).read()
        return try read(result.data, origin: url)
    }

    public func read(_ data: Data, origin: URL? = nil) throws -> PDFDocumentSnapshot {
        guard let document = PDFKit.PDFDocument(data: data) else {
            throw PDFReadError.invalid_document
        }

        let source = try PDFSource(
            fingerprint: .fingerprint(for: data),
            byteCount: data.count,
            url: origin
        )
        var pages: [PDFPageRecord] = []
        var nodes: [PDFStructureGraph.Node] = []
        var edges: [PDFStructureGraph.Edge] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw PDFReadError.missing_page(index)
            }

            let mediaBox = page.bounds(for: .mediaBox)
            let rectangle = try PDFRectangle(
                x: Double(mediaBox.minX),
                y: Double(mediaBox.minY),
                width: Double(mediaBox.width),
                height: Double(mediaBox.height)
            )
            let region = try PDFPageRegion(pageIndex: index, rectangle: rectangle)
            let pageID = "page:\(index)"
            var textSnapshots: [PDFPageTextSnapshot] = []

            nodes.append(.init(
                id: pageID,
                value: try PDFElement(kind: .page, origin: .native, anchors: [.region(region)])
            ))

            if let text = page.string, !text.isEmpty {
                let snapshot = try PDFPageTextSnapshot(id: "native", source: .native, text: text)
                textSnapshots.append(snapshot)
                let reference = try PDFTextReference(
                    pageIndex: index,
                    snapshotID: snapshot.id,
                    snapshotFingerprint: snapshot.fingerprint,
                    start: Position.Offset<Position.Unit.UTF16>(0),
                    end: Position.Offset<Position.Unit.UTF16>(snapshot.utf16Count)
                )
                let textID = "page:\(index)/native"
                nodes.append(.init(
                    id: textID,
                    value: try PDFElement(
                        kind: .text,
                        text: text,
                        origin: .native,
                        anchors: [.text(reference)]
                    )
                ))
                edges.append(.init(
                    id: "contains:\(index):native",
                    source: pageID,
                    destination: textID,
                    value: .contains
                ))
            }

            pages.append(try PDFPageRecord(
                index: index,
                bounds: rectangle,
                textSnapshots: textSnapshots
            ))
        }

        return try PDFDocumentSnapshot(
            source: source,
            pages: pages,
            graph: PDFStructureGraph(nodes: nodes, edges: edges)
        )
    }
}
