//
//  Reason.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation

/// MQTT v5.0 reason codes.
///
/// A reason code is a one byte unsigned value that indicates the result of an operation.
/// Reason codes less than 128 are considered successful. Codes greater than or equal to 128 are considered
/// a failure. These are returned by CONNACK, PUBACK, PUBREC, PUBREL, PUBCOMP, DISCONNECT and
/// AUTH packets
//public enum ReasonCode: UInt8, Sendable,Equatable {
//    /// Success (available for all). For SUBACK mean QoS0 is available
//    case success = 0
//    /// The subscription is accepted and the maximum QoS sent will be QoS 1. This might be a lower QoS than was requested.
//    case grantedQoS1 = 1
//    /// The subscription is accepted and any received QoS will be sent to this subscription.
//    case grantedQoS2 = 2
//    /// The Client wishes to disconnect but requires that the Server also publishes its Will Message.
//    case disconnectWithWill = 4
//    /// The PUBLISH message is accepted but there are no subscribers. This is sent only by the Server. If the Server knows that
//    /// there are no matching subscribers, it MAY use this Reason Code instead of 0x00 (Success).
//    case noMatchingSubscriber = 16
//    /// No matching Topic Filter is being used by the Client.
//    case noSubscriptionExisted = 17
//    /// Continue the authentication with another step
//    case continueAuthentication = 24
//    /// Initiate a re-authentication
//    case reAuthenticate = 25
//    /// Unaccpeted and the Server either does not wish to reveal the reason or none of the other Reason Codes apply.
//    case unspecifiedError = 128
//    /// Data within the packet could not be correctly parsed.
//    case malformedPacket = 129
//    /// Data in the packet does not conform to this specification.
//    case protocolError = 130
//    /// Packet is valid but the server does not accept it
//    case implementationSpecificError = 131
//    /// The Server does not support the version of the MQTT protocol requested by the Client.
//    case unsupportedProtocolVersion = 132
//    /// The Client Identifier is a valid string but is not allowed by the Server.
//    case clientIdentifierNotValid = 133
//    /// The Server does not accept the User Name or Password specified by the Client
//    case badUsernameOrPassword = 134
//    /// The client is not authorized to do this
//    case notAuthorized = 135
//    /// The MQTT Server is not available.
//    case serverUnavailable = 136
//    /// The Server is busy. Try again later.
//    case serverBusy = 137
//    /// This Client has been banned by administrative action. Contact the server administrator.
//    case banned = 138
//    /// The Server is shutting down.
//    case serverShuttingDown = 139
//    /// The authentication method is not supported or does not match the authentication method currently in use.
//    case badAuthenticationMethod = 140
//    /// The Connection is closed because no packet has been received for 1.5 times the Keepalive time.
//    case keepAliveTimeout = 141
//    /// Another Connection using the same ClientID has connected causing this Connection to be closed.
//    case sessionTakenOver = 142
//    /// The Topic Filter is correctly formed but is not allowed for this Client.
//    case topicFilterInvalid = 143
//    /// The Topic Name is not malformed, but is not accepted by this Client or Server.
//    case topicNameInvalid = 144
//    /// The specified Packet Identifier is already in use. This might indicate a mismatch in the Session State between the Client and Server.
//    case packetIdentifierInUse = 145
//    /// The Packet Identifier is not known. This is not an error during recovery, but at other times indicates a mismatch between
//    /// the Session State on the Client and Server.
//    case packetIdentifierNotFound = 146
//    /// The Client or Server has received more than Receive Maximum publication for which it has not sent PUBACK or PUBCOMP.
//    case receiveMaximumExceeded = 147
//    /// The Client or Server has received a PUBLISH packet containing a Topic Alias which is greater than the Maximum Topic Alias it
//    /// sent in the CONNECT or CONNACK packet.
//    case topicAliasInvalid = 148
//    /// The packet exceeded the maximum permissible size.
//    case packetTooLarge = 149
//    /// The received data rate is too high.
//    case messageRateTooHigh = 150
//    /// An implementation or administrative imposed limit has been exceeded.
//    case quotaExceeded = 151
//    /// The Connection is closed due to an administrative action.
//    case administrativeAction = 152
//    /// The PUBLISH payload format does not match the one specified in the Payload Format Indicator.
//    case payloadFormatInvalid = 153
//    /// The Server does not support retained messages, and retain was set to 1.
//    case retainNotSupported = 154
//    /// The Server does not support the QoS set
//    case qosNotSupported = 155
//    /// The Client should temporarily use another server.
//    case useAnotherServer = 156
//    /// The Client should permanently use another server.
//    case serverMoved = 157
//    /// The Server does not support Shared Subscriptions for this Client.
//    case sharedSubscriptionsNotSupported = 158
//    /// The connection rate limit has been exceeded.
//    case connectionRateExceeded = 159
//    /// The maximum connection time authorized for this connection has been exceeded.
//    case maximumConnectTime = 160
//    /// The Server does not support Subscription Identifiers; the subscription is not accepted.
//    case subscriptionIdentifiersNotSupported = 161
//    /// The Server does not support Wildcard Subscriptions; the subscription is not accepted.
//    case wildcardSubscriptionsNotSupported = 162
//    /// Reason code was unrecognised
//    case unrecognisedReason = 255
//}
//
//
///// Value returned in connection error in v3
//public enum ConnectCode: UInt8, Sendable,Equatable {
//    /// connection was accepted
//    case accepted = 0
//    /// The Server does not support the version of the MQTT protocol requested by the Client.
//    case unacceptableProtocolVersion = 1
//    /// The Client Identifier is a valid string but is not allowed by the Server.
//    case identifierRejected = 2
//    /// The MQTT Server is not available.
//    case serverUnavailable = 3
//    /// The Server does not accept the User Name or Password specified by the Client
//    case badUserNameOrPassword = 4
//    /// The client is not authorized to connect
//    case notAuthorized = 5
//    /// Reason code was unrecognised
//    case unrecognisedReason = 0xFF
//}

