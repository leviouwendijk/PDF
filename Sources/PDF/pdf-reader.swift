import Foundation
import PDFCore
import PDFApple

/// Consumer-facing entry point; PDFCore stays independent of platform readers.
public enum PDFReader {
    public static func read(
        _ url: URL,
        recognition: PDFRecognitionMode = .none
    ) throws -> PDFDocumentSnapshot {
        try PDFDocumentReader().read(url, recognition: recognition)
    }

    public static func read(
        _ data: Data,
        recognition: PDFRecognitionMode = .none
    ) throws -> PDFDocumentSnapshot {
        try PDFDocumentReader().read(data, recognition: recognition)
    }
}
