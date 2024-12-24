//
//  MQTT.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation

///
/// Global MQTT namespace
///
public enum MQTT{ }

extension MQTT{
    nonisolated(unsafe) static var logger:Logger = .init(minLevel: .warning)
    public static var logLevel:Logger.Level{
        get {logger.minLevel}
        set {logger = .init(minLevel: newValue)}
    }
    public struct Logger:Sendable{
        let minLevel: Level
        private func log(_ level: Level, message: String) {
            guard level.rawValue >= minLevel.rawValue else { return }
            print("MQTT(\(level)): \(message)")
        }
        public static func debug(_ message: String) {
            logger.log(.debug, message: message)
        }
        public static func info(_ message: String) {
            logger.log(.info, message: message)
        }
        public static func warning(_ message: String) {
            logger.log(.warning, message: message)
        }
        public static func error(_ message: String) {
            logger.log(.error, message: message)
        }
        public static func error(_ error: Error?){
            logger.log(.error, message: error.debugDescription)
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
            case .v5_0:
                return "5.0"
            case .v3_1_1:
                return "3.1.1"
            }
        }
        var byte: UInt8 {
            switch self {
            case .v3_1_1:
                return 4
            case .v5_0:
                return 5
            }
        }
    }
    public class Config{
        /// protocol version init in client
        public internal(set) var version:MQTT.Version
        /// timeout for server response
        public var timeout: TimeInterval = 5
        /// Version of MQTT server client is connecting to
        public var clientId: String
        /// MQTT user name.
        public var username: String? = nil
        /// MQTT password.
        public var password: String? = nil
        /// MQTT keep alive period.
        public var keepAlive: UInt16 = 60{
            didSet{
                assert(keepAlive>0, "The keepAlive value must be greater than 0!")
            }
        }
        /// timeout for server response
        public var pingTimeout: TimeInterval = 5
        /// enable auto ping
        public var pingEnabled: Bool = true
        /// timeout for connecting to server
        public var connectTimeout: TimeInterval = 5
        init(_ version:Version,clientId:String){
            self.version = version
            self.clientId = clientId
        }
    }
}
