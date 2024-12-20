//
//  Reader.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation
import Network

protocol ReaderDelegate:AnyObject{
    func readCompleted(_ reader:Reader)
    
    func reader(_ reader:Reader, didReceive error: Reader.Error)
    
    func reader(_ reader:Reader, didReceive connack: Connack)
    
    func reader(_ reader:Reader, didReceive disconnect: Disconnect)
    
    func reader(_ reader:Reader, didReceive auth: Auth)
    
    func reader(_ reader: Reader, didReceive publish: Publish)

    func reader(_ reader: Reader, didReceive puback: Puback)

    func reader(_ reader: Reader, didReceive pubrec: Pubrec)

    func reader(_ reader: Reader, didReceive pubrel: Pubrel)

    func reader(_ reader: Reader, didReceive pubcomp: Pubcomp)

    func reader(_ reader: Reader, didReceive suback: Suback)

    func reader(_ reader: Reader, didReceive unsuback: Unsuback)

    func reader(_ reader: Reader, didReceive pingresp: Pong)
    
//
//    func didReceive(_ reader: Reader, connack: FrameConnAck)
//
//    func didReceive(_ reader: Reader, publish: FramePublish)
//
//    func didReceive(_ reader: Reader, puback: FramePubAck)
//
//    func didReceive(_ reader: Reader, pubrec: FramePubRec)
//
//    func didReceive(_ reader: Reader, pubrel: FramePubRel)
//
//    func didReceive(_ reader: Reader, pubcomp: FramePubComp)
//
//    func didReceive(_ reader: Reader, suback: FrameSubAck)
//
//    func didReceive(_ reader: Reader, unsuback: FrameUnsubAck)
//
//    func didReceive(_ reader: Reader, pingresp: FramePingResp)
}

class Reader{
    private weak var delegate:ReaderDelegate?
    private let conn:NWConnection
    private var header:UInt8 = 0
    private var length:Int = 0
    private var data:[UInt8] = []
    private var multiply = 1
    init(_ delegate: ReaderDelegate, conn: NWConnection) {
        self.delegate = delegate
        self.conn = conn
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
                    self.delegate?.reader(self, didReceive: .lengthOverflow)
                    return
                }
                self.multiply = result.partialValue
                return self.readLength()
            }
            if self.length > 0{
                return self.readPayload()
            }
            self.next()
        }
    }
    func readPayload(){
        self.readData(length) { result in
            self.data = .init(repeating: 0, count: self.length)
            result.copyBytes(to: &self.data, count: self.length)
            self.next()
        }
    }
//    func read(_ data:Data)throws{
//        var idx = 0
//        guard data.count > idx else{
//            throw Error.invalidHeader
//        }
//        self.header = data[idx]
//        idx += 1
//        var length:Int = 0
//        var multiply:Int = 1
//        func readLength()throws{
//            guard data.count > idx else{
//                throw Error.invalidLength
//            }
//            let byte = data[idx]
//            idx += 1
//            length += Int(byte & 0x7f) * multiply
//            if byte & 0x80 != 0{
//                let result = multiply.multipliedReportingOverflow(by: 0x80)
//                if !result.overflow {
//                    multiply = result.partialValue
//                }else{
//                    throw Error.lengthOverflow
//                }
//                try readLength()
//            }
//        }
//        try readLength()
//        self.length = length
//        guard length == data.count - idx else{
//            throw Error.lengthNotMatch(length, data.count - idx)
//        }
//        var bytes:[UInt8] = .init(repeating: 0, count: length)
//        data.dropFirst(idx).copyBytes(to: &bytes, count: length)
//        self.data = bytes
//        try self.emit()
//    }
    private func readData(_ length:Int,finish:((Data)->Void)?){
        conn.receive(minimumIncompleteLength: length, maximumLength: length, completion: {[weak self] content, contentContext, isComplete, error in
            guard let self else{
                return
            }
            if isComplete{
                self.delegate?.readCompleted(self)
                return
            }
            if let error{
                self.delegate?.reader(self, didReceive: .networkError(error))
                return
            }
            guard let data = content,data.count == length else{
                self.delegate?.reader(self, didReceive: .readLengthError(length, content?.count ?? 0))
                return
            }
            finish?(data)
        })
    }
    private func next(){
        if let error = self.notify(){
            MQTT.Logger.error(error)
            self.delegate?.reader(self, didReceive: error)
        }
        self.readHeader()
    }
    private func notify()->Error? {
        guard let frameType = FrameType(rawValue: header & 0xF0) else {
            return Error.unkownFrame(header, data)
        }
        switch frameType {
        case .disconn:
            guard let frame = Disconnect(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: frame)
        case .auth:
            guard let frame = Auth(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: frame)
        case .connack:
            guard let connack = Connack(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: connack)
        case .pub:
            guard let publish = Publish(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: publish)
        case .puback:
            guard let puback = Puback(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: puback)
        case .pubrec:
            guard let pubrec = Pubrec(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: pubrec)
        case .pubrel:
            guard let pubrel = Pubrel(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: pubrel)
        case .pubcomp:
            guard let pubcomp = Pubcomp(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: pubcomp)
        case .suback:
            guard let frame = Suback(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: frame)
        case .unsuback:
            guard let frame = Unsuback(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: frame)
        case .pong:
            guard let frame = Pong(packetFixedHeaderType: header, bytes: data) else {
                return Error.invalidFrame(frameType, data)
            }
            delegate?.reader(self, didReceive: frame)
        
        default:
            break
        }
        return nil
    }
    private func reset(){
        header = 0
        length = 0
        data = []
        multiply = 1
    }
}
extension Reader{
    enum Error:Swift.Error,CustomStringConvertible{
        case serverClosed
        case lengthOverflow
        case unkownFrame(UInt8,[UInt8])
        case invalidFrame(FrameType,[UInt8])
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
            case .invalidFrame(let type,let data):
                return "Reader: frame \(type) error, data:\(data)"
            case .networkError(let error):
                return "Reader: network error:\(error)"
            }
        }
    }
}