/// MQTT reason codes.
///
/// A reason code is a one byte unsigned value that indicates the result of an operation.
/// Reason codes less than 128 are considered successful. Codes greater than or equal to 128 are considered
/// a failure. These are returned by CONNACK, PUBACK, PUBREC, PUBREL, PUBCOMP, DISCONNECT and
/// AUTH packets
///
public enum ResultCode:Sendable,Hashable,CustomStringConvertible{
    case auth(Auth)
    case connectv3(ConnectV3)
    case connect(Connect)
    case disconnect(Disconnect)
    case puback(Puback)
    case suback(Suback)
    case unsuback(Unsuback)
    public var description: String{
        switch self {
        case .auth(let auth):
            return "\(auth)"
        case .connectv3(let v3):
            return "\(v3)"
        case .connect(let connect):
            return "\(connect)"
        case .disconnect(let disconnect):
            return "\(disconnect)"
        case .puback(let puback):
            return "\(puback)"
        case .suback(let suback):
            return "\(suback)"
        case .unsuback(let unsuback):
            return "\(unsuback)"
        }
    }
}
extension ResultCode{
    public enum Auth: UInt8,Sendable,Hashable {
        case success = 0x00
        /// Continue the authentication with another step
        case continueAuthentication = 0x18
        /// Initiate a re-authentication
        case reAuthenticate = 0x19
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }
    /// Value returned in connection error in v3
    public enum ConnectV3: UInt8, Sendable,Hashable {
        /// connection was accepted
        case accepted = 0
        /// The Server does not support the version of the MQTT protocol requested by the Client.
        case unacceptableProtocolVersion = 1
        /// The Client Identifier is a valid string but is not allowed by the Server.
        case identifierRejected = 2
        /// The MQTT Server is not available.
        case serverUnavailable = 3
        /// The Server does not accept the User Name or Password specified by the Client
        case badUserNameOrPassword = 4
        /// The client is not authorized to connect
        case notAuthorized = 5
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }
    /// Value returned in connection of v5
    public enum Connect: UInt8,Sendable,Hashable{
        /// connection was accepted
        case accepted = 0x00
        /// Unaccpeted and the Server either does not wish to reveal the reason or none of the other Reason Codes apply.
        case unspecifiedError = 0x80
        /// Data within the packet could not be correctly parsed.
        case malformedPacket = 0x81
        /// Data in the packet does not conform to this specification.
        case protocolError = 0x82
        /// Packet is valid but the server does not accept it
        case implementationSpecificError = 0x83
        /// The Server does not support the version of the MQTT protocol requested by the Client.
        case unsupportedProtocolVersion = 0x84
        /// The Client Identifier is a valid string but is not allowed by the Server.
        case clientIdentifierNotValid = 0x85
        /// The Server does not accept the User Name or Password specified by the Client
        case badUsernameOrPassword = 0x86
        /// The client is not authorized to do this
        case notAuthorized = 0x87
        /// The MQTT Server is not available.
        case serverUnavailable = 0x88
        /// The Server is busy. Try again later.
        case serverBusy = 0x89
        /// This Client has been banned by administrative action. Contact the server administrator.
        case banned = 0x8A
        /// The authentication method is not supported or does not match the authentication method currently in use.
        case badAuthenticationMethod = 0x8C
        /// The Topic Name is not malformed, but is not accepted by this Client or Server.
        case topicNameInvalid = 0x90
        /// The packet exceeded the maximum permissible size.
        case packetTooLarge = 0x95
        /// An implementation or administrative imposed limit has been exceeded.
        case quotaExceeded = 0x97
        /// The PUBLISH payload format does not match the one specified in the Payload Format Indicator.
        case payloadFormatInvalid = 0x99
        /// The Server does not support retained messages, and retain was set to 1.
        case retainNotSupported = 0x9A
        /// The Server does not support the QoS set
        case qosNotSupported = 0x9B
        /// The Client should temporarily use another server.
        case useAnotherServer = 0x9C
        /// The Client should permanently use another server.
        case serverMoved = 0x9D
        /// The connection rate limit has been exceeded.
        case connectionRateExceeded = 0x9F
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }

