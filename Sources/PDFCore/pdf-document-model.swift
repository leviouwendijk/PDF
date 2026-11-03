import Foundation
import IO
import Position

public enum PDFModelError: Error, Sendable, Equatable {
    case invalid_byte_count(Int)
    case invalid_geometry
    case invalid_page_index(Int)
    case invalid_identity
    case invalid_text_range
    case invalid_confidence
    case noncontiguous_pages
    case duplicate_text_snapshot(String)
    case missing_text_snapshot(String)
    case stale_text_snapshot(String)
    case text_range_out_of_bounds(String)
    case invalid_node_identity
}

/// A source identity is tied to the exact bytes that were read.
/// IO's current fingerprint is not a cryptographic authenticity guarantee.
public struct PDFSource: Sendable, Hashable {
    public let fingerprint: ContentFingerprint
    public let byteCount: Int
    public let url: URL?

    public init(fingerprint: ContentFingerprint, byteCount: Int, url: URL? = nil) throws {
        guard byteCount >= 0 else { throw PDFModelError.invalid_byte_count(byteCount) }
        self.fingerprint = fingerprint
        self.byteCount = byteCount
        self.url = url
    }
}

/// Coordinates in the PDF page's unnormalized PDFKit page space.
public struct PDFRectangle: Sendable, Hashable, Encodable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { throw PDFModelError.invalid_geometry }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PDFPageRegion: Sendable, Hashable, Encodable {
    public let pageIndex: Int
    public let rectangle: PDFRectangle

    public init(pageIndex: Int, rectangle: PDFRectangle) throws {
        guard pageIndex >= 0 else { throw PDFModelError.invalid_page_index(pageIndex) }
        self.pageIndex = pageIndex
        self.rectangle = rectangle
    }
}

public enum PDFTextSource: String, Sendable {
    case native
    case recognized
    case reconstructed
}

/// IDs are unique within a page; text fingerprints bind references to exact content.
public struct PDFPageTextSnapshot: Sendable, Hashable {
    public let id: String
    public let source: PDFTextSource
    public let text: String

    public init(id: String, source: PDFTextSource, text: String) throws {
        guard !id.isEmpty else { throw PDFModelError.invalid_identity }
        self.id = id
        self.source = source
        self.text = text
    }

    public var fingerprint: ContentFingerprint { .fingerprint(for: text) }
    public var utf16Count: Int { text.utf16.count }
}

public struct PDFPageRecord: Sendable, Hashable {
    public let index: Int
    public let bounds: PDFRectangle
    public let textSnapshots: [PDFPageTextSnapshot]

    public init(index: Int, bounds: PDFRectangle, textSnapshots: [PDFPageTextSnapshot]) throws {
        guard index >= 0 else { throw PDFModelError.invalid_page_index(index) }
        self.index = index
        self.bounds = bounds
        self.textSnapshots = textSnapshots
    }
}

/// UTF-16 offsets match PDFKit's NSRange units, not Unicode character indices.
public struct PDFTextReference: Sendable, Hashable, Encodable {
    public let pageIndex: Int
    public let snapshotID: String
    public let snapshotFingerprint: ContentFingerprint
    public let start: Position.Offset<Position.Unit.UTF16>
    public let end: Position.Offset<Position.Unit.UTF16>

    public init(
        pageIndex: Int,
        snapshotID: String,
        snapshotFingerprint: ContentFingerprint,
        start: Position.Offset<Position.Unit.UTF16>,
        end: Position.Offset<Position.Unit.UTF16>
    ) throws {
        guard pageIndex >= 0 else { throw PDFModelError.invalid_page_index(pageIndex) }
        guard !snapshotID.isEmpty else { throw PDFModelError.invalid_identity }
        guard start <= end else { throw PDFModelError.invalid_text_range }
        self.pageIndex = pageIndex
        self.snapshotID = snapshotID
        self.snapshotFingerprint = snapshotFingerprint
        self.start = start
        self.end = end
    }
}

public enum PDFAnchor: Sendable, Hashable {
    case region(PDFPageRegion)
    case text(PDFTextReference)
}

public enum PDFElementKind: String, Sendable {
    case page
    case text
    case block
    case line
    case table
    case field
}

public enum PDFElementOrigin: String, Sendable, CaseIterable, Encodable {
    case native
    case recognition
    case reconstruction
    case inference
    case manual
}

public struct PDFElement: Sendable, Hashable {
    public let kind: PDFElementKind
    public let text: String?
    public let origin: PDFElementOrigin
    public let confidence: Double?
    public let anchors: [PDFAnchor]

    public init(
        kind: PDFElementKind,
        text: String? = nil,
        origin: PDFElementOrigin,
        confidence: Double? = nil,
        anchors: [PDFAnchor]
    ) throws {
        if let confidence {
            guard confidence.isFinite, (0...1).contains(confidence) else {
                throw PDFModelError.invalid_confidence
            }
        }
        self.kind = kind
        self.text = text
        self.origin = origin
        self.confidence = confidence
        self.anchors = anchors
    }
}

public enum PDFRelationKind: String, Sendable {
    case contains
    case follows
    case extracted_from
    case alternative_to
    case candidate_for
    case supports
    case contradicts
}
