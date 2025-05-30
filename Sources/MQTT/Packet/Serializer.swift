//
//  Serializer.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation

enum Serializer {
    /// write variable length
    static func writeVarint(_ value: Int, to byteBuffer: inout DataBuffer) {
        var value = value
        repeat {
            let byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byteBuffer.writeByte(byte | 0x80)
            } else {
                byteBuffer.writeByte(byte)
            }
        } while value != 0
    }
    /// read variable length from bytebuffer
    static func readVarint(from byteBuffer: inout DataBuffer) throws -> Int {
        var value = 0
        var shift = 0
        repeat {
            guard let byte: UInt8 = byteBuffer.readByte() else { throw MQTTError.incompletePacket }
            value += (Int(byte) & 0x7F) << shift
            if byte & 0x80 == 0 {
                break
            }
            shift += 7
        } while true
        return value
    }
    static func varintPacketSize(_ value: Int) -> Int {
        var value = value
        var size = 0
        repeat {
            size += 1
            value >>= 7
        } while value != 0
        return size
    }
    /// write string to byte buffer
    static func writeString(_ string: String, to byteBuffer: inout DataBuffer) throws {
        guard let data = string.data(using: .utf8) else{
            throw MQTTError.packetError(.badParameter)
        }
        guard data.count < 65536 else { throw MQTTError.packetError(.badParameter)}
        byteBuffer.writeInteger(UInt16(data.count))
        byteBuffer.writeData(data)
    }
    /// read string from bytebuffer
    static func readString(from byteBuffer: inout DataBuffer) throws -> String {
        guard let length: UInt16 = byteBuffer.readInteger() else { throw MQTTError.decodeError(.unexpectedTokens) }
        guard let string = byteBuffer.readString(length: Int(length)) else { throw MQTTError.decodeError(.unexpectedTokens) }
        return string
    }
    
    /// write buffer to byte buffer
    static func writeBuffer(_ buffer: DataBuffer, to byteBuffer: inout DataBuffer) throws {
        let length = buffer.readableBytes
        guard length < 65536 else { throw MQTTError.packetError(.badParameter) }
        var buffer = buffer
        byteBuffer.writeInteger(UInt16(length))
        byteBuffer.writeBuffer(&buffer)
    }
    /// read data from bytebuffer
    static func readBuffer(from byteBuffer: inout DataBuffer) throws -> DataBuffer {
        guard let length: UInt16 = byteBuffer.readInteger() else { throw MQTTError.decodeError(.unexpectedTokens) }
        guard let buffer = byteBuffer.readBuffer(length: Int(length)) else { throw MQTTError.decodeError(.unexpectedTokens) }
        return buffer
    }
    
    /// write data
    static func writeData(_ data: Data, to byteBuffer: inout DataBuffer) throws {
        guard data.count < 65536 else { throw MQTTError.packetError(.badParameter) }
        byteBuffer.writeInteger(UInt16(data.count))
        byteBuffer.writeData(data)
    }
    /// read data from bytebuffer
    static func readData(from byteBuffer: inout DataBuffer) throws -> Data {
        guard let length: UInt16 = byteBuffer.readInteger() else { throw MQTTError.decodeError(.unexpectedTokens) }
        guard let data = byteBuffer.readData(length: Int(length)) else { throw MQTTError.decodeError(.unexpectedTokens) }
        return data
    }    
}
