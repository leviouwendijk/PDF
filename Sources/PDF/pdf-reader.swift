import Foundation
import PDFCore
import PDFApple

/// Consumer-facing entry point; PDFCore stays independent of platform readers.
public enum PDFReader {
    public static func read(_ url: URL) throws -> PDFDocumentSnapshot {
        try PDFNativeReader().read(url)
    }

    public static func read(_ data: Data) throws -> PDFDocumentSnapshot {
        try PDFNativeReader().read(data)
    }
}
