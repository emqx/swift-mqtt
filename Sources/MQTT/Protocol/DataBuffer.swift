//
//  ByteBuffer.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/16.
//

import Foundation

@usableFromInline
struct DataBuffer:Sendable,Equatable{
    @usableFromInline private(set) var data:Data = Data()
    @usableFromInline var readIndex:Int = 0
    
    @inlinable
    init(data: Data = Data()) {
        self.data = data
    }
    /// buffer read and write
    @inlinable
    mutating func writeBuffer(_ buffer: inout DataBuffer){
        buffer.readIndex = buffer.data.count
        self.data.append(buffer.data)
    }
    @inlinable
    mutating func readBuffer(length:Int)->DataBuffer?{
        guard let data = self.readData(length: length) else{
            return nil
        }
        return DataBuffer(data: data)
    }
    
    /// data read and write
    @inlinable
    mutating func writeData(_ data: Data){
        self.data.append(data)
    }
    /// read all data when length is nil
    @inlinable
    mutating func readData(length:Int? = nil)->Data?{
        let len = length ?? self.readableBytes
        guard self.readableBytes >= len else {
            return nil
        }
        let idx = readIndex
        readIndex += len
        return self.data.subdata(in: idx..<readIndex)
    }
    
    /// string read and write
    @inlinable
    mutating func writeString(_ string:String){
        if let data = string.data(using: .utf8){
            self.data.append(data)
        }
    }
    @inlinable
    mutating func readString(length:Int)->String?{
        guard self.readableBytes >= length else {
            return nil
        }
        let idx = readIndex
        readIndex += length
        return String(data: data.subdata(in: idx..<readIndex), encoding: .utf8)
    }
    
    /// integer read and write
    @inlinable
    mutating func writeInteger<T: FixedWidthInteger>(_ integer: T,as: T.Type = T.self) {
        var int = integer
        var bytes:[UInt8] = []
        let size = MemoryLayout<T>.size
        for _ in 0..<size{
            let b = UInt8(truncatingIfNeeded: int & 0xFF)
            int = int >> 8
            bytes.append(b)
        }
        self.data.append(contentsOf: bytes.reversed())
    }
    @inlinable
    mutating func readInteger<T: FixedWidthInteger>(as: T.Type = T.self) -> T? {
        let length = MemoryLayout<T>.size
        guard self.readableBytes >= length else {
            return nil
        }
        readIndex += length
        var result:T = 0
        for i in 0..<length{
            result = result | (T(data[readIndex - i - 1]) << T(i*8))
        }
        return result
    }
    
    @inlinable
    var readableBytes:Int{
        return data.count-readIndex
    }
}
