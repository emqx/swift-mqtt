//
//  ClientV3.swift
//  swift-mqtt
//
//  Created by supertext on 2025/1/15.
//
import Promise
import Network
import Foundation
public protocol MQTT3Delegate:AnyObject{
    func mqtt(_ mqtt: MQTT.ClientV3, didUpdate status:MQTT.Status,prev:MQTT.Status)
    func mqtt(_ mqtt: MQTT.ClientV3, didReceive error:MQTT.Message)
    func mqtt(_ mqtt: MQTT.ClientV3, didReceive error:Error)
}
extension MQTT{
    open class ClientV3{
        private let impl:CoreImpl
        /// readonly confg
        public var config:Config { self.impl.config }
        /// readonly status
        public var status:Status { self.impl.status }
        /// readonly
        public var isOpened:Bool { self.impl.status == .opened }
        public weak var delegate:MQTT3Delegate?{
            didSet{
                guard let delegate else {
                    return
                }
                self.impl.socket.onMessage = {msg in
                    delegate.mqtt(self, didReceive: msg)
                }
                self.impl.socket.onError = {err in
                    delegate.mqtt(self, didReceive: err)
                }
                self.impl.socket.onStatus = { new,old in
                    delegate.mqtt(self, didUpdate: new, prev: old)
                }
            }
        }
        /// Initial v5 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        public init(_ clientId: String, endpoint:Endpoint) {
            self.impl = CoreImpl(clientId, endpoint: endpoint,version: .v3_1_1)
        }
        /// Enabling the retry mechanism
        ///
        /// - Parameters:
        ///    - policy: Retry policcy
        ///    - limits: max retry times
        ///    - filter: filter retry when some code and reason
        ///
        public func usingRetrier(_ policy:Retrier.Policy = .exponential(),limits:UInt = 10,filter:Retrier.Filter? = nil){
            self.impl.usingRetrier(policy,limits: limits,filter: filter)
        }
        /// Enabling the network mornitor mechanism
        ///
        /// - Parameters:
        ///    - enable: use monitor or not.
        ///
        public func usingMonitor(_ enable:Bool = true){
            self.impl.usingMonitor(enable)
        }
    }
}

extension MQTT.ClientV3{
    /// Close from server
    /// - Parameters:
    ///   - reason: close reason code send to the server
    /// - Returns: `Promise` waiting on disconnect message to be sent
    @discardableResult
    public func close(_ reason:MQTT.CloseReason = .normalClose)->Promise<Void>{
        self.impl.close(reason)
    }
    /// Connect to MQTT server
    ///
    /// If `cleanStart` is set to false the Server MUST resume communications with the Client based on
    /// state from the current Session (as identified by the Client identifier). If there is no Session
    /// associated with the Client identifier the Server MUST create a new Session. The Client and Server
    /// MUST store the Session after the Client and Server are disconnected. If set to true then the Client
    /// and Server MUST discard any previous Session and start a new one
    ///
    /// The function returns an EventLoopFuture which will be updated with whether the server has restored a session for this client.
    ///
    /// - Parameters:
    ///   - will: Publish message to be posted as soon as connection is made
    ///   - cleanStart: should we start with a new session
    /// - Returns: `Promise` to be updated with whether server holds a session for this client
    ///
    @discardableResult
    public func open(
        will: (topic: String, payload: Data, qos: MQTTQoS, retain: Bool)? = nil,
        cleanStart: Bool = true
    ) -> Promise<Bool> {
        
        let message = will.map {
            MQTT.Message(
                qos: .atMostOnce,
                dup: false,
                topic: $0.topic,
                retain: $0.retain,
                payload: $0.payload,
                properties: []
            )
        }
        let packet = ConnectPacket(
            cleanSession: cleanStart,
            keepAliveSeconds: config.keepAlive,
            clientId: config.clientId,
            username: config.username,
            password: config.password,
            properties: [],
            will: message
        )
        var properties = Properties()
        if self.config.version == .v5_0, cleanStart == false {
            properties.append(.sessionExpiryInterval(0xFFFF_FFFF))
        }
        return self.impl.open(packet).then(\.sessionPresent)
    }

    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///
    /// - Returns: `Promise` waiting for publish to complete. Depending on QoS setting the future will complete
    ///     when message is sent, when PUBACK is received or when PUBREC and following PUBCOMP are
    ///     received
    ///
    @discardableResult
    public func publish(
        to topic: String,
        payload: Data,
        qos: MQTTQoS  = .atLeastOnce,
        retain: Bool = false
    ) -> Promise<Void> {
        let message = MQTT.Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: [])
        let packet = PublishPacket(id: impl.nextPacketId(), message: message)
        return self.impl.publish(packet: packet).then { _ in }
    }
    /// Subscribe to topic
    /// - Parameter topic: Subscription infos
    /// - Returns: `Promise` waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    public func subscribe(to topic: String,qos:MQTTQoS = .atLeastOnce) -> Promise<Suback> {
        return self.subscribe(to: [.init(topicFilter: topic, qos: qos)])
    }
    
    /// Subscribe to topic
    /// - Parameter subscriptions: Subscription infos
    /// - Returns: `Promise` waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    public func subscribe(to subscriptions: [Subscribe]) -> Promise<Suback> {
        let subscriptions: [Subscribe.V5] = subscriptions.map { .init(topicFilter: $0.topicFilter, qos: $0.qos) }
        let packet = SubscribePacket(id: impl.nextPacketId(), subscriptions: subscriptions, properties: [])
        return self.impl.subscribe(packet: packet)
            .then { message in
                let returnCodes = message.reasons.map { Suback.ReturnCode(rawValue: $0.rawValue) ?? .failure }
                return Suback(returnCodes: returnCodes)
            }
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: `Promise` waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
    ///
    @discardableResult
    public func unsubscribe(from topic: String) -> Promise<Void> {
        return self.unsubscribe(from: [topic])
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: `Promise` waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
    ///
    @discardableResult
    public func unsubscribe(from subscriptions: [String]) -> Promise<Void> {
        let packet = UnsubscribePacket(id: impl.nextPacketId(),subscriptions: subscriptions, properties: [])
        return self.impl.unsubscribe(packet: packet).then { _ in }
    }
}
