import Darwin
import Foundation
import IOKit

enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

public enum SMCResult: UInt8, CustomStringConvertible {
    case success = 0x00
    case error = 0x01
    case commCollision = 0x80
    case spuriousData = 0x81
    case badCommand = 0x82
    case badParameter = 0x83
    case notFound = 0x84
    case notReadable = 0x85
    case notWritable = 0x86
    case keySizeMismatch = 0x87
    case framingError = 0x88
    case badArgumentError = 0x89

    public var description: String {
        let name: String
        switch self {
        case .success: name = "success"
        case .error: name = "error"
        case .commCollision: name = "commCollision"
        case .spuriousData: name = "spuriousData"
        case .badCommand: name = "badCommand"
        case .badParameter: name = "badParameter"
        case .notFound: name = "notFound"
        case .notReadable: name = "notReadable"
        case .notWritable: name = "notWritable"
        case .keySizeMismatch: name = "keySizeMismatch"
        case .framingError: name = "framingError"
        case .badArgumentError: name = "badArgumentError"
        }
        return "\(name) (0x\(String(rawValue, radix: 16)))"
    }
}

public enum SMCError: LocalizedError {
    case driverNotFound
    case openFailed(kern_return_t)
    case badStructLayout(Int)
    case badKey(String)
    case ioKit(kern_return_t)
    case firmware(key: String, result: UInt8)

    public var errorDescription: String? {
        switch self {
        case .driverNotFound:
            return "AppleSMC service was not found"
        case .openFailed(let code):
            return "failed to open AppleSMC: 0x\(String(code, radix: 16))"
        case .badStructLayout(let stride):
            return "SMC ABI struct has unexpected stride \(stride), expected 80"
        case .badKey(let key):
            return "SMC keys must be exactly four ASCII characters: \(key)"
        case .ioKit(let code):
            return "IOKit returned 0x\(String(code, radix: 16))"
        case .firmware(let key, let result):
            let decoded = SMCResult(rawValue: result)?.description ?? "unknown (0x\(String(result, radix: 16)))"
            return "SMC firmware rejected \(key): \(decoded)"
        }
    }
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

public struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

public struct SMCKeyInfo {
    public let size: UInt32
    public let typeCode: UInt32
    public let attributes: UInt8

    public var typeName: String {
        fourCCString(typeCode)
    }
}

public struct SMCValue {
    public let key: String
    public let info: SMCKeyInfo
    public let bytes: [UInt8]

    public var number: Double? {
        SMCCodec.decodeNumber(bytes: bytes, typeName: info.typeName)
    }
}

public final class SMCClient {
    private let connection: io_connect_t
    // Key metadata is immutable per boot; callers recreate the client after
    // failures, which naturally resets this cache.
    private var keyInfoCache: [String: SMCKeyInfo] = [:]

    public init() throws {
        let stride = MemoryLayout<SMCParamStruct>.stride
        guard stride == 80 else {
            throw SMCError.badStructLayout(stride)
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCError.driverNotFound
        }
        defer { IOObjectRelease(service) }

        var opened: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
        guard result == kIOReturnSuccess else {
            throw SMCError.openFailed(result)
        }
        connection = opened
    }

    deinit {
        IOServiceClose(connection)
    }

    public func keyExists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        if let cached = keyInfoCache[key] {
            return cached
        }

        var input = SMCParamStruct()
        input.key = try fourCharCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        let output = try call(input)
        try checkFirmwareResult(output.result, key: key)

        let info = SMCKeyInfo(
            size: output.keyInfo.dataSize,
            typeCode: output.keyInfo.dataType,
            attributes: output.keyInfo.dataAttributes
        )
        keyInfoCache[key] = info
        return info
    }

    public func readKey(_ key: String) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = try fourCharCode(key)
        input.keyInfo.dataSize = info.size
        input.data8 = SMCCommand.readBytes.rawValue

        let output = try call(input)
        try checkFirmwareResult(output.result, key: key)

