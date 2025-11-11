//
//  DataBuffer.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/16.
//

import Foundation

@usableFromInline
struct DataBuffer:Sendable,Equatable{
    @usableFromInline private(set) var data:Data
    @usableFromInline var nextIndex:Int = 0
    
    @inlinable
    init(data: Data = Data()) {
        self.data = data
    }
    
    /// integer read and write
    @inlinable
    mutating func writeByte(_ byte:UInt8) {
        self.data.append(byte)
    }
    @inlinable
    mutating func readByte() -> UInt8? {
        guard self.readableBytes >= 1 else {
            return nil
        }
        let idx = nextIndex
        nextIndex += 1
        return self.data[idx]
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
        let idx = nextIndex
        nextIndex += len
        return self.data.subdata(in: idx..<nextIndex)
    }
    
    /// buffer read and write
    @inlinable
    mutating func writeBuffer(_ buffer: inout DataBuffer){
        if let data = buffer.readData(){
            self.data.append(data)
        }
    }
    @inlinable
    mutating func readBuffer(length:Int)->DataBuffer?{
        guard let data = self.readData(length: length) else{
            return nil
        }
        return DataBuffer(data: data)
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
        guard let data = self.readData(length: length) else{
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// integer read and write
    @inlinable
    mutating func writeInteger<T: FixedWidthInteger>(_ integer: T,as: T.Type = T.self) {
        var int = integer.bigEndian
        let data = Data(bytes: &int, count: MemoryLayout<T>.size)
        self.data.append(data)
    }
    @inlinable
    mutating func readInteger<T: FixedWidthInteger>(as: T.Type = T.self) -> T? {
        let length = MemoryLayout<T>.size
        guard self.readableBytes >= length else {
            return nil
        }
        nextIndex += length
        var result:T = 0
        for i in 0..<length{
            result = result | (T(data[nextIndex - i - 1]) << T(i*8))
        }
        return result
    }
    /// 
    @inlinable
    var readableBytes:Int{
        return data.count-nextIndex
    }
}
