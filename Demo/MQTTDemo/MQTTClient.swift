//
//  MQTTClient.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import MQTTNIO
import MQTT
import CocoaMQTT
import Foundation
import Network

let client = MQTTClient()
//let mqtt = {
//    let m = CocoaMQTT5(clientID: "swift-mqtt", host: "broker.beta.jagat.io", port: 1883)
//    m.connectProperties = MqttConnectProperties()
//    m.connectProperties?.topicAliasMaximum = 0
//    m.username = "jagat-mqtt-pwd-im"
//    m.password = "jagat-mqtt-pwd-im"
//    m.cleanSession = true
//    m.logLevel = .debug
//    m.delegate = client
//    return m
//}()
let mqtt = {
    let params = NWParameters.tls
    let endpoint = NWEndpoint.hostPort(host: "broker.beta.jagat.io", port: 1883)
    let m = MQTT("swift-mqtt", endpoint: endpoint, params: .tcp)
    m.connectProperties = .init()
    m.connectProperties?.topicAliasMaximum = 0
    m.username = "jagat-mqtt-pwd-im"
    m.password = "jagat-mqtt-pwd-im"
    m.cleanSession = true
    m.delegate = client
    m.usingMonitor()
    m.usingPinging()
    m.usingRetrier()
    MQTT.logLevel = .debug
    return m
}()
//let mqtt = {
//    let params = NWParameters.tls
//    let endpoint = NWEndpoint.hostPort(host: "broker.beta.jagat.io", port: 1883)
//    let m = MQTTNIO.MQTTClient(host: "broker.beta.jagat.io", port: 1883, identifier: "swift-mqtt", eventLoopGroupProvider: .createNew, logger: .init(label: "MQTT"),configuration: .init(version: .v5_0,userName: "jagat-mqtt-pwd-im",password: "jagat-mqtt-pwd-im"))
//    return m
//}()
extension MQTTNIO.MQTTClient{
    func open(){
        _ = self.connect(cleanSession: true,will: nil)
    }
    func close(){
        _ = self.disconnect()
    }
    func publish(_ topic:String,payload:String){
        _ = self.publish(to: topic, payload: .init(string: payload), qos: .atLeastOnce)
    }
    func subscribe(_ topic:String){
        _ = self.subscribe(to: [.init(topicFilter: topic, qos: .atLeastOnce)])
    }
    func unsubscribe(_ topic:String){
        _ = self.unsubscribe(from: [topic])
    }
}
extension MQTT{  }
extension CocoaMQTT5{
    func open(){
       _ = self.connect()
    }
    func close(){
        self.disconnect()
    }
}
class MQTTClient{

}
extension MQTTClient:CocoaMQTT5Delegate{
    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {
        
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {
        
    }
    
    func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {
        
    }
    
    func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {
        
    }
    
    func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: (any Error)?) {
        
    }
}
extension MQTTClient:MQTTDelegate{
    ///
    func mqtt(_ mqtt: MQTT, didUpdate status:MQTT.Status,prev:MQTT.Status){

    }
    ///
    func mqtt(_ mqtt: MQTT, didConnectAck ack: ConnAckReasonCode, connAckData: DecodeConnAck?){
        MQTT.Logger.debug("didConnectAck ack \(ack)")
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishMessage message: MQTT.Message, id: UInt16){
        MQTT.Logger.debug("didPublishMessage message \(message)")
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishAck id: UInt16, pubAckData: DecodePubAck?){
        MQTT.Logger.debug("didPublishAck id \(id)")
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishRec id: UInt16, pubRecData: DecodePubRec?){
        MQTT.Logger.debug("didPublishRec id \(id)")
    }

    ///
    func mqtt(_ mqtt: MQTT, didReceiveMessage message: MQTT.Message, id: UInt16, publishData: DecodePublish?){
        MQTT.Logger.debug("didReceiveMessage message \(message)")
    }

    ///
    func mqtt(_ mqtt: MQTT, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: DecodeSubAck?){
        MQTT.Logger.debug("didSubscribeTopics success \(success), failed \(failed)")
    }

    ///
    func mqtt(_ mqtt: MQTT, didUnsubscribeTopics topics: [String], unsubAckData: DecodeUnsubAck?){
        
    }
    
    ///
    func mqtt(_ mqtt: MQTT, didReceiveDisconnectReasonCode reasonCode: MQTT.CloseCode){
        
    }
    
    ///
    func mqtt(_ mqtt: MQTT, didReceiveAuthReasonCode reasonCode: AuthReasonCode){
        
    }
    
    ///
    /// socket did recevied error.
    /// Most of the time you don't have to care about this, because it's already taken care of internally
    func mqtt(_ mqtt:MQTT, didReceive error:Error){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishComplete id: UInt16,  pubCompData: DecodePubComp?){
        
    }
    ///
    func mqttDidPing(_ mqtt: MQTT){
        
    }

    ///
    func mqttDidReceivePong(_ mqtt: MQTT){
        
    }
}
