//
//  MQTT.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation
@_exported import Promise

///
/// Global MQTT namespace
///
public enum MQTT:Sendable{ }


extension MQTT{
    public enum Logger:Sendable{
        nonisolated(unsafe) public static var level:Level = .warning
        private static func log(_ level: Level, message: String) {
            guard level.rawValue >= self.level.rawValue else { return }
            print("MQTT(\(level)): \(message)")
        }
        public static func debug(_ message: String) {
            log(.debug, message: message)
        }
        public static func info(_ message: String) {
            log(.info, message: message)
        }
        public static func warning(_ message: String) {
            log(.warning, message: message)
        }
        public static func error(_ message: String) {
            log(.error, message: message)
        }
        public static func error(_ error: Error?){
            log(.error, message: error.debugDescription)
        }
    }
}
extension MQTT.Logger{
    public enum Level: Int, Sendable {
        case debug = 0, info, warning, error, off
    }
}
extension MQTT{
    public enum Version:Sendable{
        case v5_0
        case v3_1_1
        var string:String{
            switch self {
            case .v5_0:  return "5.0"
            case .v3_1_1: return "3.1.1"
            }
        }
        var uint8: UInt8 {
            switch self {
            case .v3_1_1: return 4
            case .v5_0: return 5
            }
        }
    }
    public final class Config:@unchecked Sendable{
        /// protocol version init in client
        public let version:MQTT.Version
        /// Version of MQTT server client is connecting to
        public internal(set) var clientId: String
        /// MQTT username.
        /// - Note:Please set this value before client open, otherwise it will take effect on the next open
        public var username: String? = nil
        /// MQTT password.
        /// - Note:Please set this value before client open, otherwise it will take effect on the next open
        public var password: String? = nil
        /// MQTT keep alive period in second.
        /// It will take effect immediately
        public var keepAlive: UInt16 = 60{
            didSet{
                assert(keepAlive>0, "keepalive must be greater than zero!")
            }
        }
        /// enable `keepAlive`
        /// - Note:Please set this value before client open, otherwise it will take effect on the next open
        public var pingEnabled: Bool = true
        /// timeout second for `keepAlive`
        /// It will take effect at next ping request
        public var pingTimeout: TimeInterval = 5{
            didSet{
                assert(pingTimeout>0, "pingTimeout must be greater than zero!")
            }
        }
        ///The max times the connection consecutive ping timeouts
        /// It will take effect immediately
        public var maxPingCount:UInt8 = 1{
            didSet{
                assert(maxPingCount>0, "maxPingCount must be greater than zero!")
            }
        }
        /// timeout second  for connecting to server
        /// - Important: This setting does not take effect in the quic protocol. In the quic protocol is fixed at 30s and cannot be modified
        /// - Note:Please set this value before client open, otherwise it will take effect on the next open
        public var connectTimeout: TimeInterval = 30{
            didSet{
                assert(connectTimeout>0, "connectTimeout must be greater than zero!")
            }
        }
        /// timeout second  for pubulish  flow acks
        /// It will take effect immediately
        public var publishTimeout: TimeInterval = 5{
            didSet{
                assert(publishTimeout>0, "publishTimeout must be greater than zero!")
            }
        }
        /// timeout second for write data to connection
        /// It will take effect immediately
        public var writingTimeout: TimeInterval = 5{
            didSet{
                assert(writingTimeout>0, "writingTimeout must be greater than zero!")
            }
        }
        init(_ version:Version,clientId:String){
            self.version = version
            self.clientId = clientId
        }
    }
}
extension MQTT{
    class Task:@unchecked Sendable{
        private let promise:Promise<Packet>
        private var item:DispatchWorkItem?
        init(){
            self.promise = .init()
        }
        func done(with packet: Packet){
            if self.promise.isDone{ return }
            self.promise.done(packet)
            self.item?.cancel()
            self.item = nil
        }
        func done(with error: any Error){
            if self.promise.isDone{ return }
            self.promise.done(error)
            self.item?.cancel()
            self.item = nil
        }
        func start(in queue:DispatchQueue, timeout:TimeInterval? = nil) -> Promise<Packet>{
            if let timeout{
                let item = DispatchWorkItem{[weak self] in
                    self?.promise.done(MQTTError.timeout)
                }
                queue.asyncAfter(deadline: .now()+timeout, execute: item)
                self.item = item
            }
            return self.promise
        }
    }
}
/// Indicates the level of assurance for delivery of a packet.
public enum MQTTQoS: UInt8, Sendable {
    /// fire and forget
    case atMostOnce = 0
    /// wait for `PUBACK`, if you don't receive it after a period of time retry sending
    case atLeastOnce = 1
    /// wait for `PUBREC`, send `PUBREL` and then wait for `PUBCOMP`
    case exactlyOnce = 2
}
public enum MQTTError:Sendable,Hashable, Swift.Error {
    /// client timed out while waiting for response from server
    /// This includes connection timeouts and writing timeouts
    case timeout
    /// client in not connect to the broker
    case unconnected
    /// never happen forever
    case neverHappened
    /// You called connect on a client that is already connected to the broker
    case alreadyOpened
    /// Client has already been closed
    case alreadyClosed
    /// Encode of MQTT packet error or invalid paarameters
    case packetError(Packet)
    /// Decode of MQTT message failed
    case decodeError(Decode)
    /// the server disconnected
    /// the server closed the connection. If this happens during a publish you can resend the publish packet by reconnecting to server with `cleanSession` set to false.
    case serverClose(ResultCode.Disconnect)
    /// user closed connectiion
    case clientClose(ResultCode.Disconnect)
    /// publish failed
    case publishFailed(ResultCode.Puback)
    /// We received an unexpected message while connecting
    /// result code may be  `ResultCode.ConnectV3` or `ResultCode.Connect` or `nil`
    case connectFailed(ResultCode? = nil)
    /// Invalid  certificate data when import tls cert file
    case invalidCertData
    /// The read stream has been completed
    case unexpectMessage
    /// Packet error incomplete packet
    case incompletePacket
    /// Auth packets sent without authWorkflow being supplied
    case authflowRequired
    
    
}
extension MQTTError{
    /// Errors generated by bad packets sent by the client
    public enum Packet:Sendable,Hashable {
        case badParameter
        /// Packet sent contained invalid entries
        /// QoS is not accepted by this connection as it is greater than the accepted value
        case qosInvalid
        /// publish messages on this connection do not support the retain flag
        case retainUnavailable
        /// subscribe/unsubscribe packet requires at least one topic
        case atLeastOneTopicRequired
        /// topic alias is greater than server maximum topic alias or the alias is zero
        case topicAliasOutOfRange
        /// invalid topic name
        case invalidTopicName
        /// client to server publish packets cannot include a subscription identifier
        case publishIncludesSubscription
    }
}


extension MQTTError{
    public enum Decode:Sendable,Hashable{
        /// Read variable length overflow
        case varintOverflow
        /// Reader stream completed
        case streamCompleted
        /// Packet received contained invalid tokens
        case unexpectedTokens
        /// got unexpected data length when read
        case unexpectedDataLength
        /// Failed to recognise the packet control type
        case unrecognisedPacketType
    }
}
