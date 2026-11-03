import Schema
import Position

// Schema descriptions match synthesized Encodable output. The validated
// PDFCore initializers remain responsible for construction invariants.
// Position.Offset<UTF16> already owns its exact encoded representation.

extension PDFRectangle: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .object(properties: [
            JSONSchema.number("x", required: true),
            JSONSchema.number("y", required: true),
            JSONSchema.number("width", required: true),
            JSONSchema.number("height", required: true)
        ], additionalProperties: .disallowed)
    }
}

extension PDFPageRegion: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .object(properties: [
            JSONSchema.integer("pageIndex", required: true),
            JSONSchema.property("rectangle", schema: PDFRectangle.jsonschema, required: true)
        ], additionalProperties: .disallowed)
    }
}

extension PDFElementOrigin: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .string(cases: Self.allCases.map(\.rawValue))
    }
}

extension PDFTextReference: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        let fingerprint = JSONSchema.object(properties: [
            JSONSchema.string("algorithm", required: true),
            JSONSchema.string("value", required: true)
        ], additionalProperties: .disallowed)
        return .object(properties: [
            JSONSchema.integer("pageIndex", required: true),
            JSONSchema.string("snapshotID", required: true),
            JSONSchema.property("snapshotFingerprint", schema: fingerprint, required: true),
            JSONSchema.property("start", schema: Position.Offset<Position.Unit.UTF16>.jsonschema, required: true),
            JSONSchema.property("end", schema: Position.Offset<Position.Unit.UTF16>.jsonschema, required: true)
        ], additionalProperties: .disallowed)
    }
}

extension PDFLineObservation: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .object(properties: [
            JSONSchema.string("id", required: true),
            JSONSchema.property("text", schema: String?.jsonschema),
            JSONSchema.property("origin", schema: PDFElementOrigin.jsonschema, required: true),
            JSONSchema.property("confidence", schema: Double?.jsonschema),
            JSONSchema.property("textReferences", schema: [PDFTextReference].jsonschema, required: true),
            JSONSchema.property("regions", schema: [PDFPageRegion].jsonschema, required: true)
        ], additionalProperties: .disallowed)
    }
}
