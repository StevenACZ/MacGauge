import Testing

@testable import MacFanCore

@Test func encodesAndDecodesFloatValues() throws {
    let info = SMCKeyInfo(size: 4, typeCode: try fourCharCode("flt "), attributes: 0)
    let bytes = SMCCodec.encodeNumber(42.5, for: info)

    #expect(SMCCodec.decodeNumber(bytes: bytes, typeName: "flt ") == 42.5)
}

@Test func decodesFixedPointValues() {
    #expect(SMCCodec.decodeNumber(bytes: [0x00, 0x10], typeName: "fpe2") == 4)
    #expect(SMCCodec.decodeNumber(bytes: [0x19, 0x80], typeName: "sp78") == 25.5)
}

@Test func fourCharacterCodesRequireExactlyFourASCIICharacters() throws {
    #expect(fourCCString(try fourCharCode("FNum")) == "FNum")
    #expect(throws: SMCError.self) {
        _ = try fourCharCode("Fan")
    }
}

@Test func fourCCStringFallsBackForNonASCIICodes() {
    #expect(fourCCString(0xFFFF_FFFF) == "????")
}

@Test func roundTripsFixedPointFanValues() throws {
    let info = SMCKeyInfo(size: 2, typeCode: try fourCharCode("fpe2"), attributes: 0)

    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(1_250.25, for: info), typeName: "fpe2") == 1_250.25)
    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(0, for: info), typeName: "fpe2") == 0)
}

@Test func fixedPointEncodeClampsInsteadOfTrapping() throws {
    let info = SMCKeyInfo(size: 2, typeCode: try fourCharCode("fpe2"), attributes: 0)

    // 16383.75 is the largest representable fpe2 value.
    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(1_000_000, for: info), typeName: "fpe2") == 16_383.75)
    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(-500, for: info), typeName: "fpe2") == 0)
}

@Test func roundTripsUnsignedIntegerValues() throws {
    let ui16 = SMCKeyInfo(size: 2, typeCode: try fourCharCode("ui16"), attributes: 0)
    let ui32 = SMCKeyInfo(size: 4, typeCode: try fourCharCode("ui32"), attributes: 0)

    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(4_660, for: ui16), typeName: "ui16") == 4_660)
    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(70_000, for: ui16), typeName: "ui16") == 65_535)
    #expect(
        SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(305_419_896, for: ui32), typeName: "ui32") == 305_419_896)
    #expect(SMCCodec.decodeNumber(bytes: SMCCodec.encodeNumber(-1, for: ui32), typeName: "ui32") == 0)
}

@Test func decodesNegativeTemperatures() {
    #expect(SMCCodec.decodeNumber(bytes: [0xE6, 0x80], typeName: "sp78") == -25.5)
}

@Test func decodeReturnsNilForShortOrEmptyPayloads() {
    #expect(SMCCodec.decodeNumber(bytes: [], typeName: "fpe2") == nil)
    #expect(SMCCodec.decodeNumber(bytes: [0x01], typeName: "ui16") == nil)
    #expect(SMCCodec.decodeNumber(bytes: [], typeName: "ui8 ") == nil)
    #expect(SMCCodec.decodeNumber(bytes: [0x00, 0x00, 0x00], typeName: "ui32") == nil)
    #expect(SMCCodec.decodeNumber(bytes: [0x00, 0x00, 0x00], typeName: "flt ") == nil)
    #expect(SMCCodec.decodeNumber(bytes: [0x01], typeName: "sp78") == nil)
}

@Test func decodeReturnsNilForUnknownTypes() {
    #expect(SMCCodec.decodeNumber(bytes: [0x00, 0x00, 0x00, 0x00], typeName: "ch8*") == nil)
}

@Test func unknownTypeEncodesAsLittleEndianFloat() throws {
    let unknown = SMCKeyInfo(size: 4, typeCode: try fourCharCode("ch8*"), attributes: 0)
    let float = SMCKeyInfo(size: 4, typeCode: try fourCharCode("flt "), attributes: 0)

    #expect(SMCCodec.encodeNumber(42.5, for: unknown) == SMCCodec.encodeNumber(42.5, for: float))
}

@Test func flagValuesRoundTripAsSingleByte() throws {
    let info = SMCKeyInfo(size: 1, typeCode: try fourCharCode("flag"), attributes: 0)

    #expect(SMCCodec.encodeNumber(1, for: info) == [1])
    #expect(SMCCodec.decodeNumber(bytes: [1], typeName: "flag") == 1)
    #expect(SMCCodec.decodeNumber(bytes: [0], typeName: "flag") == 0)
    #expect(SMCCodec.decodeNumber(bytes: [], typeName: "flag") == nil)
}
