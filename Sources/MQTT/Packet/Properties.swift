//
//  Properties.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation

/// MQTT v5.0 properties. A property consists of a identifier and a value

public typealias Properties = [Property]

extension Properties{
    ///
    /// `PUBACK` `SUBACK` `PUBREL` `PUBREC` `PUBCOMP` `UNSUBACK` properties
    ///
    public func ack()->Property.ACK{ .init(self) }
    ///
    /// `AUTH` packet properties
    ///
    public func auth()->Property.Auth{ .init(self) }
    ///
    /// `CONNECT` packet properties
    ///
    public func connect()->Property.Connect{ .init(self) }
    ///
    /// `PUBACK` properties
    ///
    public func connack()->Property.Connack{ .init(self) }
    ///
    /// `PUBLISH` packet properties
    ///
    public func publish()->Property.Publish{ .init(self) }
    
    func write(to byteBuffer: inout DataBuffer) throws {
        Serializer.writeVarint(self.packetSize, to: &byteBuffer)

        for property in self {
            try property.write(to: &byteBuffer)
        }
    }
    static func read(from byteBuffer: inout DataBuffer) throws -> Self {
        var properties: [Property] = []
        guard byteBuffer.readableBytes > 0 else {
            return .init()
        }
        let packetSize = try Serializer.readVarint(from: &byteBuffer)
        guard var propertyBuffer = byteBuffer.readBuffer(length: packetSize) else { throw MQError.badResponse }
        while propertyBuffer.readableBytes > 0 {
            let property = try Property.read(from: &propertyBuffer)
            properties.append(property)
        }
        return .init(properties)
    }
    var packetSize: Int {
        return self.reduce(0) { $0 + 1 + $1.value.packetSize }
    }
}


/// MQTT v5.0 properties. A property consists of a identifier and a value

public enum Property: Equatable, Sendable {
    /// Payload format: 0 = bytes, 1 = UTF8 string (available for PUBLISH)
    case payloadFormat(UInt8)
    /// Message expiry indicates the lifetime of the message (available for PUBLISH)
    case messageExpiry(UInt32)
    /// String describing the content of the message eg "application/json" (available for PUBLISH)
    case contentType(String)
    /// Response topic used in request/response interactions (available for PUBLISH)
    case responseTopic(String)
    /// Correlation data used to id a request/response in request/response interactions (available for PUBLISH)
    case correlationData(Data)
    /// Subscription identifier set in SUBSCRIBE packet and included in related PUBLISH packet
    /// (available for PUBLISH, SUBSCRIBE)
    case subscriptionIdentifier(Int)
    /// Interval before session expires (available for CONNECT, CONNACK, DISCONNECT)
    case sessionExpiryInterval(UInt32)
    /// Client identifier assigned to client if they didn't provide one (available for CONNACK)
    case assignedClientIdentifier(String)
    /// Indication to client on how long server will keep connection without activity (available for CONNACK)
    case serverKeepAlive(UInt16)
    /// String indicating the authentication method to use (available for CONNECT, CONNACK, AUTH)
    case authenticationMethod(String)
    /// Data used in authentication (available for CONNECT, CONNACK, AUTH)
    case authenticationData(Data)
    /// Request that server sends a reason string in its CONNACK or DISCONNECT packets (available for CONNECT)
    case requestProblemInformation(UInt8)
    /// Interval to wait before publishing connect will message (available for CONNECT will)
    case willDelayInterval(UInt32)
    /// Request response information from server (available for CONNECT)
    case requestResponseInformation(UInt8)
    /// Response information from server. Commonly used to pass a globally unique portion
    /// of the topic tree for this client (available for CONNACK)
    case responseInformation(String)
    /// Server uses serverReference in CONNACK to indicate to either use another server or that the server has moved
    /// (available for CONNACK)
    case serverReference(String)
    /// String representing the reason associated with this response (available for CONNACK,
    /// PUBACK, PUBREC, PUBREL, PUBCOMP, SUBACK, UNSUBACK, DISCONNECT, AUTH)
    case reasonString(String)
    /// Maximum number of PUBLISH, PUBREL messages that can be sent without receiving a response (available for CONNECT, CONNACK)
    case receiveMaximum(UInt16)
    /// Maximum number for topic alias (available for CONNECT, CONNACK)
    case topicAliasMaximum(UInt16)
    /// Topic alias. Use instead of full topic name to reduce packet size (available for PUBLISH)
    case topicAlias(UInt16)
    /// Maximum QoS supported by server (available for CONNACK)
    case maximumQoS(MQTTQoS)
    /// Does server support retained publish packets (available for CONNACK)
    case retainAvailable(UInt8)
    /// User property, key and value (available for all packets)
    case userProperty(String, String)
    /// Maximum packet size supported (available for CONNECT, CONNACK)
    case maximumPacketSize(UInt32)
    /// Does server support wildcard subscription (available for CONNACK)
    case wildcardSubscriptionAvailable(UInt8)
    /// Does server support subscription identifiers (available for CONNACK)
    case subscriptionIdentifierAvailable(UInt8)
    /// Does server support shared subscriptions (available for CONNACK)
    case sharedSubscriptionAvailable(UInt8)
}

