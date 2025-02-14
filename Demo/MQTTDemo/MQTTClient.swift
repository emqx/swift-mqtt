//
//  MQTTClient.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import MQTT
import Foundation
import Photos

let client = MQTTClient()

class MQTTClient:MQTT.Client.V5{
    init() {
        super.init("swift-mqtt", endpoint: .quic(host: "172.16.2.7",tls: .trustAll()))
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
    }
}
extension MQTTClient:MQTTDelegate{
    func mqtt(_ mqtt: MQTT.Client, didUpdate status: MQTT.Status, prev: MQTT.Status) {
        
    }
    func mqtt(_ mqtt: MQTT.Client, didReceive error: any Error) {
        
    }
    func mqtt(_ mqtt: MQTT.Client, didReceive message: MQTT.Message) {
        
    }
}
