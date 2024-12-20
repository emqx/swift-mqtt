//
//  ByteBuffer.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/16.
//

import Foundation

public struct DataBuffer:Sendable,Equatable{
    private var data:Data = Data()
    private var readIndex:Int = 0
    public static let empty:DataBuffer = .init()
    public init(data: Data = Data()) {
        self.data = data
    }
    public mutating func writeBuffer(_ buffer: inout DataBuffer){
        buffer.readIndex = buffer.data.count
        self.data.append(buffer.data)
    }
    public mutating func writeString(_ string:String){
        if let data = string.data(using: .utf8){
            self.data.append(data)
        }
    }
    public mutating func writeInteger<T: FixedWidthInteger>(_ integer: T,as: T.Type = T.self) {
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
    /// read all data when length is nil
    public mutating func readData(length:Int? = nil)->Data?{
        var len = length ?? self.readableBytes
        guard self.readableBytes >= len else {
            return nil
        }
        let idx = readIndex
        readIndex += len
        return self.data.subdata(in: idx..<readIndex)
    }
    public mutating func readInteger<T: FixedWidthInteger>(as: T.Type = T.self) -> T? {
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
    public mutating func readSlice(length:Int)->DataBuffer?{
        guard self.readableBytes >= length else {
            return nil
        }
        let idx = readIndex
        readIndex += length
        return DataBuffer(data: data.subdata(in: idx..<readIndex))
    }
    public mutating func readString(length:Int)->String?{
        guard self.readableBytes >= length else {
            return nil
        }
        let idx = readIndex
        readIndex += length
        return String(data: data.subdata(in: idx..<readIndex), encoding: .utf8)
    }
    public var readableBytes:Int{
        return data.count-readIndex
    }
}
