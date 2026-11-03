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

                // PDFKit owns the physical line segmentation. Ranges remain anchored
                // to the original unmodified page text, never reconstructed text.
                let characterCount = min(page.numberOfCharacters, snapshot.utf16Count)
                if characterCount > 0,
                   let wholePage = page.selection(for: NSRange(location: 0, length: characterCount)) {
                    var previousLineID: String?
                    var lineOrdinal = 0

                    for line in wholePage.selectionsByLine() {
                        // Avoid claiming a contiguous span for discontiguous selections.
                        guard line.numberOfTextRanges(on: page) == 1 else { continue }
                        let range = line.range(at: 0, on: page)
                        guard range.location != NSNotFound, range.length > 0,
                              range.location <= snapshot.utf16Count,
                              range.length <= snapshot.utf16Count - range.location,
                              let stringRange = Range(range, in: text) else { continue }

                        let lineText = String(text[stringRange])
                        guard !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }

                        let bounds = line.bounds(for: page)
                        guard bounds.minX.isFinite, bounds.minY.isFinite,
                              bounds.width.isFinite, bounds.height.isFinite,
                              bounds.width > 0, bounds.height > 0 else { continue }

                        let lineRegion = try PDFPageRegion(
                            pageIndex: index,
                            rectangle: PDFRectangle(
                                x: Double(bounds.minX),
                                y: Double(bounds.minY),
                                width: Double(bounds.width),
                                height: Double(bounds.height)
                            )
                        )
                        let textReference = try PDFTextReference(
                            pageIndex: index,
                            snapshotID: snapshot.id,
                            snapshotFingerprint: snapshot.fingerprint,
                            start: Position.Offset<Position.Unit.UTF16>(range.location),
                            end: Position.Offset<Position.Unit.UTF16>(range.location + range.length)
                        )
                        let lineID = "page:\(index)/line:\(lineOrdinal)"
                        nodes.append(.init(
                            id: lineID,
                            value: try PDFElement(
                                kind: .line,
                                text: lineText,
                                origin: .native,
                                anchors: [.text(textReference), .region(lineRegion)]
                            )
                        ))
                        edges.append(.init(
                            id: "contains:\(index):line:\(lineOrdinal)",
                            source: pageID,
                            destination: lineID,
                            value: .contains
                        ))
                        if let previousLineID {
                            edges.append(.init(
                                id: "follows:\(index):line:\(lineOrdinal)",
                                source: previousLineID,
                                destination: lineID,
                                value: .follows
                            ))
                        }
                        previousLineID = lineID
                        lineOrdinal += 1
                    }
                }
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