extension Property {
    enum ID: UInt8 {
        case payloadFormat = 1
        case messageExpiry = 2
        case contentType = 3
        case responseTopic = 8
        case correlationData = 9
        case subscriptionIdentifier = 11
        case sessionExpiryInterval = 17
        case assignedClientIdentifier = 18
        case serverKeepAlive = 19
        case authenticationMethod = 21
        case authenticationData = 22
        case requestProblemInformation = 23
        case willDelayInterval = 24
        case requestResponseInformation = 25
        case responseInformation = 26
        case serverReference = 28
        case reasonString = 31
        case receiveMaximum = 33
        case topicAliasMaximum = 34
        case topicAlias = 35
        case maximumQoS = 36
        case retainAvailable = 37
        case userProperty = 38
        case maximumPacketSize = 39
        case wildcardSubscriptionAvailable = 40
        case subscriptionIdentifierAvailable = 41
        case sharedSubscriptionAvailable = 42
    }
    enum Value: Equatable {
        case byte(UInt8)
        case twoByteInteger(UInt16)
        case fourByteInteger(UInt32)
        case varint(Int)
        case string(String)
        case stringPair(String, String)
        case binaryData(Data)

        var packetSize: Int {
            switch self {
            case .byte:
                return 1
            case .twoByteInteger:
                return 2
            case .fourByteInteger:
                return 4
            case .varint(let value):
                return Serializer.varintPacketSize(value)
            case .string(let string):
                return 2 + string.utf8.count
            case .stringPair(let string1, let string2):
                return 2 + string1.utf8.count + 2 + string2.utf8.count
            case .binaryData(let data):
                return 2 + data.count
            }
        }

        func write(to byteBuffer: inout DataBuffer) throws {
            switch self {
            case .byte(let value):
                byteBuffer.writeInteger(value)
            case .twoByteInteger(let value):
                byteBuffer.writeInteger(value)
            case .fourByteInteger(let value):
                byteBuffer.writeInteger(value)
            case .varint(let value):
                Serializer.writeVarint(value, to: &byteBuffer)
            case .string(let string):
                try Serializer.writeString(string, to: &byteBuffer)
            case .stringPair(let string1, let string2):
                try Serializer.writeString(string1, to: &byteBuffer)
                try Serializer.writeString(string2, to: &byteBuffer)
            case .binaryData(let data):
                try Serializer.writeData(data, to: &byteBuffer)
            }
        }
    }
}

