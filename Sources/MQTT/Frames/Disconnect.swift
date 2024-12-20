//
//  Disconnect.swift
//  CocoaMQTT
//
//  Created by JianBo on 2019/8/7.
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// MQTT Disconnect packet
struct Disconnect: Frame {

    var packetFixedHeaderType: UInt8 = FrameType.disconn.rawValue

    //3.14.2 DISCONNECT Variable Header
    public var sendReasonCode: MQTT.CloseCode?
    public var receiveReasonCode: MQTT.CloseCode?

    //3.14.2.2.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?
    
    //3.14.2.2.3 Reason String
    public var reasonString: String?
    //3.14.2.2.4 User Property
    public var userProperties: [String: String]?
    //3.14.2.2.5 Server Reference
    public var serverReference: String?

    ///MQTT 3.1.1
    init() { /* Nothing to do */ }

    ///MQTT 5.0
    init(disconnectReasonCode: MQTT.CloseCode) {
        self.sendReasonCode = disconnectReasonCode
    }
}

extension Disconnect {
    
    func fixedHeader() -> [UInt8] {
        var header = [UInt8]()
        header += [FrameType.disconn.rawValue]

        return header
    }
    
    func variableHeader5() -> [UInt8] {
        
        var header = [UInt8]()
        header += [sendReasonCode!.rawValue]

        //MQTT 5.0
        header += beVariableByteInteger(length: self.properties().count)
   

        return header
    }
    
    func payload5() -> [UInt8] { return [] }

    func properties() -> [UInt8] {
        
        var properties = [UInt8]()

        //3.14.2.2.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: Property.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }
        //3.14.2.2.3 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: Property.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        //3.14.2.2.4 User Property
        if let userProperty = self.userProperties {
            properties += userProperty.userPropertyBytes
        }
        //3.14.2.2.5 Server Reference
        if let serverReference = self.serverReference {
            properties += getMQTTPropertyData(type: Property.serverReference.rawValue, value: serverReference.bytesWithLength)
        }

        return properties
    }

    func allData() -> [UInt8] {
        
        var allData = [UInt8]()

        allData += fixedHeader()
        allData += variableHeader5()
        allData += properties()
        allData += payload5()

        return allData
    }

    func variableHeader() -> [UInt8] { return [] }

    func payload() -> [UInt8] { return [] }
}

extension Disconnect: InitialWithBytes {
    
    init?(packetFixedHeaderType: UInt8, bytes: [UInt8]) {

        var protocolVersion = "";
        if let storage = Storage() {
            protocolVersion = storage.queryMQTTVersion()
        }

        if (protocolVersion == "5.0"){
            if bytes.count > 0 {
                receiveReasonCode = MQTT.CloseCode(rawValue: bytes[0])
            }
        }
    }
    
}

extension Disconnect: CustomStringConvertible {
    var description: String {
        return "DISCONNECT"
    }
}
