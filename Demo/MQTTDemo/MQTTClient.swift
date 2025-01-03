//
//  MQTTClient.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import MQTT
import Foundation

let client = MQTTClient()

let mqtt = {
    let m = MQTT.ClientV5("swift-mqtt", endpoint: .quic(host: "172.16.2.7",tls: .trustAll()))
    m.config.keepAlive = 60
    m.config.username = "test"
    m.config.password = "test"
    m.usingMonitor()
    m.usingRetrier()
    MQTT.Logger.level = .debug
    return m
}()


extension MQTT.Client{
    func publish(_ topic:String,payload:String){
        if let data = payload.data(using: .utf8){
            self.publish(to:topic, payload: data)
        }
    }
    func subscribe(_ topic:String){
        self.subscribe(to: topic)
    }
    func unsubscribe(_ topic:String){
        self.unsubscribe(from:topic)
    }
}
class MQTTClient{

}