extension Property {
    var value: Value {
        switch self {
        case .payloadFormat(let value): return .byte(value)
        case .messageExpiry(let value): return .fourByteInteger(value)
        case .contentType(let value): return .string(value)
        case .responseTopic(let value): return .string(value)
        case .correlationData(let value): return .binaryData(value)
        case .subscriptionIdentifier(let value): return .varint(value)
        case .sessionExpiryInterval(let value): return .fourByteInteger(value)
        case .assignedClientIdentifier(let value): return .string(value)
        case .serverKeepAlive(let value): return .twoByteInteger(value)
        case .authenticationMethod(let value): return .string(value)
        case .authenticationData(let value): return .binaryData(value)
        case .requestProblemInformation(let value): return .byte(value)
        case .willDelayInterval(let value): return .fourByteInteger(value)
        case .requestResponseInformation(let value): return .byte(value)
        case .responseInformation(let value): return .string(value)
        case .serverReference(let value): return .string(value)
        case .reasonString(let value): return .string(value)
        case .receiveMaximum(let value): return .twoByteInteger(value)
        case .topicAliasMaximum(let value): return .twoByteInteger(value)
        case .topicAlias(let value): return .twoByteInteger(value)
        case .maximumQoS(let value): return .byte(value.rawValue)
        case .retainAvailable(let value): return .byte(value)
        case .userProperty(let value1, let value2): return .stringPair(value1, value2)
        case .maximumPacketSize(let value): return .fourByteInteger(value)
        case .wildcardSubscriptionAvailable(let value): return .byte(value)
        case .subscriptionIdentifierAvailable(let value): return .byte(value)
        case .sharedSubscriptionAvailable(let value): return .byte(value)
        }
    }
    var id: ID {
        switch self {
        case .payloadFormat: return .payloadFormat
        case .messageExpiry: return .messageExpiry
        case .contentType: return .contentType
        case .responseTopic: return .responseTopic
        case .correlationData: return .correlationData
        case .subscriptionIdentifier: return .subscriptionIdentifier
        case .sessionExpiryInterval: return .sessionExpiryInterval
        case .assignedClientIdentifier: return .assignedClientIdentifier
        case .serverKeepAlive: return .serverKeepAlive
        case .authenticationMethod: return .authenticationMethod
        case .authenticationData: return .authenticationData
        case .requestProblemInformation: return .requestProblemInformation
        case .willDelayInterval: return .willDelayInterval
        case .requestResponseInformation: return .requestResponseInformation
        case .responseInformation: return .responseInformation
        case .serverReference: return .serverReference
        case .reasonString: return .reasonString
        case .receiveMaximum: return .receiveMaximum
        case .topicAliasMaximum: return .topicAliasMaximum
        case .topicAlias: return .topicAlias
        case .maximumQoS: return .maximumQoS
        case .retainAvailable: return .retainAvailable
        case .userProperty: return .userProperty
        case .maximumPacketSize: return .maximumPacketSize
        case .wildcardSubscriptionAvailable: return .wildcardSubscriptionAvailable
        case .subscriptionIdentifierAvailable: return .subscriptionIdentifierAvailable
        case .sharedSubscriptionAvailable: return .sharedSubscriptionAvailable
        }
    }

    func write(to byteBuffer: inout DataBuffer) throws {
        byteBuffer.writeInteger(self.id.rawValue)
        try self.value.write(to: &byteBuffer)
    }

    static func read(from byteBuffer: inout DataBuffer) throws -> Self {
        guard let idValue: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
        guard let id = Property.ID(rawValue: idValue) else { throw MQError.badResponse }
        switch id {
        case .payloadFormat:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .payloadFormat(value)
        case .messageExpiry:
            guard let value: UInt32 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .messageExpiry(value)
        case .contentType:
            let string = try Serializer.readString(from: &byteBuffer)
            return .contentType(string)
        case .responseTopic:
            let string = try Serializer.readString(from: &byteBuffer)
            return .responseTopic(string)
        case .correlationData:
            let data = try Serializer.readData(from: &byteBuffer)
            return .correlationData(data)
        case .subscriptionIdentifier:
            let value = try Serializer.readVarint(from: &byteBuffer)
            return .subscriptionIdentifier(value)
        case .sessionExpiryInterval:
            guard let value: UInt32 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .sessionExpiryInterval(value)
        case .assignedClientIdentifier:
            let string = try Serializer.readString(from: &byteBuffer)
            return .assignedClientIdentifier(string)
        case .serverKeepAlive:
            guard let value: UInt16 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .serverKeepAlive(value)
        case .authenticationMethod:
            let string = try Serializer.readString(from: &byteBuffer)
            return .authenticationMethod(string)
        case .authenticationData:
            let data = try Serializer.readData(from: &byteBuffer)
            return .authenticationData(data)
        case .requestProblemInformation:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .requestProblemInformation(value)
        case .willDelayInterval:
            guard let value: UInt32 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .willDelayInterval(value)
        case .requestResponseInformation:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .requestResponseInformation(value)
        case .responseInformation:
            let string = try Serializer.readString(from: &byteBuffer)
            return .responseInformation(string)
        case .serverReference:
            let string = try Serializer.readString(from: &byteBuffer)
            return .serverReference(string)
        case .reasonString:
            let string = try Serializer.readString(from: &byteBuffer)
            return .reasonString(string)
        case .receiveMaximum:
            guard let value: UInt16 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .receiveMaximum(value)
        case .topicAliasMaximum:
            guard let value: UInt16 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .topicAliasMaximum(value)
        case .topicAlias:
            guard let value: UInt16 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .topicAlias(value)
        case .maximumQoS:
            guard let value: UInt8 = byteBuffer.readInteger(),
                  let qos = MQTTQoS(rawValue: value) else { throw MQError.badResponse }
            return .maximumQoS(qos)
        case .retainAvailable:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .retainAvailable(value)
        case .userProperty:
            let string1 = try Serializer.readString(from: &byteBuffer)
            let string2 = try Serializer.readString(from: &byteBuffer)
            return .userProperty(string1, string2)
        case .maximumPacketSize:
            guard let value: UInt32 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .maximumPacketSize(value)
        case .wildcardSubscriptionAvailable:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .wildcardSubscriptionAvailable(value)
        case .subscriptionIdentifierAvailable:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .subscriptionIdentifierAvailable(value)
        case .sharedSubscriptionAvailable:
            guard let value: UInt8 = byteBuffer.readInteger() else { throw MQError.badResponse }
            return .sharedSubscriptionAvailable(value)
        }
    }

