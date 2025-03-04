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
        /// MQTT user name.
        public var username: String? = nil
        /// MQTT password.
        public var password: String? = nil
        /// MQTT keep alive period in second.
        public var keepAlive: UInt16 = 60{
            didSet{
                assert(keepAlive>0, "keepalive has to be greater than zero!")
            }
        }
        /// enable `keepAlive`
        public var pingEnabled: Bool = true
        /// timeout second for `keepAlive`
        public var pingTimeout: TimeInterval = 5
        /// timeout millisecond  for connecting to server
        /// - Important: This setting does not take effect in the quic protocol. In the quic protocol is fixed at 30s and cannot be modified
        public var connectTimeout: UInt64 = 30 * 1000
        /// timeout millisecond  for pubulish  flow ac
        public var publishTimeout: UInt64 = 5 * 1000
        /// timeout millisecond for write data to connection
        public var writingTimeout: UInt64 = 5 * 1000
        init(_ version:Version,clientId:String){
            self.version = version
            self.clientId = clientId
        }
    }
}
extension MQTT{
    class Task:@unchecked Sendable{
        private let promise:Promise<Packet>
        private var timeoutItem:DispatchWorkItem?
        init(){
            self.promise = .init()
        }
        func done(with packet: Packet){
            self.promise.done(packet)
            self.timeoutItem?.cancel()
            self.timeoutItem = nil
        }
        func done(with error: any Error){
            self.promise.done(error)
            self.timeoutItem?.cancel()
            self.timeoutItem = nil
        }
        func start(in queue:DispatchQueue, timeout:UInt64? = nil) -> Promise<Packet>{
            if let timeout{
                let item = DispatchWorkItem{
                    self.promise.done(MQTTError.timeout)
                }
                queue.asyncAfter(deadline: .now()+TimeInterval(timeout)/1000, execute: item)
                self.timeoutItem = item
            }
            return self.promise
        }
    }
}
extension MQTT{
    /// Array of inflight packets. Used to resend packets when reconnecting to server
    struct Inflight : Sendable{
        @Safely private(set) var packets: [Packet] = []
        /// add packet
        func add(packet: Packet) {
            self.$packets.write { pkgs in
                pkgs.append(packet)
            }
        }
        /// remove packert
        func remove(id: UInt16) {
            self.$packets.write { pkgs in
                guard let first = pkgs.firstIndex(where: { $0.id == id }) else { return }
                pkgs.remove(at: first)
            }
        }
        /// remove all packets
        mutating func clear() {
            self.$packets.write { pkgs in
                pkgs = []
            }
        }
    }
}
