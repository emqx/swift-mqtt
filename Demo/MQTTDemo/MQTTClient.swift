//
//  MQTTClient.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import MQTT
import Foundation

enum Logger:Sendable{
    nonisolated(unsafe) public static var level:Level = .error
    private static func log(_ level: Level, message: String) {
        guard level.rawValue >= self.level.rawValue else { return }
        print("APP(\(level)): \(message)")
    }
    static func debug(_ message: String) {
        log(.debug, message: message)
    }
    static func info(_ message: String) {
        log(.info, message: message)
    }
    static func warning(_ message: String) {
        log(.warning, message: message)
    }
    static func error(_ message: String) {
        log(.error, message: message)
    }
    static func error(_ error: Error?){
        log(.error, message: error.debugDescription)
    }
}
extension Logger{
    enum Level: Int, Sendable {
        case debug = 0, info, warning, error, off
    }
}

let client = Client()

class Observer{
    @objc func statusChanged(_ notify:Notification){
        guard let info = notify.mqttStatus() else{
            return
        }
        Logger.info("observed: status: \(info.old)--> \(info.new)")
    }
    @objc func recivedMessage(_ notify:Notification){
        guard let info = notify.mqttMesaage() else{
            return
        }
        let str = String(data: info.message.payload, encoding: .utf8) ?? ""
        Logger.info("observed: message: \(str)")
    }
    @objc func recivedError(_ notify:Notification){
        guard let info = notify.mqttError() else{
            return
        }
        Logger.info("observed: error: \(info.error)")
    }
}
class Client:MQTTClient.V5,@unchecked Sendable{
    let observer = Observer()
    init() {
        super.init(UUID().uuidString, endpoint: .tcp(host: "broker.emqx.io"))
        MQTT.Logger.level = .debug
        self.config.keepAlive = 60
        self.config.pingTimeout = 5
        self.config.username = "test"
        self.config.password = "test"
        self.config.pingEnabled = true
        self.delegateQueue = .main
        /// start network monitor
        self.startMonitor()
        /// start auto reconnecting
        self.startRetrier{reason in
            switch reason{
            case .serverClose(let code):
                switch code{
                case .serverBusy,.connectionRateExceeded:// don't retry when server is busy
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }
        /// eg
        /// set simple delegate
        self.delegate = self
        /// eg.
        /// add multiple observer.
        /// Don't observe self. If necessary use delegate
        self.addObserver(observer, for: .status, selector: #selector(Observer.statusChanged(_:)))
        self.addObserver(observer, for: .message, selector: #selector(Observer.recivedMessage(_:)))
        self.addObserver(observer, for: .error, selector: #selector(Observer.recivedError(_:)))
    }
    
}
extension Client:MQTTDelegate{
    func mqtt(_ mqtt: MQTTClient, didUpdate status: Status, prev: Status) {
        Logger.info("delegate: status \(prev)--> \(status)")
    }
    func mqtt(_ mqtt: MQTTClient, didReceive error: any Error) {
        Logger.info("delegate: error \(error)")
    }
    func mqtt(_ mqtt: MQTTClient, didReceive message: Message) {
        let str = String(data: message.payload, encoding: .utf8) ?? ""
        Logger.info("delegate: message: \(str)")
    }
}
