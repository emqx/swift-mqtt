//
//  CoreTypes.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation

/// MQTT PUBLISH packet parameters.
public struct Message: Sendable {
    /// Quality of Service for message.
    public let qos: MQTTQoS
    
    /// Whether this is a duplicate publish message.
    public let dup: Bool

    /// Topic name on which the message is published.
    public let topic: String
    
    /// Whether this is a retained message.
    public let retain: Bool
    
    /// Message payload.
    public let payload: Data

    /// MQTT v5 properties
    public let properties: Properties
    
    init(qos: MQTTQoS, dup: Bool, topic: String, retain: Bool, payload: Data, properties: Properties) {
        self.qos = qos
        self.dup = dup
        self.topic = topic
        self.retain = retain
        self.payload = payload
        self.properties = properties
    }
    func duplicate()->Message{
        .init(qos: qos, dup: true, topic: topic, retain: retain, payload: payload, properties: properties)
    }
}

/// MQTT v5 `SUBSCRIBE` packet parameters.
public struct Subscribe: Sendable {
    /// Topic filter to subscribe to.
    public let topicFilter: String
    /// Quality of Service for subscription.
    public let qos: MQTTQoS
    /// Don't forward message published by this client
    public let noLocal: Bool
    /// Keep retain flag message was published with
    public let retainAsPublished: Bool
    /// Retain handing
    public let retainHandling: RetainHandling
    public init(
        _ topicFilter: String,
        qos: MQTTQoS = .atLeastOnce,
        noLocal: Bool = false,
        retainAsPublished: Bool = true,
        retainHandling: RetainHandling = .sendIfNew
    ) {
        self.qos = qos
        self.topicFilter = topicFilter
        self.noLocal = noLocal
        self.retainAsPublished = retainAsPublished
        self.retainHandling = retainHandling
    }
    /// Retain handling options
    public enum RetainHandling: UInt8, Sendable {
        /// always send retain message
        case sendAlways = 0
        /// send retain if new
        case sendIfNew = 1
        /// do not send retain message
        case doNotSend = 2
    }
    /// MQTT v3 `SUBSCRIBE` packet parameters.
    public struct V3: Sendable {
        /// Topic filter to subscribe to.
        public let topicFilter: String
        /// Quality of Service for subscription.
        public let qos: MQTTQoS
        public init(_ topicFilter: String, qos: MQTTQoS) {
            self.qos = qos
            self.topicFilter = topicFilter
        }
    }
}


/// MQTT V5 Auth packet
///
/// An AUTH packet is sent from Client to Server or Server to Client as
/// part of an extended authentication exchange, such as challenge / response
/// authentication
public struct Auth: Sendable {
    /// MQTT v5 authentication reason code
    public let code: ResultCode.Auth
    /// MQTT v5 properties. It will be empty in v3
    public let properties: Property.Auth?
    init(code: ResultCode.Auth, properties: Properties) {
        self.code = code
        self.properties = properties.isEmpty ? nil : properties.auth()
    }
    func packet()->AuthPacket{
        .init(code: code, properties: properties?.properties ?? [])
    }
}
/// MQTT v5 ACK information. Returned with `PUBACK`, `PUBREL`
public struct Puback: Sendable ,Equatable{
    /// MQTT v5 reason code
    public let code: ResultCode.Puback
    /// MQTT v5 properties. It will be empty in v3
    public let properties: Property.ACK?
    init(code: ResultCode.Puback = .success, properties: Properties = .init()) {
        self.code = code
        self.properties = properties.isEmpty ? nil : properties.ack()
    }
}
/// Contains data returned in subscribe ack packets
public struct Suback: Sendable {
    /// MQTT v3 and  v5 subscription reason code
    public let codes: [ResultCode.Suback]
    /// MQTT v5 properties. It will be empty in v3
    public let properties: Property.ACK?
    init(codes: [ResultCode.Suback], properties: Properties = .init()) {
        self.codes = codes
        self.properties = properties.isEmpty ? nil : properties.ack()
    }
}
/// Contains data returned in subscribe ack packets
public struct Unsuback: Sendable {
    /// MQTT v3 and  v5 subscription reason code
    public let codes: [ResultCode.Unsuback]
    /// MQTT v5 properties. It will be empty in v3
    public let properties: Property.ACK?
    init(codes: [ResultCode.Unsuback], properties: Properties = .init()) {
        self.codes = codes
        self.properties = properties.isEmpty ? nil : properties.ack()
    }
}

/// MQTT v5 Connack
public struct Connack: Sendable {
    /// connect reason code
    public let code: ResultCode.Connect
    /// MQTT v5 properties. It will be empty in v3
    public let properties: Property.Connack?
    /// is using session state from previous session
    public let sessionPresent: Bool
    init(code: ResultCode.Connect, properties: Properties, sessionPresent: Bool) {
        self.code = code
        self.properties = properties.connack()
        self.sessionPresent = sessionPresent
    }
}