    public enum Disconnect: UInt8,Sendable,Hashable {
        case normal = 0x00
        /// The Client wishes to disconnect but requires that the Server also publishes its Will Message.
        case disconnectWithWill = 0x04
        /// Unaccpeted and the Server either does not wish to reveal the reason or none of the other Reason Codes apply.
        case unspecifiedError = 0x80
        /// Data within the packet could not be correctly parsed.
        case malformedPacket = 0x81
        /// Data in the packet does not conform to this specification.
        case protocolError = 0x82
        /// Packet is valid but the server does not accept it
        case implementationSpecificError = 0x83
        /// The client is not authorized to do this
        case notAuthorized = 0x87
        /// The Server is busy. Try again later.
        case serverBusy = 0x89
        /// The Server is shutting down.
        case serverShuttingDown = 0x8B
        /// The Connection is closed because no packet has been received for 1.5 times the Keepalive time.
        case keepAliveTimeout = 0x8D
        /// Another Connection using the same ClientID has connected causing this Connection to be closed.
        case sessionTakenOver = 0x8E
        /// The Topic Filter is correctly formed but is not allowed for this Client.
        case topicFilterInvalid = 0x8F
        /// The Topic Name is not malformed, but is not accepted by this Client or Server.
        case topicNameInvalid = 0x90
        /// The Client or Server has received more than Receive Maximum publication for which it has not sent PUBACK or PUBCOMP.
        case receiveMaximumExceeded = 0x93
        /// The Client or Server has received a PUBLISH packet containing a Topic Alias which is greater than the Maximum Topic Alias it
        /// sent in the CONNECT or CONNACK packet.
        case topicAliasInvalid = 0x94
        /// The packet exceeded the maximum permissible size.
        case packetTooLarge = 0x95
        /// The received data rate is too high.
        case messageRateTooHigh = 0x96
        /// An implementation or administrative imposed limit has been exceeded.
        case quotaExceeded = 0x97
        /// The Connection is closed due to an administrative action.
        case administrativeAction = 0x98
        /// The PUBLISH payload format does not match the one specified in the Payload Format Indicator.
        case payloadFormatInvalid = 0x99
        /// The Server does not support retained messages, and retain was set to 1.
        case retainNotSupported = 0x9A
        /// The Server does not support the QoS set
        case qosNotSupported = 0x9B
        /// The Client should temporarily use another server.
        case useAnotherServer = 0x9C
        /// The Client should permanently use another server.
        case serverMoved = 0x9D
        /// The Server does not support Shared Subscriptions for this Client.
        case sharedSubscriptionsNotSupported = 0x9E
        /// The connection rate limit has been exceeded.
        case connectionRateExceeded = 0x9F
        /// The maximum connection time authorized for this connection has been exceeded.
        case maximumConnectTime = 0xA0
        /// The Server does not support Subscription Identifiers; the subscription is not accepted.
        case subscriptionIdentifiersNotSupported = 0xA1
        /// The Server does not support Wildcard Subscriptions; the subscription is not accepted.
        case wildcardSubscriptionsNotSupported = 0xA2
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }
    /// include `PUBACK` `PUBREC` `PUBREL` `PUBCOMB`
    public enum Puback: UInt8,Sendable,Hashable {
        case success = 0x00
        /// The `PUBLISH` message is accepted but there are no subscribers. This is sent only by the Server. If the Server knows that
        /// there are no matching subscribers, it MAY use this Reason Code instead of 0x00 (Success).
        case noMatchingSubscribers = 0x10
        /// Unaccpeted and the Server either does not wish to reveal the reason or none of the other Reason Codes apply.
        case unspecifiedError = 0x80
        /// Packet is valid but the server does not accept it
        case implementationSpecificError = 0x83
        /// The client is not authorized to connect
        case notAuthorized = 0x87
        /// The Topic Name is not malformed, but is not accepted by this Client or Server.
        case topicNameInvalid = 0x90
        /// The specified Packet Identifier is already in use. This might indicate a mismatch in the Session State between the Client and Server.
        case packetIdentifierInUse = 0x91
        /// The Packet Identifier is not known. This is not an error during recovery, but at other times indicates a mismatch between
        /// the Session State on the Client and Server.
        case packetIdentifierNotFound = 0x92
        /// An implementation or administrative imposed limit has been exceeded.
        case quotaExceeded = 0x97
        /// The PUBLISH payload format does not match the one specified in the Payload Format Indicator.
        case payloadFormatInvalid = 0x99
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }
    public enum Suback: UInt8,Sendable,Hashable {
        /// QoS0 is available
        case grantedQoS0 = 0x00
        /// The subscription is accepted and the maximum QoS sent will be QoS 1. This might be a lower QoS than was requested.
        case grantedQoS1 = 0x01
        /// The subscription is accepted and any received QoS will be sent to this subscription.
        case grantedQoS2 = 0x02
        /// Unaccpeted and the Server either does not wish to reveal the reason or none of the other Reason Codes apply.
        case unspecifiedError = 0x80
        /// Packet is valid but the server does not accept it
        case implementationSpecificError = 0x83
        case notAuthorized = 0x87
        /// The Topic Filter is correctly formed but is not allowed for this Client.
        case topicFilterInvalid = 0x8F
        /// The specified Packet Identifier is already in use. This might indicate a mismatch in the Session State between the Client and Server.
        case packetIdentifierInUse = 0x91
        /// An implementation or administrative imposed limit has been exceeded.
        case quotaExceeded = 0x97
        /// The Server does not support Shared Subscriptions for this Client.
        case sharedSubscriptionsNotSupported = 0x9E
        /// The Server does not support Subscription Identifiers; the subscription is not accepted.
        case subscriptionIdentifiersNotSupported = 0xA1
        /// The Server does not support Wildcard Subscriptions; the subscription is not accepted.s
        case wildcardSubscriptionsNotSupported = 0xA2
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }

    public enum Unsuback: UInt8,Sendable,Hashable {
        /// unsubscripti sucessfully
        case success = 0x00
        /// No matching Topic Filter is being used by the Client.
        case noSubscriptionExisted = 0x11
        /// Unaccpeted and the Server either does not wish to reveal the reason or none of the other Reason Codes apply.
        case unspecifiedError = 0x80
        /// Packet is valid but the server does not accept it
        case implementationSpecificError = 0x83
        /// The client is not authorized to connect
        case notAuthorized = 0x87
        /// The Topic Filter is correctly formed but is not allowed for this Client.
        case topicFilterInvalid = 0x8F
        /// The specified Packet Identifier is already in use. This might indicate a mismatch in the Session State between the Client and Server.
        case packetIdentifierInUse = 0x91
        /// Reason code was unrecognised
        case unrecognisedReason = 0xFF
    }
}
