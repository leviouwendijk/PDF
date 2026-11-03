import Foundation
import CoreGraphics
import Vision
import Readers
import IO
import PDFCore

public enum PDFVisionError: Error, Sendable {
    case invalid_document
    case missing_page(Int)
    case invalid_page_geometry(Int)
    case rendering_failed(Int)
}

/// A Vision result is independent evidence, not a replacement for native PDF text.
public struct PDFVisionLine: Sendable {
    public let text: String
    public let confidence: Double
    public let region: PDFPageRegion
}

public struct PDFVisionPage: Sendable {
    public let index: Int
    public let lines: [PDFVisionLine]
}

/// Vision observations bound to the PDF bytes they came from.
public struct PDFVisionExtraction: Sendable {
    public let sourceFingerprint: ContentFingerprint
    public let pages: [PDFVisionPage]

    init(sourceFingerprint: ContentFingerprint, pages: [PDFVisionPage]) {
        self.sourceFingerprint = sourceFingerprint
        self.pages = pages
    }
}

/// OCR over rendered PDF pages; does not modify a PDFDocumentSnapshot.
public struct PDFVisionReader: Sendable {
    public init() {}

    /// Unlike recognize, extract retains the originating PDF identity.
    public func extract(_ url: URL) throws -> PDFVisionExtraction {
        let data = try DataFileReader(url).read().data
        return try extract(data)
    }

    public func extract(_ data: Data) throws -> PDFVisionExtraction {
        let pages = try recognize(data)
        return PDFVisionExtraction(sourceFingerprint: .fingerprint(for: data), pages: pages)
    }

    public func recognize(_ url: URL) throws -> [PDFVisionPage] {
        let source = try DataFileReader(url).read()
        return try recognize(source.data)
    }

    public func recognize(_ data: Data) throws -> [PDFVisionPage] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            throw PDFVisionError.invalid_document
        }

        var pages: [PDFVisionPage] = []
        for index in 0..<document.numberOfPages {
            guard let page = document.page(at: index + 1) else {
                throw PDFVisionError.missing_page(index)
            }
            let mediaBox = page.getBoxRect(.mediaBox)
            guard mediaBox.width.isFinite, mediaBox.height.isFinite,
                  mediaBox.width > 0, mediaBox.height > 0 else {
                throw PDFVisionError.invalid_page_geometry(index)
            }

            // 144 dpi nominally, bounded to 4096 pixels on the longer side.
            let scale = min(CGFloat(2), CGFloat(4096) / max(mediaBox.width, mediaBox.height))
            let width = max(1, Int((mediaBox.width * scale).rounded(.up)))
            let height = max(1, Int((mediaBox.height * scale).rounded(.up)))
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw PDFVisionError.rendering_failed(index)
            }

            let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(canvas)
            let pdfToImage = page.getDrawingTransform(
                .mediaBox,
                rect: canvas,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.saveGState()
            context.concatenate(pdfToImage)
            context.drawPDFPage(page)
            context.restoreGState()
            guard let image = context.makeImage() else {
                throw PDFVisionError.rendering_failed(index)
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

            // Presentation order only; not a semantic reading-order guarantee.
            let observations = (request.results ?? []).sorted { lhs, rhs in
                let verticalGap = lhs.boundingBox.midY - rhs.boundingBox.midY
                if abs(verticalGap) > 0.005 { return verticalGap > 0 }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

            let imageToPDF = pdfToImage.inverted()
            var lines: [PDFVisionLine] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                // Vision uses normalized image coordinates with a bottom-left origin.
                let imageBounds = CGRect(
                    x: observation.boundingBox.minX * CGFloat(width),
                    y: observation.boundingBox.minY * CGFloat(height),
                    width: observation.boundingBox.width * CGFloat(width),
                    height: observation.boundingBox.height * CGFloat(height)
                )
                let pdfBounds = imageBounds.applying(imageToPDF).standardized
                guard pdfBounds.minX.isFinite, pdfBounds.minY.isFinite,
                      pdfBounds.width.isFinite, pdfBounds.height.isFinite,
                      pdfBounds.width > 0, pdfBounds.height > 0 else { continue }

                let region = try PDFPageRegion(
                    pageIndex: index,
                    rectangle: PDFRectangle(
                        x: Double(pdfBounds.minX),
                        y: Double(pdfBounds.minY),
                        width: Double(pdfBounds.width),
                        height: Double(pdfBounds.height)
                    )
                )
                lines.append(PDFVisionLine(
                    text: text,
                    confidence: Double(candidate.confidence),
                    region: region
                ))
            }
            pages.append(PDFVisionPage(index: index, lines: lines))
        }
        return pages
    }
}
