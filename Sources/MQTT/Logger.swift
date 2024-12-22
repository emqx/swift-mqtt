//
//  Logger.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation


extension MQTT{
    
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
