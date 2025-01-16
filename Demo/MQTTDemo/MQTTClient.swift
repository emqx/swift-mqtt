//
//  MQTTClient.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import MQTT
import Foundation

let client = MQTTClient()



class MQTTClient:MQTT.ClientV5{
    init() {
        super.init("swift-mqtt", endpoint: .quic(host: "172.16.2.7",tls: .trustAll()))
        self.config.keepAlive = 60
        self.config.username = "test"
        self.config.password = "test"
        self.usingMonitor()
        self.usingRetrier()
        MQTT.Logger.level = .debug
    }
}
extension MQTTClient:MQTT5Delegate{
    func mqtt(_ mqtt: MQTT.ClientV5, didUpdate status: MQTT.Status, prev: MQTT.Status) {
        
    }
    func mqtt(_ mqtt: MQTT.ClientV5, didReceive error: any Error) {
        
    }
    func mqtt(_ mqtt: MQTT.ClientV5, didReceive error: MQTT.Message) {
        
    }
}
