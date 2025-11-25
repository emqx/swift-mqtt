//
//  Client.v3.swift
//  swift-mqtt
//
//  Created by supertext on 2025/1/15.
//
import Foundation


extension MQTTClient{
    open class V3:MQTTClient, @unchecked Sendable{
        /// Initial v3 client object
        ///
        /// - Parameters:
        ///   - endpoint:The network endpoint
        public init(_ endpoint:Endpoint) {
            super.init(endpoint, version: .v3_1_1)
        }
    }
}

extension MQTTClient.V3{
    /// Close from server
    /// - Parameters:
    ///   - code: close reason code send to the server
    /// - Returns: `Promise` waiting on disconnect message to be sent
    @discardableResult
    @preconcurrency
    final public func close(_ code:ResultCode.Disconnect = .normal)->Promise<Void>{
        self._close(code,properties: [])
    }
    /// Connect to MQTT server
    ///
    /// If `cleanStart` is set to false the Server MUST resume communications with the Client based on
    /// state from the current Session (as identified by the Client identifier). If there is no Session
    /// associated with the Client identifier the Server MUST create a new Session. The Client and Server
    /// MUST store the Session after the Client and Server are disconnected. If set to true then the Client
    /// and Server MUST discard any previous Session and start a new one
    ///
    /// - Parameters:
    ///   - identity: The user identity to be pack into the `CONNECT` Packet
    ///   - will: Publish message to be posted as soon as connection is made
    ///   - cleanStart: should we start with a new session
    /// - Returns: `Promise<Bool>` to be updated with whether server holds a session for this client
    ///
    @discardableResult
    @preconcurrency
    final public func open(_ identity:Identity,will: (topic: String, payload: Data, retain: Bool)? = nil, cleanStart: Bool = true ) -> Promise<Bool> {
        let message = will.map {
            Message(
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
            keepAlive: config.keepAlive,
            clientId: identity.clientId,
            username: identity.username,
            password: identity.password,
            properties: [],
            will: message
        )
        self.identity = identity
        return self.open(packet).then(\.sessionPresent)
    }

    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///
    /// - Returns: `Promise<Void>` waiting for publish to complete.
    ///
    @discardableResult
    @preconcurrency
    final public func publish(
        to topic: String,
        payload: Data,
        qos: MQTTQoS  = .atLeastOnce,
        retain: Bool = false
    ) -> Promise<Void> {
        let message = Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: [])
        let packet = PublishPacket(id: nextPacketId(), message: message)
        return self.publish(packet: packet).then { _ in }
    }
    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///
    /// - Returns: `Promise<Void>` waiting for publish to complete.
    ///
    @discardableResult
    @preconcurrency
    final public func publish(to topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, retain:Bool = false)->Promise<Void>{
        let data = payload.data(using: .utf8) ?? Data()
        return publish(to:topic, payload: data,qos: qos,retain: retain)
    }
    /// Subscribe to topic
    /// - Parameter topic: Subscription infos
    /// - Returns: `Promise<Suback>` waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    @preconcurrency
    final public func subscribe(to topic: String,qos:MQTTQoS = .atLeastOnce) -> Promise<Suback> {
        let packet = SubscribePacket(id: nextPacketId(), properties: [],subscriptions: [.init(topic, qos: qos)])
        return self.subscribe(packet: packet).then { $0.suback() }
    }
    /// Subscribe to topic
    /// - Parameter subscriptions: Subscription infoszw
    /// - Returns: `Promise<Suback>` waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    @preconcurrency
    final public func subscribe(to subscriptions: [Subscribe.V3]) -> Promise<Suback> {
        let subscriptions: [Subscribe] = subscriptions.map { .init($0.topic, qos: $0.qos) }
        let packet = SubscribePacket(id: nextPacketId(), properties: [],subscriptions: subscriptions)
        return self.subscribe(packet: packet).then { $0.suback() }
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: `Promise<Void>` waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
    ///
    @discardableResult
    @preconcurrency
    final public func unsubscribe(from topic: String) -> Promise<Void> {
        return unsubscribe(from: [topic])
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: `Promise` waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
    ///
    @discardableResult
    @preconcurrency
    final public func unsubscribe(from subscriptions: [String]) -> Promise<Void> {
        let packet = UnsubscribePacket(id: nextPacketId(),subscriptions: subscriptions, properties: [])
        return self.unsubscribe(packet: packet).then { _ in }
    }
}
