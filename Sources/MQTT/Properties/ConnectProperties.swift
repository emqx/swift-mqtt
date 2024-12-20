//
//  MqttConnectProperties.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/7/25.
//

import Foundation

public struct ConnectProperties {
    //3.1.2.11.1 Property Length
    //public var propertyLength: UInt8?
    //3.1.2.11.2 Session Expiry Interval
    public var sessionExpiryInterval: UInt32?
    //3.1.2.11.3 Receive Maximum
    public var receiveMaximum: UInt16?
    //3.1.2.11.4 Maximum Packet Size
    public var maximumPacketSize: UInt32?
    //3.1.2.11.5 Topic Alias Maximum
    public var topicAliasMaximum: UInt16?
    //3.1.2.11.6 Request Response Information
    public var requestResponseInformation: UInt8?
    //3.1.2.11.7 Request Problem Information
    public var requestProblemInfomation: UInt8?
    //3.1.2.11.8 User Property
    public var userProperties: [String: String]?
    //3.1.2.11.9 Authentication Method
    public var authenticationMethod: String?
    //3.1.2.11.10 Authentication Data
    public var authenticationData: [UInt8]?
    public init(sessionExpiryInterval: UInt32? = nil, receiveMaximum: UInt16? = nil, maximumPacketSize: UInt32? = nil, topicAliasMaximum: UInt16? = nil, requestResponseInformation: UInt8? = nil, requestProblemInfomation: UInt8? = nil, userProperties: [String : String]? = nil, authenticationMethod: String? = nil, authenticationData: [UInt8]? = nil) {
        self.sessionExpiryInterval = sessionExpiryInterval
        self.receiveMaximum = receiveMaximum
        self.maximumPacketSize = maximumPacketSize
        self.topicAliasMaximum = topicAliasMaximum
        self.requestResponseInformation = requestResponseInformation
        self.requestProblemInfomation = requestProblemInfomation
        self.userProperties = userProperties
        self.authenticationMethod = authenticationMethod
        self.authenticationData = authenticationData
    }
    public var properties: [UInt8] {
        var properties = [UInt8]()
        //3.1.2.11.2 Session Expiry Interval
        if let sessionExpiryInterval = self.sessionExpiryInterval {
            properties += getMQTTPropertyData(type: Property.sessionExpiryInterval.rawValue, value: sessionExpiryInterval.byteArrayLittleEndian)
        }
        // 3.1.2.11.3 Receive Maximum
        if let receiveMaximum = self.receiveMaximum {
            properties += getMQTTPropertyData(type: Property.receiveMaximum.rawValue, value: receiveMaximum.hlBytes)
        }

        // 3.1.2.11.4 Maximum Packet Size
        if let maximumPacketSize = self.maximumPacketSize {
            properties += getMQTTPropertyData(type: Property.maximumPacketSize.rawValue, value: maximumPacketSize.byteArrayLittleEndian)
        }

        // 3.1.2.11.5 Topic Alias Maximum
        if let topicAliasMaximum = self.topicAliasMaximum {
            properties += getMQTTPropertyData(type: Property.topicAliasMaximum.rawValue, value: topicAliasMaximum.hlBytes)
        }

        // 3.1.2.11.6 Request Response Information
        if let requestResponseInformation = self.requestResponseInformation {
            properties += getMQTTPropertyData(type: Property.requestResponseInformation.rawValue, value: [requestResponseInformation])
        }
        // 3.1.2.11.7 Request Problem Information
        if let requestProblemInfomation = self.requestProblemInfomation {
            properties += getMQTTPropertyData(type: Property.requestProblemInformation.rawValue, value: [requestProblemInfomation])
        }
        // 3.1.2.11.8 User Property
        if let userProperty = self.userProperties {
            properties += userProperty.userPropertyBytes
        }
        // 3.1.2.11.9 Authentication Method
        if let authenticationMethod = self.authenticationMethod {
            properties += getMQTTPropertyData(type: Property.authenticationMethod.rawValue, value: authenticationMethod.bytesWithLength)
        }
        // 3.1.2.11.10 Authentication Data
        if let authenticationData = self.authenticationData {
            properties += authenticationData
        }
        return properties
    }
}
