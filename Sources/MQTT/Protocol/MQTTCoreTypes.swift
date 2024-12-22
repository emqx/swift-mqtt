//===----------------------------------------------------------------------===//
//
// This source file is part of the MQTTNIO project
//
// Copyright (c) 2020-2021 Adam Fowler
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

extension MQTT{
    public enum Version{
        case v5_0
        case v3_1_1
        var string:String{
            switch self {
            case .v5_0:
                return "5.0"
            case .v3_1_1:
                return "3.1.1"
            }
        }
    }
}
/// Indicates the level of assurance for delivery of a packet.
public enum MQTTQoS: UInt8, Sendable {
    /// fire and forget
    case atMostOnce = 0
    /// wait for PUBACK, if you don't receive it after a period of time retry sending
    case atLeastOnce = 1
    /// wait for PUBREC, send PUBREL and then wait for PUBCOMP
    case exactlyOnce = 2
}

/// MQTT Packet type enumeration
public enum MQTTPacketType: UInt8, Sendable {
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
public struct MQTTPublishInfo: Sendable {
    /// Quality of Service for message.
    public let qos: MQTTQoS

    /// Whether this is a retained message.
    public let retain: Bool

    /// Whether this is a duplicate publish message.
    public let dup: Bool

    /// Topic name on which the message is published.
    public let topicName: String

    /// MQTT v5 properties
    public let properties: Properties

    /// Message payload.
    public let payload: Data

    public init(qos: MQTTQoS, retain: Bool, dup: Bool = false, topicName: String, payload: Data, properties: Properties) {
        self.qos = qos
        self.retain = retain
        self.dup = dup
        self.topicName = topicName
        self.payload = payload
        self.properties = properties
    }
}

/// MQTT SUBSCRIBE packet parameters.
public struct MQTTSubscribeInfo: Sendable {
    /// Topic filter to subscribe to.
    public let topicFilter: String

    /// Quality of Service for subscription.
    public let qos: MQTTQoS

    public init(topicFilter: String, qos: MQTTQoS) {
        self.qos = qos
        self.topicFilter = topicFilter
    }
}

/// MQTT Sub ACK
///
/// Contains data returned in subscribe ack packets
public struct MQTTSuback: Sendable {
    public enum ReturnCode: UInt8, Sendable {
        case grantedQoS0 = 0
        case grantedQoS1 = 1
        case grantedQoS2 = 2
        case failure = 0x80
    }

    /// MQTT v5 subscribe return codes
    public let returnCodes: [ReturnCode]

    init(returnCodes: [MQTTSuback.ReturnCode]) {
        self.returnCodes = returnCodes
    }
}


/// MQTT v5 Connack
public struct MQTTConnackV5: Sendable {
    /// is using session state from previous session
    public let sessionPresent: Bool
    /// connect reason code
    public let reason: MQTTReasonCode
    /// properties
    public let properties: Properties
}

/// MQTT v5 ACK information. Returned with PUBACK, PUBREL
public struct MQTTAckV5: Sendable {
    /// MQTT v5 reason code
    public let reason: MQTTReasonCode
    /// MQTT v5 properties
    public let properties: Properties

    init(reason: MQTTReasonCode = .success, properties: Properties = .init()) {
        self.reason = reason
        self.properties = properties
    }
}

/// MQTT v5 SUBSCRIBE packet parameters.
public struct MQTTSubscribeInfoV5: Sendable {
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

/// MQTT v5 Sub ACK packet
///
/// Contains data returned in subscribe/unsubscribe ack packets
public struct MQTTSubackV5: Sendable {
    /// MQTT v5 subscription reason code
    public let reasons: [MQTTReasonCode]
    /// MQTT v5 properties
    public let properties: Properties

    init(reasons: [MQTTReasonCode], properties: Properties = .init()) {
        self.reasons = reasons
        self.properties = properties
    }
}

/// MQTT V5 Auth packet
///
/// An AUTH packet is sent from Client to Server or Server to Client as
/// part of an extended authentication exchange, such as challenge / response
/// authentication
public struct MQTTAuthV5: Sendable {
    /// MQTT v5 authentication reason code
    public let reason: MQTTReasonCode
    /// MQTT v5 properties
    public let properties: Properties

    init(reason: MQTTReasonCode, properties: Properties) {
        self.reason = reason
        self.properties = properties
    }
}