    var packetSize: Int {
        return self.value.packetSize
    }
}

extension Property{
    ///
    /// CONNACK properties
    ///
    public struct Connack{
        public var sessionExpiryInterval: UInt32?
        public var receiveMaximum: UInt16?
        public var maximumQoS: MQTTQoS?
        public var retainAvailable: Bool?
        public var maximumPacketSize: UInt32?
        public var assignedClientIdentifier: String?
        public var topicAliasMaximum: UInt16?
        public var reasonString: String?
        public var userProperty: [String: String]?
        public var wildcardSubscriptionAvailable: Bool?
        public var subscriptionIdentifiersAvailable: Bool?
        public var sharedSubscriptionAvailable: Bool?
        public var serverKeepAlive: UInt16?
        public var responseInformation: String?
        public var serverReference: String?
        public var authenticationMethod: String?
        public var authenticationData:Data?
        fileprivate init(_ properties:Properties){
            properties.forEach { p in
                switch p {
                case .sessionExpiryInterval(let uInt32):
                    self.sessionExpiryInterval = uInt32
                case .assignedClientIdentifier(let string):
                    self.assignedClientIdentifier = string
                case .serverKeepAlive(let uInt16):
                    self.serverKeepAlive = uInt16
                case .authenticationMethod(let string):
                    self.authenticationMethod = string
                case .authenticationData(let dataBuffer):
                    self.authenticationData = dataBuffer
                case .responseInformation(let string):
                    self.responseInformation = string
                case .serverReference(let string):
                    self.serverReference = string
                case .reasonString(let string):
                    self.reasonString = string
                case .receiveMaximum(let uInt16):
                    self.receiveMaximum = uInt16
                case .topicAliasMaximum(let uInt16):
                    self.topicAliasMaximum = uInt16
                case .maximumQoS(let mQTTQoS):
                    self.maximumQoS = mQTTQoS
                case .retainAvailable(let uInt8):
                    self.retainAvailable = uInt8 == 0 ? false : true
                case .maximumPacketSize(let uInt32):
                    self.maximumPacketSize = uInt32
                case .wildcardSubscriptionAvailable(let uInt8):
                    self.wildcardSubscriptionAvailable = uInt8 == 0 ? false : true
                case .subscriptionIdentifierAvailable(let uInt8):
                    self.subscriptionIdentifiersAvailable = uInt8 == 0 ? false : true
                case .sharedSubscriptionAvailable(let uInt8):
                    self.sharedSubscriptionAvailable = uInt8 == 0 ? false : true
                case .userProperty(let key, let value):
                    if self.userProperty == nil {
                        self.userProperty = [key:value]
                    }else{
                        self.userProperty?[key] = value
                    }
                default:
                    break
                }
            }
        }
    }
}
extension Property{
    public struct ACK{
        public var reasonString: String?
        public var userProperty: [String: String]?
        fileprivate init(_ properties:Properties){
            properties.forEach { p in
                switch p{
                case .reasonString(let str):
                    self.reasonString = str
                case .userProperty(let key, let value):
                    if self.userProperty == nil {
                        self.userProperty = [key:value]
                    }else{
                        self.userProperty?[key] = value
                    }
                default:
                    break
                }
            }
        }
    }
}
extension Property{
    public struct Publish{
        public var payloadFormat: UInt8?
        public var messageExpiry: UInt32?
        public var topicAlias: UInt16?
        public var responseTopic: String?
        public var correlationData: Data?
        public var userProperty: [String: String]?
        public var subscriptionIdentifier: Int?
        public var contentType: String?
        public init(){}
        init(_ properties:Properties){
            properties.forEach { p in
                switch p{
                case .payloadFormat(let uint):
                    self.payloadFormat = uint
                case .messageExpiry(let uint):
                    self.messageExpiry = uint
                case .topicAlias(let uint):
                    self.topicAlias = uint
                case .responseTopic(let str):
                    self.responseTopic = str
                case .correlationData(let data):
                    self.correlationData = data
                case .subscriptionIdentifier(let uint):
                    self.subscriptionIdentifier = uint
                case .contentType(let str):
                    self.contentType = str
                case .userProperty(let key, let value):
                    if self.userProperty == nil {
                        self.userProperty = [key:value]
                    }else{
                        self.userProperty?[key] = value
                    }
                default:
                    break
                }
            }
        }
        public var properties:Properties{
            var result = Properties()
            if let payloadFormat{
                result.append(.payloadFormat(payloadFormat))
            }
            if let messageExpiry{
                result.append(.messageExpiry(messageExpiry))
            }
            if let topicAlias{
                result.append(.topicAlias(topicAlias))
            }
            if let responseTopic{
                result.append(.responseTopic(responseTopic))
            }
            if let correlationData{
                result.append(.correlationData(correlationData))
            }
            if let subscriptionIdentifier{
                result.append(.subscriptionIdentifier(subscriptionIdentifier))
            }
            if let contentType{
                result.append(.contentType(contentType))
            }
            if let userProperty{
                userProperty.forEach { key,value in
                    result.append(.userProperty(key, value))
                }
            }
            return result
        }
    }
    
}
extension Property{
    
