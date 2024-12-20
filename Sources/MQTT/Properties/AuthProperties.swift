//
//  MqttAuthProperties.swift
//  CocoaMQTT
//
//  Created by liwei wang on 1/9/2021.
//

import Foundation

public struct AuthProperties {
    //3.15.2.2.2 Authentication Method
    public var authenticationMethod: String?
    //3.15.2.2.3 Authentication Data
    public var authenticationData: [UInt8]?
    //3.15.2.2.4 Reason String
    public var reasonString: String?
    //3.15.2.2.5 User Property
    public var userProperties: [String: String]?
    public init(authenticationMethod: String? = nil, authenticationData: [UInt8]? = nil, reasonString: String? = nil, userProperties: [String : String]? = nil) {
        self.authenticationMethod = authenticationMethod
        self.authenticationData = authenticationData
        self.reasonString = reasonString
        self.userProperties = userProperties
    }
    public var properties: [UInt8] {
        var properties = [UInt8]()
        //3.15.2.2.2 Authentication Method
        if let authenticationMethod = self.authenticationMethod {
            properties += getMQTTPropertyData(type: Property.authenticationMethod.rawValue, value: authenticationMethod.bytesWithLength)
        }
        //3.15.2.2.3 Authentication Data
        if let authenticationData = self.authenticationData {
            properties += getMQTTPropertyData(type: Property.authenticationData.rawValue, value: authenticationData)
        }
        //3.15.2.2.4 Reason String
        if let reasonString = self.reasonString {
            properties += getMQTTPropertyData(type: Property.reasonString.rawValue, value: reasonString.bytesWithLength)
        }
        //3.15.2.2.5 User Property
        if let userProperty = self.userProperties {
            properties += userProperty.userPropertyBytes
        }
        return properties
    }
}
