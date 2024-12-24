//
//  CoreTypes.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation





/// MQTT Packet type enumeration
public enum PacketType: UInt8, Sendable {
    case CONNECT = 0x10
    case CONNACK = 0x20
    case PUBLISH = 0x30
    case PUBACK = 0x40
    case PUBREC = 0x50
    case PUBREL = 0x62
    case PUBCOMP = 0x70
    case SUBSCRIBE = 0x82
    case SUBACK = 0x90
    case UNSUBSCRIBE = 0xA2
    case UNSUBACK = 0xB0
    case PINGREQ = 0xC0
    case PINGRESP = 0xD0
    case DISCONNECT = 0xE0
    case AUTH = 0xF0
}

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
}

/// MQTT SUBSCRIBE packet parameters.
public struct Subscribe: Sendable {
    /// Topic filter to subscribe to.
    public let topicFilter: String

    /// Quality of Service for subscription.
    public let qos: MQTTQoS

    public init(topicFilter: String, qos: MQTTQoS) {
        self.qos = qos
        self.topicFilter = topicFilter
    }
    /// MQTT v5 SUBSCRIBE packet parameters.
    public struct V5: Sendable {
        /// Retain handling options
        public enum RetainHandling: UInt8, Sendable {
            /// always send retain message
            case sendAlways = 0
            /// send retain if new
            case sendIfNew = 1
            /// do not send retain message
            case doNotSend = 2
        }

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
            topicFilter: String,
            qos: MQTTQoS,
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
    }
}

/// MQTT Sub ACK
///
/// Contains data returned in subscribe ack packets
public struct Suback: Sendable {
    public enum ReturnCode: UInt8, Sendable {
        case grantedQoS0 = 0
        case grantedQoS1 = 1
        case grantedQoS2 = 2
        case failure = 0x80
    }

    /// MQTT v5 subscribe return codes
    public let returnCodes: [ReturnCode]

    init(returnCodes: [Suback.ReturnCode]) {
        self.returnCodes = returnCodes
    }
    /// MQTT v5 Sub ACK packet
    ///
    /// Contains data returned in subscribe/unsubscribe ack packets
    public struct V5: Sendable {
        /// MQTT v5 subscription reason code
        public let reasons: [ReasonCode]
        /// MQTT v5 properties
        public let properties: Properties

        init(reasons: [ReasonCode], properties: Properties = .init()) {
            self.reasons = reasons
            self.properties = properties
        }
    }
}


/// MQTT v5 Connack
public struct ConnackV5: Sendable {
    /// is using session state from previous session
    public let sessionPresent: Bool
    /// connect reason code
    public let reason: ReasonCode
    /// properties
    public let properties: Properties
}

/// MQTT v5 ACK information. Returned with PUBACK, PUBREL
public struct AckV5: Sendable {
    /// MQTT v5 reason code
    public let reason: ReasonCode
    /// MQTT v5 properties
    public let properties: Properties

    init(reason: ReasonCode = .success, properties: Properties = .init()) {
        self.reason = reason
        self.properties = properties
    }
}





/// MQTT V5 Auth packet
///
/// An AUTH packet is sent from Client to Server or Server to Client as
/// part of an extended authentication exchange, such as challenge / response
/// authentication
public struct AuthV5: Sendable {
    /// MQTT v5 authentication reason code
    public let reason: ReasonCode
    /// MQTT v5 properties
    public let properties: Properties

    init(reason: ReasonCode, properties: Properties) {
        self.reason = reason
        self.properties = properties
    }
}
