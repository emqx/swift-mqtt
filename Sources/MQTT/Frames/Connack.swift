//
//  FrameConnack.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

struct Connack: Frame {
    var packetFixedHeaderType: UInt8 = FrameType.connack.rawValue
    // --- Attributes
    ///MQTT 3.1.1
    var returnCode: Code?
    ///MQTT 5.0
    var reasonCode: ConnAckReasonCode?
    //3.2.2.1.1 Session Present
    var sessPresent: Bool = false
    // --- Attributes End
    //3.2.2.3 CONNACK Properties
    var connackProperties: DecodeConnAck?
    var propertiesBytes: [UInt8]?
    //3.2.3 CONNACK Payload
    //The CONNACK packet has no Payload.
    ///MQTT 3.1.1
    init(returnCode: Code) {
        self.returnCode = returnCode
    }
    ///MQTT 5.0
    init(code: ConnAckReasonCode) {
        reasonCode = code
    }
}

extension Connack {
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.connack.rawValue]
        return header
    }
    func variableHeader5() -> [UInt8] {
        return [sessPresent.bit, reasonCode!.rawValue]
    }
    func payload5() -> [UInt8] { return [] }
    func properties() -> [UInt8] { return propertiesBytes ?? [] }
    func allData() -> [UInt8] {
        var allData = [UInt8]()
        allData += fixedHeader()
        allData += variableHeader5()
        allData += properties()
        allData += payload5()
        return allData
    }
    func variableHeader() -> [UInt8] {
        return [sessPresent.bit, returnCode!.rawValue]
    }
    func payload() -> [UInt8] { return [] }
}

extension Connack: InitialWithBytes {
    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {
        guard packetFixedHeaderType == FrameType.connack.rawValue else {
            return nil
        }
        guard bytes.count >= 2 else {
            return nil
        }
        sessPresent = Bool(bit: bytes[0] & 0x01)
        let mqtt5ack = ConnAckReasonCode(rawValue: bytes[1])
        reasonCode = mqtt5ack
        let ack = Code(byte: bytes[1])
        returnCode = ack
        propertiesBytes = bytes
        self.connackProperties = DecodeConnAck()
        self.connackProperties!.properties(connackData: bytes)
    }
}

extension Connack: CustomStringConvertible {
    var description: String {
        return "CONNACK(code: \(String(describing: reasonCode)), sp: \(sessPresent))"
    }
}
extension Connack{
    enum Code: UInt8, CustomStringConvertible {
        case accept  = 0
        case unacceptableProtocolVersion
        case identifierRejected
        case serverUnavailable
        case badUsernameOrPassword
        case notAuthorized
        case reserved
        
        public init(byte: UInt8) {
            switch byte {
            case Code.accept.rawValue..<Code.reserved.rawValue:
                self.init(rawValue: byte)!
            default:
                self = .reserved
            }
        }
        
        public var description: String {
            switch self {
            case .accept:                       return "accept"
            case .unacceptableProtocolVersion:  return "unacceptableProtocolVersion"
            case .identifierRejected:           return "identifierRejected"
            case .serverUnavailable:            return "serverUnavailable"
            case .badUsernameOrPassword:        return "badUsernameOrPassword"
            case .notAuthorized:                return "notAuthorized"
            case .reserved:                     return "reserved"
            }
        }
    }
}
