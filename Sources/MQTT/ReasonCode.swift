//
//  Reader.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation

 public enum AuthReasonCode: UInt8 {
    case success = 0x00
    case continueAuthentication = 0x18
    case ReAuthenticate = 0x19
}

 public enum ConnAckReasonCode: UInt8 {
    case success = 0x00
    case unspecifiedError = 0x80
    case malformedPacket = 0x81
    case protocolError = 0x82
    case implementationSpecificError = 0x83
    case unsupportedProtocolVersion = 0x84
    case clientIdentifierNotValid = 0x85
    case badUsernameOrPassword = 0x86
    case notAuthorized = 0x87
    case serverUnavailable = 0x88
    case serverBusy = 0x89
    case banned = 0x8A
    case badAuthenticationMethod = 0x8C
    case topicNameInvalid = 0x90
    case packetTooLarge = 0x95
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
    case retainNotSupported = 0x9A
    case qosNotSupported = 0x9B
    case useAnotherServer = 0x9C
    case serverMoved = 0x9D
    case connectionRateExceeded = 0x9F
}

 public enum PubAckReasonCode: UInt8 {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
}

 public enum PubCompReasonCode: UInt8 {
    case success = 0x00
    case packetIdentifierNotFound = 0x92
}

 public enum PubRecReasonCode: UInt8 {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
}

 public enum PubRelReasonCode: UInt8 {
    case success = 0x00
    case packetIdentifierNotFound = 0x92
}

 public enum SubAckReasonCode: UInt8 {
    case grantedQoS0 = 0x00
    case grantedQoS1 = 0x01
    case grantedQoS2 = 0x02
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case sharedSubscriptionsNotSupported = 0x9E
    case subscriptionIdentifiersNotSupported = 0xA1
    case wildcardSubscriptionsNotSupported = 0xA2
}

 public enum UnsubAckReasonCode: UInt8 {
    case success = 0x00
    case noSubscriptionExisted = 0x11
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUse = 0x91
}

 public enum RetainHandlingOption: UInt8 {
    case sendOnSubscribe = 0
    case sendOnlyWhenSubscribeIsNew = 1
    case none = 2
}

 public enum PayloadFormatIndicator: UInt8 {
    case unspecified = 0x00
    case utf8 = 0x01
}