    public struct Auth{
        public var authenticationMethod: String?
        public var authenticationData: Data?
        public var reasonString: String?
        public var userProperty: [String: String]?
        public init(){}
        init(_ properties:Properties){
            properties.forEach { p in
                switch p{
                case .authenticationData(let data):
                    self.authenticationData = data
                case .authenticationMethod(let str):
                    self.authenticationMethod = str
                case .reasonString(let str):
                    self.reasonString = str
                case .userProperty(let key, let value):
                    if self.userProperty == nil {
                        self.userProperty = [key:value]
                    }else{
                        self.userProperty?[key] = value
                    }
                default:
                    break
                }
            }
        }
        public var properties:Properties{
            var result = Properties()
            if let authenticationMethod{
                result.append(.authenticationMethod(authenticationMethod))
            }
            if let authenticationData{
                result.append(.authenticationData(authenticationData))
            }
            if let reasonString{
                result.append(.reasonString(reasonString))
            }
            if let userProperty{
                userProperty.forEach { key,value in
                    result.append(.userProperty(key, value))
                }
            }
            return result
        }
    }
}
extension Property{
    public struct Connect{
        public var sessionExpiryInterval: UInt32?
        public var receiveMaximum: UInt16?
        public var maximumPacketSize: UInt32?
        public var topicAliasMaximum: UInt16?
        public var requestResponseInformation: UInt8?
        public var requestProblemInformation: UInt8?
        public var userProperty: [String: String]?
        public var authenticationMethod: String?
        public var authenticationData: Data?
        public init(){}
        fileprivate init(_ properties:Properties){
            properties.forEach { p in
                switch p{
                case .sessionExpiryInterval(let uint):
                    self.sessionExpiryInterval = uint
                case .receiveMaximum(let uint):
                    self.receiveMaximum = uint
                case .maximumPacketSize(let uint):
                    self.maximumPacketSize = uint
                case .topicAliasMaximum(let uint):
                    self.topicAliasMaximum = uint
                case .requestResponseInformation(let uint):
                    self.requestResponseInformation = uint
                case .requestProblemInformation(let uint):
                    self.requestProblemInformation = uint
                case .authenticationMethod(let str):
                    self.authenticationMethod = str
                case .authenticationData(let buffer):
                    self.authenticationData = buffer
                case .userProperty(let key, let value):
                    if self.userProperty == nil {
                        self.userProperty = [key:value]
                    }else{
                        self.userProperty?[key] = value
                    }
                default:
                    break
                }
            }
        }
        public var properties:Properties{
            var result = Properties()
            if let authenticationMethod{
                result.append(.authenticationMethod(authenticationMethod))
            }
            if let authenticationData{
                result.append(.authenticationData(authenticationData))
            }
            if let sessionExpiryInterval{
                result.append(.sessionExpiryInterval(sessionExpiryInterval))
            }
            if let maximumPacketSize{
                result.append(.maximumPacketSize(maximumPacketSize))
            }
            if let receiveMaximum{
                result.append(.receiveMaximum(receiveMaximum))
            }
            if let topicAliasMaximum{
                result.append(.topicAliasMaximum(topicAliasMaximum))
            }
            if let requestResponseInformation{
                result.append(.requestResponseInformation(requestResponseInformation))
            }
            if let requestProblemInformation{
                result.append(.requestProblemInformation(requestProblemInformation))
            }
            if let userProperty{
                userProperty.forEach { key,value in
                    result.append(.userProperty(key, value))
                }
            }
            return result
        }
    }
}
