import Foundation
import Testing

@testable import MacFanCore

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
    #expect(response.protocolVersion == 2)
    #expect(response.helperVersion == nil)
    #expect(response.actualRPM == 4000)
    #expect(response.mode == 3)
    #expect(response.contested == true)
}

@Test func helperResponseRoundTripsExtendedFields() throws {
    let response = HelperResponse(id: "a", ok: true, message: "ok", helperVersion: "3.0", actualRPM: 4000, mode: 3, contested: true)
    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(HelperResponse.self, from: data)
    #expect(decoded.protocolVersion == HelperResponse.currentProtocolVersion)
    #expect(decoded.helperVersion == "3.0")
    #expect(decoded.actualRPM == 4000)
    #expect(decoded.mode == 3)
    #expect(decoded.contested == true)
}

@Test func helperCommandRoundTripsShutdownAction() throws {
    let command = HelperCommand(action: .shutdown)
    let data = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(HelperCommand.self, from: data)
    #expect(decoded.action == .shutdown)
    #expect(decoded.id == command.id)
}

@Test func helperCommandDefaultsToAllFans() throws {
    let command = HelperCommand(action: .setPercent, percent: 50)
    let data = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(HelperCommand.self, from: data)
    #expect(decoded.fanIndexes == nil)
    #expect(decoded.percent == 50)
}

@Test func helperResponseRoundTripsPerFanResults() throws {
    let response = HelperResponse(
        id: "a",
        ok: true,
        message: "ok",
        actualRPM: 2100,
        mode: 1,
        contested: true,
        fans: [
            HelperFanResult(index: 0, targetRPM: 2000, actualRPM: 2100, mode: 1, contested: false),
            HelperFanResult(index: 1, targetRPM: 2200, actualRPM: 3400, mode: 0, contested: true),
        ]
    )
    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(HelperResponse.self, from: data)
    #expect(decoded.fans?.count == 2)
    #expect(decoded.fans?[1].contested == true)
    #expect(decoded.fans?[0].targetRPM == 2000)
}

@Test func helperCommandDecodesLegacyPayloadWithoutFanIndexesOrPercent() throws {
    let json = #"{"id":"a","action":"automatic","allowDangerous":false,"allowZero":false,"createdAt":0}"#
        .data(using: .utf8)!
    let command = try JSONDecoder().decode(HelperCommand.self, from: json)
    #expect(command.action == .automatic)
    #expect(command.fanIndexes == nil)
    #expect(command.percent == nil)
}

@Test func legacyDaemonWouldRejectUnknownAction() throws {
    // A protocol-2 daemon fails to decode actions it does not know, replying
    // ok=false; the app treats that as "shutdown unsupported" and re-registers.
    let json = #"{"id":"a","action":"selfDestruct","fanIndex":0,"allowDangerous":false,"allowZero":false,"createdAt":0}"#
        .data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(HelperCommand.self, from: json)
    }
}
