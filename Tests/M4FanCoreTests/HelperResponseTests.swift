import Foundation
import Testing

@testable import M4FanCore

@Test func helperResponseDecodesLegacyPayloadWithoutExtendedFields() throws {
    let json = #"{"id":"a","ok":true,"message":"ok","completedAt":0}"#.data(using: .utf8)!
    let response = try JSONDecoder().decode(HelperResponse.self, from: json)
    #expect(response.ok)
    #expect(response.id == "a")
    #expect(response.protocolVersion == nil)
    #expect(response.actualRPM == nil)
    #expect(response.mode == nil)
    #expect(response.contested == nil)
}

@Test func helperResponseDecodesExtendedFields() throws {
    let json = #"{"id":"a","ok":true,"message":"ok","completedAt":0,"protocolVersion":2,"actualRPM":4000,"mode":3,"contested":true}"#.data(
        using: .utf8)!
    let response = try JSONDecoder().decode(HelperResponse.self, from: json)
    #expect(response.protocolVersion == HelperResponse.currentProtocolVersion)
    #expect(response.actualRPM == 4000)
    #expect(response.mode == 3)
    #expect(response.contested == true)
}

@Test func helperResponseRoundTripsExtendedFields() throws {
    let response = HelperResponse(id: "a", ok: true, message: "ok", actualRPM: 4000, mode: 3, contested: true)
    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(HelperResponse.self, from: data)
    #expect(decoded.protocolVersion == HelperResponse.currentProtocolVersion)
    #expect(decoded.actualRPM == 4000)
    #expect(decoded.mode == 3)
    #expect(decoded.contested == true)
}
