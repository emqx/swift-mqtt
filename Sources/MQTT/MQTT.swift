//
//  MQTT.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation
import Promise

///
/// Global MQTT namespace
///
public enum MQTT{ }


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

/// Indicates the level of assurance for delivery of a packet.
public enum MQTTQoS: UInt8, Sendable {
    /// fire and forget
    case atMostOnce = 0
    /// wait for PUBACK, if you don't receive it after a period of time retry sending
    case atLeastOnce = 1
    /// wait for PUBREC, send PUBREL and then wait for PUBCOMP
    case exactlyOnce = 2
}

extension MQTT{
    public enum Version{
        case v5_0
        case v3_1_1
        var string:String{
            switch self {
            case .v5_0:  return "5.0"
            case .v3_1_1: return "3.1.1"
            }
        }
        var byte: UInt8 {
            switch self {
            case .v3_1_1: return 4
            case .v5_0: return 5
            }
        }
    }
    public class Config{
        /// protocol version init in client
        public internal(set) var version:MQTT.Version
        /// Version of MQTT server client is connecting to
        public internal(set)var clientId: String
        /// timeout for server response
        public var timeout: TimeInterval = 5
        /// MQTT user name.
        public var username: String? = nil
        /// MQTT password.
        public var password: String? = nil
        /// timeout for server response
        public var pingTimeout: TimeInterval = 5
        /// enable auto ping
        public var pingEnabled: Bool = true
        /// timeout for connecting to server
        public var connectTimeout: TimeInterval = 5
        /// MQTT keep alive period.
        public var keepAlive: UInt16 = 60{
            didSet{
                assert(keepAlive>0, "keepalive has to be greater than zero!")
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
        private var sendPacket: any Packet
        private var timeoutItem:DispatchWorkItem?
        init(_ packet:Packet){
            self.promise = .init()
            self.sendPacket = packet
        }
        func done(with packet: any Packet){
            self.promise.done(packet)
            self.timeoutItem?.cancel()
            self.timeoutItem = nil
        }
        func done(with error: any Error){
            self.promise.done(error)
            self.timeoutItem?.cancel()
            self.timeoutItem = nil
        }
        func start(_ timeout:UInt64? = nil) -> Promise<Packet>{
            if let timeout{
                let item = DispatchWorkItem{
                    self.promise.done(MQTTError.timeout)
                }
                DispatchQueue.global().asyncAfter(deadline: .now()+TimeInterval(timeout), execute: item)
                self.timeoutItem = item
            }
            return self.promise
        }
    }
}
