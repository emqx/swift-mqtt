//
//  MQTTClient.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import MQTT
import Foundation

let client = MQTTClient()

class Observer{
    @objc func statusChanged(_ notify:Notification){
        guard let info = notify.mqttStatus() else{
            return
        }
        print("from:",info.old," to:",info.new)
    }
    @objc func recivedMessage(_ notify:Notification){
        guard let info = notify.mqttMesaage() else{
            return
        }
        let str = String(data: info.message.payload, encoding: .utf8) ?? ""
        print(str)
    }
    @objc func recivedError(_ notify:Notification){
        guard let info = notify.mqttError() else{
            return
        }
        print(info.error)
    }
}
class MQTTClient:MQTT.Client.V5,@unchecked Sendable{
    let observer = Observer()
    init() {
        let clientID = UUID().uuidString
        super.init(clientID, endpoint: .quic(host: "172.16.2.7",tls: .trustAll()))
        MQTT.Logger.level = .debug
        self.config.keepAlive = 60
        self.config.username = "test"
        self.config.password = "test"
        self.config.pingEnabled = true
        
        /// start network monitor
        self.startMonitor()
        /// start auto reconnecting
        self.startRetrier{reason in
            switch reason{
            case .serverClosed(let code, _):
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
        self.addObserver(observer, of: .status, selector: #selector(Observer.statusChanged(_:)))
        self.addObserver(observer, of: .message, selector: #selector(Observer.recivedMessage(_:)))
        self.addObserver(observer, of: .error, selector: #selector(Observer.recivedError(_:)))
    }
    
}
extension MQTTClient:MQTTDelegate{
    func mqtt(_ mqtt: MQTT.Client, didUpdate status: MQTT.Status, prev: MQTT.Status) {
        print("status:",status)
    }
    func mqtt(_ mqtt: MQTT.Client, didReceive error: any Error) {
        print("Error:",error)
    }
    func mqtt(_ mqtt: MQTT.Client, didReceive message: MQTT.Message) {
        print("message:",message)
    }
}
