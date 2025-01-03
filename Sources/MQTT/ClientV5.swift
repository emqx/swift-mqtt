//
//  ClientV5.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Promise
import Network
import Foundation

public protocol MQTT5Delegate:AnyObject{
    func mqtt(_ mqtt: MQTT.ClientV5, didUpdate status:MQTT.Status,prev:MQTT.Status)
    func mqtt(_ mqtt: MQTT.ClientV5, didReceive error:MQTT.Message)
    func mqtt(_ mqtt: MQTT.ClientV5, didReceive error:Error)
}

extension MQTT{
    public final class ClientV5 : @unchecked Sendable{
        private let client:Client
        public var config:Config { self.client.config }
        public var status:Status { self.client.status }
        public var isOpened:Bool { self.client.status == .opened }
        public weak var delegate:MQTT5Delegate?{
            didSet{
                guard let delegate else {
                    return
                }
                self.client.socket.onMessage = {msg in
                    delegate.mqtt(self, didReceive: msg)
                }
                self.client.socket.onError = {err in
                    delegate.mqtt(self, didReceive: err)
                }
                self.client.socket.onStatus = { new,old in
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
            self.client = Client(clientId, endpoint: endpoint)
            self.client.config.version = .v5_0
        }
        /// Enabling the retry mechanism
        ///
        /// - Parameters:
        ///    - policy: Retry policcy
        ///    - limits: max retry times
        ///    - filter: filter retry when some code and reason
        ///
        public func usingRetrier(_ policy:Retrier.Policy = .exponential(),limits:UInt = 10,filter:Retrier.Filter? = nil){
            self.client.usingRetrier(policy,limits: limits,filter: filter)
        }
        /// Enabling the network mornitor mechanism
        ///
        /// - Parameters:
        ///    - enable: use monitor or not.
        ///
        public func usingMonitor(_ enable:Bool = true){
            self.client.usingMonitor(enable)
        }
    }
}
extension MQTT.ClientV5{
    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///    - properties: properties to attach to publish message
    ///
    /// - Returns: Future waiting for publish to complete. Depending on QoS setting the future will complete
    ///     when message is sent, when PUBACK is received or when PUBREC and following PUBCOMP are
    ///     received. QoS1 and above return an `MQTTAckV5` which contains a `reason` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = [])->Promise<AckV5?>{
        let data = payload.data(using: .utf8) ?? Data()
        return self.publish(to:topic, payload: data,qos: qos,retain: retain,properties: properties)
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
    /// - Returns: Future waiting for publish to complete. Depending on QoS setting the future will complete
    ///     when message is sent, when PUBACK is received or when PUBREC and following PUBCOMP are
    ///     received. QoS1 and above return an `MQTTAckV5` which contains a `reason` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:Data,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = []) ->Promise<AckV5?> {
        let message = MQTT.Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: properties)
        let packet = PublishPacket(id: client.nextPacketId(),message: message)
        return client.publish(packet: packet)
    }
    
    /// Subscribe to topic
    ///
    /// - Parameters:
    ///    - topic: Subscription topic
    ///    - properties: properties to attach to subscribe message
    ///
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server and
    ///     return its contents
    @discardableResult
    public func subscribe(to topic:String,qos:MQTTQoS = .atLeastOnce,properties:Properties = [])->Promise<Suback.V5>{
        return self.subscribe(to: [Subscribe.V5(topicFilter: topic, qos: qos)], properties: properties)
    }
    /// Subscribe to topic
    ///
    /// - Parameters:
    ///    - subscriptions: Subscription infos
    ///    - properties: properties to attach to subscribe message
    ///
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server and
    ///     return its contents
    @discardableResult
    public func subscribe(to subscriptions:[Subscribe.V5],properties:Properties = [])->Promise<Suback.V5>{
        let packet = SubscribePacket(subscriptions: subscriptions, properties: properties, id: client.nextPacketId())
        return client.subscribe(packet: packet).then { suback in
            return Suback.V5(reasons: suback.reasons,properties: properties)
        }
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topic: Topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: Future waiting for unsubscribe to complete. Will wait for UNSUBACK message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topic:String,properties:Properties = []) -> Promise<Suback.V5> {
        return self.unsubscribe(from:[topic], properties: properties)
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topics: List of topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: Future waiting for unsubscribe to complete. Will wait for UNSUBACK message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topics:[String],properties:Properties = []) -> Promise<Suback.V5> {
        let packet = UnsubscribePacket(subscriptions: topics, properties: properties, id: client.nextPacketId())
        return client.unsubscribe(packet: packet).then { suback in
            return Suback.V5(reasons: suback.reasons,properties: properties)
        }
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
    ///   - cleanStart: should we start with a new session
    ///   - properties: properties to attach to connect message
    ///   - will: Publish message to be posted as soon as connection is made
    ///   - authflow: The authentication workflow. This is currently unimplemented.
    /// - Returns: EventLoopFuture to be updated with connack
    ///
    @discardableResult
    public func open(
        will: (topic: String, payload: Data, qos: MQTTQoS, retain: Bool, properties: Properties)? = nil,
        cleanStart: Bool = true,
        properties: Properties = .init(),
        authflow: (@Sendable (AuthV5) -> Promise<AuthV5>)? = nil
    ) -> Promise<ConnackV5> {
        
        let publish = will.map {
            MQTT.Message(
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
            keepAliveSeconds: config.keepAlive,
            clientId: config.clientId,
            username: config.username,
            password: config.password,
            properties: properties,
            will: publish
        )

        return self.client.open(packet, authflow: authflow).then {
            .init(
                sessionPresent: $0.sessionPresent,
                reason: ReasonCode(rawValue: $0.returnCode) ?? .unrecognisedReason,
                properties: $0.properties
            )
        }
    }
    /// Close from server
    /// - Parameters:
    ///   - reason: close reason code send to the server
    /// - Returns: Future waiting on disconnect message to be sent
    ///
    @discardableResult
    public func close(_ reason:MQTT.CloseReason = .normalClose)->Promise<Void>{
        self.client.close(reason)
    }
    /// Re-authenticate with server
    ///
    /// - Parameters:
    ///   - properties: properties to attach to auth packet. Must include `authenticationMethod`
    ///   - authflow: Respond to auth packets from server
    /// - Returns: final auth packet returned from server
    ///
    @discardableResult
    public func auth(
        properties: Properties,
        authflow: (@Sendable (AuthV5) -> Promise<AuthV5>)? = nil
    ) -> Promise<AuthV5> {
        let authPacket = AuthPacket(reason: .reAuthenticate, properties: properties)
        return self.client.reAuth(packet: authPacket)
            .then { packet -> Promise<AuthPacket> in
                if packet.reason == .success{
                    return .init(packet)
                }
                guard let authflow else {
                    throw MQError.authflowRequired
                }
                return self.client.processAuth(packet, authflow: authflow).then { apkg in
                    guard let auth = apkg as? AuthPacket else {
                        throw MQError.unexpectedMessage
                    }
                    return auth
                }
            }
            .then { pkg in
                return AuthV5(reason: pkg.reason, properties: pkg.properties)
            }
    }
}
