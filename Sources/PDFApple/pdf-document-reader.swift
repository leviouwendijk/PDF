import Foundation
import Readers
import Position
import Primitives
import PDFCore

/// Native extraction remains the default; Vision recognition is explicit.
public enum PDFRecognitionMode: Sendable {
    case none
    case vision
}

public enum PDFVisionIntegrationError: Error, Sendable, Equatable {
    case source_mismatch
    case page_count_mismatch(Int, Int)
    case page_index_mismatch(Int, Int)
    case line_page_mismatch(Int, Int)
    case already_recognized(Int)
}

/// A single PDF byte version feeds both native and recognized extraction.
public struct PDFDocumentReader: Sendable {
    public init() {}

    public func read(_ url: URL, recognition: PDFRecognitionMode = .none) throws -> PDFDocumentSnapshot {
        let data = try DataFileReader(url).read().data
        return try read(data, origin: url, recognition: recognition)
    }

    public func read(
        _ data: Data,
        origin: URL? = nil,
        recognition: PDFRecognitionMode = .none
    ) throws -> PDFDocumentSnapshot {
        let native = try PDFNativeReader().read(data, origin: origin)
        switch recognition {
        case .none:
            return native
        case .vision:
            return try native.incorporating(PDFVisionReader().extract(data))
        }
    }
}

extension PDFDocumentSnapshot {
    /// Add independent OCR evidence without overwriting native text or graph nodes.
    /// Vision evidence must have been extracted from these exact source bytes.
    public func incorporating(_ extraction: PDFVisionExtraction) throws -> PDFDocumentSnapshot {
        guard extraction.sourceFingerprint == source.fingerprint else {
            throw PDFVisionIntegrationError.source_mismatch
        }
        guard extraction.pages.count == pages.count else {
            throw PDFVisionIntegrationError.page_count_mismatch(pages.count, extraction.pages.count)
        }

        var updatedPages: [PDFPageRecord] = []
        var updatedNodes = graph.nodes
        var updatedEdges = graph.edges

        for index in pages.indices {
            let originalPage = pages[index]
            let recognizedPage = extraction.pages[index]
            guard recognizedPage.index == index else {
                throw PDFVisionIntegrationError.page_index_mismatch(index, recognizedPage.index)
            }
            guard !originalPage.textSnapshots.contains(where: { $0.id == "vision" }) else {
                throw PDFVisionIntegrationError.already_recognized(index)
            }
            for line in recognizedPage.lines {
                guard line.region.pageIndex == index else {
                    throw PDFVisionIntegrationError.line_page_mismatch(index, line.region.pageIndex)
                }
            }

            // Each line has a separate, exact UTF-16 range in this OCR-only text.
            // A newline between lines belongs to neither line's range.
            let recognizedText = recognizedPage.lines.map(\.text).joined(separator: "\n")
            let snapshot = try PDFPageTextSnapshot(
                id: "vision",
                source: .recognized,
                text: recognizedText
            )
            updatedPages.append(try PDFPageRecord(
                index: originalPage.index,
                bounds: originalPage.bounds,
                textSnapshots: originalPage.textSnapshots + [snapshot]
            ))

            let pageID = "page:\(index)"
            let textID = "page:\(index)/vision"
            let fullReference = try PDFTextReference(
                pageIndex: index,
                snapshotID: snapshot.id,
                snapshotFingerprint: snapshot.fingerprint,
                start: Position.Offset<Position.Unit.UTF16>(0),
                end: Position.Offset<Position.Unit.UTF16>(snapshot.utf16Count)
            )
            updatedNodes.append(.init(
                id: textID,
                value: try PDFElement(
                    kind: .text,
                    text: snapshot.text,
                    origin: .recognition,
                    anchors: [.text(fullReference)]
                )
            ))
            updatedEdges.append(.init(
                id: "contains:\(index):vision",
                source: pageID,
                destination: textID,
                value: .contains
            ))

            var offset = 0
            var previousLineID: String?
            for (ordinal, line) in recognizedPage.lines.enumerated() {
                if ordinal > 0 { offset += 1 }
                let start = offset
                offset += line.text.utf16.count
                let lineReference = try PDFTextReference(
                    pageIndex: index,
                    snapshotID: snapshot.id,
                    snapshotFingerprint: snapshot.fingerprint,
                    start: Position.Offset<Position.Unit.UTF16>(start),
                    end: Position.Offset<Position.Unit.UTF16>(offset)
                )
                let lineID = "page:\(index)/vision/line:\(ordinal)"
                updatedNodes.append(.init(
                    id: lineID,
                    value: try PDFElement(
                        kind: .line,
                        text: line.text,
                        origin: .recognition,
                        confidence: line.confidence,
                        anchors: [.text(lineReference), .region(line.region)]
                    )
                ))
                updatedEdges.append(.init(
                    id: "contains:\(index):vision:line:\(ordinal)",
                    source: pageID,
                    destination: lineID,
                    value: .contains
                ))
                updatedEdges.append(.init(
                    id: "extracted_from:\(index):vision:line:\(ordinal)",
                    source: lineID,
                    destination: textID,
                    value: .extracted_from
                ))
                if let previousLineID {
                    updatedEdges.append(.init(
                        id: "follows:\(index):vision:line:\(ordinal)",
                        source: previousLineID,
                        destination: lineID,
                        value: .follows
                    ))
                }
                previousLineID = lineID
            }
        }

        return try PDFDocumentSnapshot(
            source: source,
            pages: updatedPages,
            graph: PDFStructureGraph(nodes: updatedNodes, edges: updatedEdges)
        )
    }
}
