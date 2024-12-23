//
//  Reader.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/17.
//

import Foundation
import Network

protocol ReaderDelegate:AnyObject{
    func readCompleted(_ reader:Reader)
    func reader(_ reader:Reader, didReceive error: Error)
    func reader(_ reader:Reader, didReceive packet: Packet)
}
class Reader:@unchecked Sendable{
    private let conn:NWConnection
    private var header:UInt8 = 0
    private var length:Int = 0
    private var multiply = 1
    private let version:MQTT.Version
    private weak var delegate:ReaderDelegate?
    init(_ delegate: ReaderDelegate, conn: NWConnection,version:MQTT.Version) {
        self.conn = conn
        self.delegate = delegate
        self.version = version
    }
    func start(){
        self.readHeader()
    }
    func readHeader(){
        self.reset()
        self.readData(1) { result in
            self.header = result[0]
            self.readLength()
        }
    }
    func readLength(){
        self.readData(1) { result in
            let byte = result[0]
            self.length += Int(byte & 0x7f) * self.multiply
            if byte & 0x80 != 0{
                let result = self.multiply.multipliedReportingOverflow(by: 0x80)
                if result.overflow {
                    self.delegate?.reader(self, didReceive: Error.lengthOverflow)
                    return
                }
                self.multiply = result.partialValue
                return self.readLength()
            }
            if self.length > 0{
                return self.readPayload()
            }
            self.parse(data: Data())
        }
    }
    func readPayload(){
        self.readData(length) { result in
            self.parse(data: result)
        }
    }
    private func readData(_ length:Int,finish:(@Sendable (Data)->Void)?){
        conn.receive(minimumIncompleteLength: length, maximumLength: length, completion: {[weak self] content, contentContext, isComplete, error in
            guard let self else{
                return
            }
            if isComplete{
                self.delegate?.readCompleted(self)
                return
            }
            if let error{
                self.delegate?.reader(self, didReceive: Error.networkError(error))
                return
            }
            guard let data = content,data.count == length else{
                self.delegate?.reader(self, didReceive: Error.readLengthError(length, content?.count ?? 0))
                return
            }
            finish?(data)
        })
    }
    private func parse(data:Data){
        guard let type = PacketType(rawValue: self.header & 0xF0) else {
            self.delegate?.reader(self, didReceive: Error.unkownFrame(header, data))
            return
        }
        let incoming:IncomingPacket = .init(type: type, flags: self.header & 0xF, remainingData: .init(data: data))
        do {
            let message: Packet
            switch incoming.type {
            case .PUBLISH:
                message = try PublishPacket.read(version: self.version, from: incoming)
            case .CONNACK:
                message = try ConnackPacket.read(version: self.version, from: incoming)
            case .PUBACK, .PUBREC, .PUBREL, .PUBCOMP:
                message = try PubAckPacket.read(version: self.version, from: incoming)
            case .SUBACK, .UNSUBACK:
                message = try SubackPacket.read(version: self.version, from: incoming)
            case .PINGRESP:
                message = try PingrespPacket.read(version: self.version, from: incoming)
            case .DISCONNECT:
                message = try DisconnectPacket.read(version: self.version, from: incoming)
            case .AUTH:
                message = try AuthPacket.read(version: self.version, from: incoming)
            default:
                throw MQTTError.decodeError
            }
            self.delegate?.reader(self, didReceive: message)
        } catch {
            self.delegate?.reader(self, didReceive: error)
        }
        self.readHeader()
    }
    private func reset(){
        header = 0
        length = 0
        multiply = 1
    }
}
extension Reader{
    enum Error:Swift.Error,CustomStringConvertible{
        case serverClosed
        case lengthOverflow
        case unkownFrame(UInt8,Data)
        case networkError(NWError)
        case readLengthError(Int,Int)
        var description: String{
            switch self {
            case .serverClosed:
                return "Reader: the server has close the stream"
            case .lengthOverflow:
                return "Reader: length overflow"
            case .readLengthError(let expect, let got):
                return "Reader: read data length error expect:\(expect),but got:\(got)"
            case .unkownFrame(let header,let data):
                return "Reader: unknown frame type, header: \(header), data:\(data)"
            case .networkError(let error):
                return "Reader: network error:\(error)"
            }
        }
    }
}
