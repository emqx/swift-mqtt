//
//  Client.v5.swift
//  swift-mqtt
//
//  Created by supertext on 2025/4/14.
//

import Foundation

extension MQTTClient{
    open class V5:MQTTClient, @unchecked Sendable{
        /// Initial v5 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        public init(_ clientId: String, endpoint:Endpoint) {
            super.init(clientId, endpoint: endpoint, version: .v5_0)
        }
    }
}

extension MQTTClient.V5{
    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///    - properties: properties to attach to publish message
    ///
    /// - Returns: `Promise<Puback?>` waiting for publish to complete.
    /// Depending on `QoS` setting the promise will complete  after message is sent, when `PUBACK` is received or when `PUBREC` and following `PUBCOMP` are received.
    /// `QoS0` retrun nil. `QoS1` and above return an `Puback` which contains a `code` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = [])->Promise<Puback?>{
        let data = payload.data(using: .utf8) ?? Data()
        return publish(to:topic, payload: data,qos: qos,retain: retain,properties: properties)
    }
    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///    - properties: properties to attach to publish message
    ///
    /// - Returns: `Promise<Puback?>` waiting for publish to complete.
    /// Depending on `QoS` setting the promise will complete  after message is sent, when `PUBACK` is received or when `PUBREC` and following `PUBCOMP` are received.
    /// `QoS0` retrun nil. `QoS1` and above return an `Puback` which contains a `code` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:Data,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = []) ->Promise<Puback?> {
        let message = Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: properties)
        return self.publish(packet: PublishPacket(id: nextPacketId(), message: message))
    }
    /// Subscribe to topic
    ///
    /// - Parameters:
    ///    - topic: Subscription topic
    ///    - properties: properties to attach to subscribe message
    ///
    /// - Returns: `Promise<Suback>` waiting for subscribe to complete. Will wait for `SUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func subscribe(to topic:String,qos:MQTTQoS = .atLeastOnce,properties:Properties = [])->Promise<Suback>{
        return self.subscribe(to: [Subscribe(topic, qos: qos)], properties: properties)
    }
    /// Subscribe to topic
    ///
    /// - Parameters:
    ///    - subscriptions: Subscription infos
    ///    - properties: properties to attach to subscribe message
    ///
    /// - Returns: `Promise<Suback>` waiting for subscribe to complete. Will wait for `SUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func subscribe(to subscriptions:[Subscribe],properties:Properties = [])->Promise<Suback>{
        let packet = SubscribePacket(id: nextPacketId(), properties: properties, subscriptions: subscriptions)
        return self.subscribe(packet: packet).then { try $0.suback() }
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topic: Topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: `Promise<Unsuback>` waiting for unsubscribe to complete. Will wait for `UNSUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topic:String,properties:Properties = []) -> Promise<Unsuback> {
        return unsubscribe(from:[topic], properties: properties)
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topics: List of topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: `Promise<Unsuback>` waiting for unsubscribe to complete. Will wait for `UNSUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topics:[String],properties:Properties = []) -> Promise<Unsuback> {
        let packet = UnsubscribePacket(id: nextPacketId(), subscriptions: topics, properties: properties)
        return self.unsubscribe(packet: packet).then { try $0.unsuback() }
    }


    /// Connect to MQTT server
    ///
    /// If `cleanStart` is set to false the Server MUST resume communications with the Client based on
    /// state from the current Session (as identified by the Client identifier). If there is no Session
    /// associated with the Client identifier the Server MUST create a new Session. The Client and Server
    /// MUST store the Session after the Client and Server are disconnected. If set to true then the
    /// Client and Server MUST discard any previous Session and start a new one
    ///
    /// The function returns an EventLoopFuture which will be updated with whether the server has restored a session for this client.
    ///
    /// - Parameters:
    ///   - will: Publish message to be posted as soon as connection is made
    ///   - cleanStart: should we start with a new session
    ///   - properties: properties to attach to connect message
    ///   - authflow: The authentication workflow. This is currently unimplemented.
    /// - Returns: `Promise<Connack>` to be updated with connack
    ///
    @discardableResult
    public func open(
        will: (topic: String, payload: Data, qos: MQTTQoS, retain: Bool, properties: Properties)? = nil,
        cleanStart: Bool = true,
        properties: Properties = [],
        authflow: Authflow? = nil
    ) -> Promise<Connack> {
        let publish = will.map {
            Message(
                qos: .atMostOnce,
                dup: false,
                topic: $0.topic,
                retain: $0.retain,
                payload: $0.payload,
                properties: $0.properties
            )
        }
        let packet = ConnectPacket(
            cleanSession: cleanStart,
            keepAlive: config.keepAlive,
            clientId: config.clientId,
            username: config.username,
            password: config.password,
            properties: properties,
            will: publish
        )
        return self.open(packet, authflow: authflow).then{ $0.ack() }
    }
    /// Close from server
    /// - Parameters:
    ///   - code: The close reason code send to the server
    ///   - properties: The close properties send to the server
    /// - Returns: `Promise<Void>` waiting on disconnect message to be sent
    ///
    @discardableResult
    public func close(_ code:ResultCode.Disconnect = .normal ,properties:Properties = [])->Promise<Void>{
        self._close(code,properties: properties)
    }
    /// Re-authenticate with server
    ///
    /// - Parameters:
    ///   - properties: properties to attach to auth packet. Must include `authenticationMethod`
    ///   - authflow: Respond to auth packets from server
    /// - Returns: `Promise<Auth>` final auth packet returned from server
    ///
    @discardableResult
    public func auth(_ properties: Properties, authflow: Authflow? = nil) -> Promise<Auth> {
        self.auth(properties: properties, authflow: authflow)
    }
}