        let bytes = Array(bytesFromTuple(output.bytes).prefix(Int(info.size)))
        return SMCValue(key: key, info: info, bytes: bytes)
    }

    public func writeKey(_ key: String, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = try fourCharCode(key)
        input.keyInfo.dataSize = info.size
        input.data8 = SMCCommand.writeBytes.rawValue
        input.bytes = tupleFromBytes(bytes)

        let output = try call(input)
        try checkFirmwareResult(output.result, key: key)
    }

    public func enumerateKeys(maximum: Int? = nil) throws -> [String] {
        let countValue = try readKey("#KEY")
        guard let total = countValue.number else { return [] }
        let bounded = min(Int(total), maximum ?? Int(total))
        guard bounded > 0 else { return [] }

        return try (0..<bounded).compactMap { index in
            var input = SMCParamStruct()
            input.data8 = SMCCommand.readIndex.rawValue
            input.data32 = UInt32(index)
            let output = try call(input)
            guard output.result == SMCResult.success.rawValue else { return nil }
            return fourCCString(output.key)
        }
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            throw SMCError.ioKit(result)
        }
        return output
    }

    private func checkFirmwareResult(_ result: UInt8, key: String) throws {
        guard result == SMCResult.success.rawValue else {
            throw SMCError.firmware(key: key, result: result)
        }
    }
}

enum SMCCodec {
    static func decodeNumber(bytes: [UInt8], typeName: String) -> Double? {
        switch typeName {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw =
                UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: raw))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "ui8 ", "flag":
            guard let first = bytes.first else { return nil }
            return Double(first)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw)
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw =
                (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
            return Double(raw)
        default:
            return nil
        }
    }

    static func encodeNumber(_ value: Double, for info: SMCKeyInfo) -> [UInt8] {
        switch info.typeName {
        case "flt ":
            let raw = Float(value).bitPattern
            return [
                UInt8(raw & 0xff),
                UInt8((raw >> 8) & 0xff),
                UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 24) & 0xff),
            ]
        case "fpe2":
            let raw = UInt16(max(0, min(Double(UInt16.max), (value * 4.0).rounded())))
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui8 ", "flag":
            return [UInt8(max(0, min(255, value.rounded())))]
        case "ui16":
            let raw = UInt16(max(0, min(Double(UInt16.max), value.rounded())))
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui32":
            let raw = UInt32(max(0, min(Double(UInt32.max), value.rounded())))
            return [
                UInt8((raw >> 24) & 0xff),
                UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 8) & 0xff),
                UInt8(raw & 0xff),
            ]
        default:
            let raw = Float(value).bitPattern
            return [
                UInt8(raw & 0xff),
                UInt8((raw >> 8) & 0xff),
                UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 24) & 0xff),
            ]
        }
    }
}

func fourCharCode(_ key: String) throws -> UInt32 {
    guard key.utf8.count == 4 else {
        throw SMCError.badKey(key)
    }

    return key.utf8.reduce(UInt32(0)) { result, byte in
        (result << 8) | UInt32(byte)
    }
}

func fourCCString(_ value: UInt32) -> String {
    let bytes = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

func bytesFromTuple(_ tuple: SMCBytes) -> [UInt8] {
    [
        tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7,
        tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15,
        tuple.16, tuple.17, tuple.18, tuple.19, tuple.20, tuple.21, tuple.22, tuple.23,
        tuple.24, tuple.25, tuple.26, tuple.27, tuple.28, tuple.29, tuple.30, tuple.31,
    ]
}

func tupleFromBytes(_ bytes: [UInt8]) -> SMCBytes {
    let padded = Array(bytes.prefix(32)) + Array(repeating: 0, count: max(0, 32 - bytes.count))
    return (
        padded[0], padded[1], padded[2], padded[3], padded[4], padded[5], padded[6], padded[7],
        padded[8], padded[9], padded[10], padded[11], padded[12], padded[13], padded[14], padded[15],
        padded[16], padded[17], padded[18], padded[19], padded[20], padded[21], padded[22], padded[23],
        padded[24], padded[25], padded[26], padded[27], padded[28], padded[29], padded[30], padded[31]
    )
}
