import Testing
@testable import M4FanCore

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
