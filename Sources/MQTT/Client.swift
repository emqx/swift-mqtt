//
//  Client.swift
//  swift-mqtt
//
//  Created by supertext on 2025/1/15.
//
import Foundation

public protocol MQTTDelegate:AnyObject{
    func mqtt(_ mqtt: MQTT.Client, didUpdate status:MQTT.Status, prev :MQTT.Status)
    func mqtt(_ mqtt: MQTT.Client, didReceive message:MQTT.Message)
    func mqtt(_ mqtt: MQTT.Client, didReceive error:Error)
}

extension MQTT{
    open class Client{
        fileprivate let impl:CoreImpl
        /// readonly confg
        public var config:Config { impl.config }
        /// readonly status
        public var status:Status { impl.socket.status }
        /// the readonly retrier if using
        public var retrier: MQTT.Retrier? { impl.socket.retrier }
        /// readonly
        public var isOpened:Bool { impl.socket.status == .opened }
        /// network endpoint
        public var endpoint:MQTT.Endpoint { impl.socket.endpoint }
        /// mqtt delegate
        public weak var delegate:MQTTDelegate?{
            didSet{
                if let delegate {
                    self.impl.socket.onMessage = {[weak self] msg in
                        if let self{
                            delegate.mqtt(self, didReceive: msg)
                        }
                    }
                    self.impl.socket.onStatus = {[weak self]  new,old in
                        if let self{
                            delegate.mqtt(self, didUpdate: new, prev: old)
                        }
                    }
                    self.impl.socket.onError = {[weak self] err in
                        if let self{
                            delegate.mqtt(self, didReceive: err)
                        }
                    }
                }else{
                    self.impl.socket.onMessage = nil
                    self.impl.socket.onStatus = nil
                    self.impl.socket.onError = nil
                }
            }
        }
        
        /// Initial v5 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        ///   - version: The mqtt client version
        init(_ clientId: String, endpoint:Endpoint,version:MQTT.Version) {
            self.impl = CoreImpl(clientId, endpoint: endpoint,version: version)
        }
        /// Enale the autto reconnect mechanism
        ///
        /// - Parameters:
        ///    - policy: Retry policcy
        ///    - limits: max retry times
        ///    - filter: filter retry when some reason,  return `true` if retrying are not required
        ///
        public func startRetrier(_ policy:Retrier.Policy = .exponential(),limits:UInt = 10,filter:Retrier.Filter? = nil){
            self.impl.socket.retrier = Retrier(policy, limits: limits, filter: filter)
        }
        ///  Stop the auto reconnect mechanism
        public func stopRetrier(){
            self.impl.socket.retrier = nil
        }
        /// Enable the network mornitor mechanism
        ///
        public func startMonitor(){
            self.impl.socket.startMonitor(true)
        }
        /// Disable the network mornitor mechanism
        ///
        public func stopMonitor(){
            self.impl.socket.startMonitor(false)
        }
    }
}

extension MQTT.Client{
    open class V3:MQTT.Client{
        /// Initial v5 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        public init(_ clientId: String, endpoint:MQTT.Endpoint) {
            super.init(clientId, endpoint: endpoint, version: .v3_1_1)
        }
    }
}

extension MQTT.Client.V3{
    /// Close from server
    /// - Parameters:
    ///   - code: close reason code send to the server
    /// - Returns: `Promise` waiting on disconnect message to be sent
    @discardableResult
    public func close(_ code:ResultCode.Disconnect = .normal)->Promise<Void>{
        self.impl.close(code,properties: [])
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
    public func open( will: (topic: String, payload: Data, qos: MQTTQoS, retain: Bool)? = nil, cleanStart: Bool = true ) -> Promise<Bool> {
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


extension MQTT.Client{
    open class V5:MQTT.Client{
        /// Initial v5 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        public init(_ clientId: String, endpoint:MQTT.Endpoint) {
            super.init(clientId, endpoint: endpoint, version: .v5_0)
        }
    }
}
extension MQTT.Client.V5{
    /// Publish message to topic
    ///
    /// - Parameters:
    ///    - topic: Topic name on which the message is published
    ///    - payload: Message payload
    ///    - qos: Quality of Service for message.
    ///    - retain: Whether this is a retained message.
    ///    - properties: properties to attach to publish message
    ///
    /// - Returns: `Promise<AckV5?>` waiting for publish to complete. Depending on `QoS` setting the future will complete
    ///     when message is sent, when `PUBACK` is received or when `PUBREC` and following `PUBCOMP` are
    ///     received. `QoS1` and above return an `AckV5` which contains a `reason` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = [])->Promise<PubackV5?>{
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
    /// - Returns: `Promise<AckV5?>` waiting for publish to complete. Depending on `QoS` setting the future will complete
    ///     when message is sent, when `PUBACK` is received or when `PUBREC` and following `PUBCOMP` are
    ///     received. `QoS1` and above return an `AckV5` which contains a `reason` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:Data,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = []) ->Promise<PubackV5?> {
        let message = MQTT.Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: properties)
        return impl.publish(packet: PublishPacket(id: impl.nextPacketId(), message: message))
    }
    
    /// Subscribe to topic
    ///
    /// - Parameters:
    ///    - topic: Subscription topic
    ///    - properties: properties to attach to subscribe message
    ///
    /// - Returns: `Promise` waiting for subscribe to complete. Will wait for `SUBACK` message from server and
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
    /// - Returns: `Promise` waiting for subscribe to complete. Will wait for `SUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func subscribe(to subscriptions:[Subscribe.V5],properties:Properties = [])->Promise<Suback.V5>{
        let packet = SubscribePacket(id: impl.nextPacketId(), subscriptions: subscriptions, properties: properties)
        return impl.subscribe(packet: packet).then { suback in
            return Suback.V5(reasons: suback.reasons,properties: properties)
        }
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topic: Topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: `Promise` waiting for unsubscribe to complete. Will wait for `UNSUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topic:String,properties:Properties = []) -> Promise<Suback.V5> {
        return self.unsubscribe(from:[topic], properties: properties)
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topics: List of topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: `Promise` waiting for unsubscribe to complete. Will wait for `UNSUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topics:[String],properties:Properties = []) -> Promise<Suback.V5> {
        let packet = UnsubscribePacket(id: impl.nextPacketId(), subscriptions: topics, properties: properties)
        return impl.unsubscribe(packet: packet).then { suback in
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
    /// - Returns: `Promise` to be updated with connack
    ///
    @discardableResult
    public func open(
        will: (topic: String, payload: Data, qos: MQTTQoS, retain: Bool, properties: Properties)? = nil,
        cleanStart: Bool = true,
        properties: Properties = [],
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

        return self.impl.open(packet, authflow: authflow).then {
            .init(
                sessionPresent: $0.sessionPresent,
                reason: ResultCode.ConnectV5(rawValue: $0.returnCode) ?? .unrecognisedReason,
                properties: $0.properties.connack()
            )
        }
    }
    /// Close from server
    /// - Parameters:
    ///   - code: The close reason code send to the server
    ///   - properties: The close properties send to the server
    /// - Returns: `Promise` waiting on disconnect message to be sent
    ///
    @discardableResult
    public func close(_ code:ResultCode.Disconnect = .normal ,properties:Properties = [])->Promise<Void>{
        self.impl.close(code,properties: properties)
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
        self.impl.auth(properties: properties, authflow: authflow)
    }
}
