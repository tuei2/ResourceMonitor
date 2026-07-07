import Foundation
import IOKit

// SMC reader for Apple Silicon and Intel Macs.
// All struct fields use native (little-endian on ARM64) byte order.
// The 80-byte raw buffer layout matches the AppleSMC kernel struct exactly.
final class SMCHelper {
    private var connection: io_connect_t = 0
    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCGetKeyInfo: UInt8 = 9
    private let kSMCReadKey: UInt8 = 5

    var isOpen: Bool { connection != 0 }

    func open() -> Bool {
        if connection != 0 { return true }   // Already open — IOServiceOpen would leak if called again
        var mainPort: mach_port_t = 0
        IOMainPort(mach_port_t(0), &mainPort)
        let service = IOServiceGetMatchingService(mainPort, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    // Returns temperature in Celsius. Handles sp78, fpe2, and flt (Apple Silicon).
    func temperature(_ key: String) -> Double? {
        guard let info = keyInfo(key) else { return nil }
        let size = info.dataSize
        guard let bytes = readBytes(key, size: size) else { return nil }

        switch info.dataType {
        case fourCC("sp78"):
            guard size >= 2 else { return nil }
            let hi = Int8(bitPattern: bytes[0])
            let val = Double(hi) + Double(bytes[1]) / 256.0
            return val > 0 && val < 150 ? val : nil

        case fourCC("fpe2"):
            guard size >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let val = Double(raw) / 4.0
            return val > 0 && val < 150 ? val : nil

        case fourCC("flt "):
            // Apple Silicon: 32-bit IEEE float, little-endian in the data buffer
            guard size >= 4 else { return nil }
            let raw: UInt32 = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                            | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let val = Double(Float32(bitPattern: raw))
            return val > 0 && val < 150 ? val : nil

        default:
            return nil
        }
    }

    // Returns fan speed in RPM. On Apple Silicon fans use flt format.
    func fanSpeed(_ key: String) -> Double? {
        guard let info = keyInfo(key) else { return nil }
        let size = info.dataSize
        guard let bytes = readBytes(key, size: size) else { return nil }

        switch info.dataType {
        case fourCC("flt "):
            guard size >= 4 else { return nil }
            let raw: UInt32 = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                            | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float32(bitPattern: raw))

        case fourCC("fpe2"):
            guard size >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0

        default:
            return nil
        }
    }

    // Returns a generic float value (flt  type). Used for power readings (PCPU, PGPU).
    func floatValue(_ key: String) -> Double? {
        guard let info = keyInfo(key), info.dataType == fourCC("flt "),
              let bytes = readBytes(key, size: info.dataSize), info.dataSize >= 4 else { return nil }
        let raw: UInt32 = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                        | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let val = Double(Float32(bitPattern: raw))
        return val > 0 && val < 1000 ? val : nil
    }

    // Writes an fpe2 value (RPM * 4 stored as big-endian UInt16). Used for fan target keys.
    @discardableResult
    func writeFPE2(_ key: String, value: Double) -> Bool {
        let raw = UInt16(max(0, value) * 4)
        return writeBytes(key, bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
    }

    // Writes a ui16 value (big-endian UInt16). Used for FS!  (fan mode bitmask).
    @discardableResult
    func writeUI16(_ key: String, value: UInt16) -> Bool {
        writeBytes(key, bytes: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    // Returns total number of SMC keys on this machine.
    func keyCount() -> Int {
        var input = [UInt8](repeating: 0, count: 80)
        writeKeyLE("#KEY", into: &input)
        writeUInt32LE(4, into: &input, offset: 28)
        input[kSMCData8Offset] = kSMCReadKey
        guard let output = callSMC(&input) else { return 0 }
        let b = output[48..<52]
        return Int(UInt32(b[b.startIndex]) << 24 | UInt32(b[b.startIndex+1]) << 16 |
                   UInt32(b[b.startIndex+2]) << 8  | UInt32(b[b.startIndex+3]))
    }

    // Returns the key name at a given index (used for dynamic sensor discovery).
    func keyAtIndex(_ index: UInt32) -> String? {
        var input = [UInt8](repeating: 0, count: 80)
        writeUInt32LE(index, into: &input, offset: 44)   // data32 = index
        writeUInt32LE(4,     into: &input, offset: 28)   // keyInfo.dataSize hint
        input[kSMCData8Offset] = 8                        // kSMCGetKeyFromIndex
        guard let output = callSMC(&input) else { return nil }
        // Key is returned as big-endian ASCII at offset 0
        let b = [output[0], output[1], output[2], output[3]]
        guard b[0] > 32 && b[0] < 128 else { return nil }
        return String(bytes: b, encoding: .ascii)
    }

    // Returns number of fans from "FNum" key.
    func fanCount() -> Int {
        guard let bytes = readBytes("FNum", size: 1) else { return 0 }
        return Int(bytes[0])
    }

    // MARK: - Private

    @discardableResult
    private func writeBytes(_ key: String, bytes: [UInt8]) -> Bool {
        var input = [UInt8](repeating: 0, count: 80)
        writeKeyLE(key, into: &input)
        writeUInt32LE(UInt32(bytes.count), into: &input, offset: 28)
        input[kSMCData8Offset] = 6 // kSMCWriteKey
        for (i, b) in bytes.prefix(32).enumerated() { input[48 + i] = b }
        return callSMC(&input) != nil
    }

    private struct KeyInfo {
        var dataSize: UInt32
        var dataType: UInt32
    }

    private func keyInfo(_ key: String) -> KeyInfo? {
        var input = [UInt8](repeating: 0, count: 80)
        writeKeyLE(key, into: &input)
        input[kSMCData8Offset] = kSMCGetKeyInfo
        guard let output = callSMC(&input) else { return nil }
        let dataSize = readUInt32LE(output, offset: 28)
        let dataType = readUInt32LE(output, offset: 32)
        guard dataSize > 0 && dataSize <= 32 else { return nil }
        return KeyInfo(dataSize: dataSize, dataType: dataType)
    }

    private func readBytes(_ key: String, size: UInt32) -> [UInt8]? {
        var input = [UInt8](repeating: 0, count: 80)
        writeKeyLE(key, into: &input)
        writeUInt32LE(size, into: &input, offset: 28)
        input[kSMCData8Offset] = kSMCReadKey
        guard let output = callSMC(&input) else { return nil }
        return Array(output[48..<(48 + Int(size))])
    }

    private func callSMC(_ input: inout [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let result = input.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection,
                                         kSMCHandleYPCEvent,
                                         inPtr.baseAddress, 80,
                                         outPtr.baseAddress, &outSize)
            }
        }
        return result == kIOReturnSuccess ? output : nil
    }

    // SMC param struct byte layout (80 bytes, all multi-byte fields are little-endian):
    // offset  0: key         (UInt32 LE — FourCC stored as native integer)
    // offset  4: vers        (6 bytes)
    // offset 10: padding     (2 bytes)
    // offset 12: pLimitData  (16 bytes)
    // offset 28: keyInfo     (dataSize UInt32 LE, dataType UInt32 LE, dataAttrib 1B)
    // offset 37–41: padding
    // offset 42: data8       (1 byte) ← SMC command (9=GetKeyInfo, 5=ReadKey)
    // offset 43: padding
    // offset 44: data32      (UInt32 LE)
    // offset 48: bytes       (32 bytes) ← returned key data (little-endian native format)

    private let kSMCData8Offset = 42

    private func writeKeyLE(_ key: String, into buf: inout [UInt8]) {
        let cc = fourCC(key)
        writeUInt32LE(cc, into: &buf, offset: 0)
    }

    private func writeUInt32LE(_ value: UInt32, into buf: inout [UInt8], offset: Int) {
        buf[offset + 0] = UInt8( value        & 0xFF)
        buf[offset + 1] = UInt8((value >>  8) & 0xFF)
        buf[offset + 2] = UInt8((value >> 16) & 0xFF)
        buf[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func readUInt32LE(_ buf: [UInt8], offset: Int) -> UInt32 {
        UInt32(buf[offset])
            | UInt32(buf[offset + 1]) << 8
            | UInt32(buf[offset + 2]) << 16
            | UInt32(buf[offset + 3]) << 24
    }
}

func fourCC(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) | scalar.value
    }
    return result
}
