//
//  FrameProtocl.swift
//  CocoaMQTT
//
//  Created by Feng Lee<feng@eqmtt.io> on 14/8/3.
//  Copyright (c) 2015 emqx.io. All rights reserved.
//

import Foundation

enum FrameType: UInt8 {
    case reserved = 0x00
    case conn = 0x10
    case connack = 0x20
    case pub = 0x30
    case puback = 0x40
    case pubrec = 0x50
    case pubrel = 0x60
    case pubcomp = 0x70
    case sub = 0x80
    case suback = 0x90
    case unsub = 0xA0
    case unsuback = 0xB0
    case ping = 0xC0
    case pong = 0xD0
    case disconn = 0xE0
    case auth = 0xF0
}

/// The frame can be initialized with a bytes
protocol InitialWithBytes {

    init?(packetFixedHeaderType: UInt8, bytes: [UInt8])
}


/// MQTT Frame protocol
protocol Frame {
    /// Each MQTT Control Packet contains a fixed header
    /// MQTT 3.1.1
    var packetFixedHeaderType: UInt8 {get set}
    /// MQTT 5.0
    func fixedHeader() -> [UInt8]
    /// Some types of MQTT Control Packets contain a variable header component
    /// MQTT 3.1.1
    func variableHeader() -> [UInt8]
    /// MQTT 5.0
    func variableHeader5() -> [UInt8]
    /// MQTT 5.0 The last field in the Variable Header of the CONNECT, CONNACK, PUBLISH, PUBACK, PUBREC, PUBREL, PUBCOMP, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK, DISCONNECT, and AUTH packet is a set of Properties. In the CONNECT packet there is also an optional set of Properties in the Will Properties field with the Payload.
    func properties() -> [UInt8]
    /// Some MQTT Control Packets contain a payload as the final part of the packet
    /// MQTT 3.1.1
    func payload() -> [UInt8]
    /// MQTT 5.0
    func payload5() -> [UInt8]
    /// fixedHeader + variableHeader + properties + payload
    func allData() -> [UInt8]
}

extension Frame {

    /// Pack struct to binary
    func bytes(version: String) -> [UInt8] {

        if version == "5.0" {
            let fixedHeader = self.fixedHeader()
            let variableHeader5 = self.variableHeader5()
            let payload5 = self.payload5()
            let properties = self.properties()
            let len5 = UInt32(variableHeader5.count + properties.count + payload5.count)

//            Logger.debug("==========================MQTT 5.0==========================")
//            Logger.debug("packetFixedHeaderType \(packetFixedHeaderType)")
//            Logger.debug("fixedHeader \(fixedHeader)")
//            Logger.debug("remainingLen(len: len) \(remainingLen(len: len5))")
//            Logger.debug("variableHeader \(variableHeader5)")
//            Logger.debug("properties \(properties)")
//            Logger.debug("payload \(payload5)")
//            Logger.debug("=============================================================")

            return [packetFixedHeaderType] + remainingLen(len: len5) + variableHeader5 + properties + payload5
        }else {

            let variableHeader = self.variableHeader()
            let payload = self.payload()

            let len = UInt32(variableHeader.count + payload.count)

            MQTT.Logger.debug("=========================MQTT 3.1.1=========================")
            MQTT.Logger.debug("packetFixedHeaderType \(packetFixedHeaderType)")
            MQTT.Logger.debug("remainingLen(len: len) \(remainingLen(len: len))")
            MQTT.Logger.debug("variableHeader \(variableHeader)")
            MQTT.Logger.debug("payload \(payload)")
            MQTT.Logger.debug("=============================================================")
            
            return [packetFixedHeaderType] + remainingLen(len: len) + variableHeader + payload
        }

    }
    
    private func remainingLen(len: UInt32) -> [UInt8] {
        var bytes: [UInt8] = []
        var digit: UInt8 = 0
        
        var len = len
        repeat {
            digit = UInt8(len % 128)
            len = len / 128
            // if there are more digits to encode, set the top bit of this digit
            if len > 0 {
                digit = digit | 0x80
            }
            bytes.append(digit)
        } while len > 0
        
        return bytes
    }
}

/// Fixed Header Attributes
extension Frame {

    /// The Fixed Header consist of the following attritutes
    ///
    /// +---------+----------+-------+--------+
    /// | 7 6 5 4 |     3    |  2 1  | 0      |
    /// +---------+----------+-------+--------+
    /// |  Type   | DUP flag |  QoS  | RETAIN |
    /// +-------------------------------------+
    
    
    /// The type of the Frame
    var type: FrameType {
        return  FrameType(rawValue: packetFixedHeaderType & 0xF0)!
    }
    
    /// Dup flag
    var dup: Bool {
        get {
            return ((packetFixedHeaderType & 0x08) >> 3) == 0 ? false : true
        }
        set {
            packetFixedHeaderType = (packetFixedHeaderType & 0xF7) | (newValue.bit  << 3)
        }
    }
    
    /// Qos level
    var qos: MQTTQos {
        get {
            return MQTTQos(rawValue: (packetFixedHeaderType & 0x06) >> 1)!
        }
        set {
            packetFixedHeaderType = (packetFixedHeaderType & 0xF9) | (newValue.rawValue << 1)
        }
    }
    
    /// Retained flag
    var retained: Bool {
        get {
            return (packetFixedHeaderType & 0x01) == 0 ? false : true
        }
        set {
            packetFixedHeaderType = (packetFixedHeaderType & 0xFE) | newValue.bit
        }
    }
}


