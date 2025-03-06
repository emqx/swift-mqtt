//
//  Client.swift
//  swift-mqtt
//
//  Created by supertext on 2025/1/15.
//
import Foundation

public protocol MQTTDelegate:AnyObject,Sendable{
    func mqtt(_ mqtt: MQTT.Client, didUpdate status:MQTT.Status, prev :MQTT.Status)
    func mqtt(_ mqtt: MQTT.Client, didReceive message:MQTT.Message)
    func mqtt(_ mqtt: MQTT.Client, didReceive error:Error)
}

public extension Notification{
    /// Parse mqtt message from `Notification` conveniently
    func mqttMesaage()->(client:MQTT.Client,message:MQTT.Message)?{
        guard let client = self.object as? MQTT.Client else{
            return nil
        }
        guard let message = self.userInfo?["message"] as? MQTT.Message else{
            return nil
        }
        return (client,message)
    }
    /// Parse mqtt status from `Notification` conveniently
    func mqttStatus()->(client:MQTT.Client,new:MQTT.Status,old:MQTT.Status)?{
        guard let client = self.object as? MQTT.Client else{
            return nil
        }
        guard let new = self.userInfo?["new"] as? MQTT.Status else{
            return nil
        }
        guard let old = self.userInfo?["old"] as? MQTT.Status else{
            return nil
        }
        return (client,new,old)
    }
    /// Parse mqtt error from `Notification` conveniently
    func mqttError()->(client:MQTT.Client,error:Error)?{
        guard let client = self.object as? MQTT.Client else{
            return nil
        }
        guard let error = self.userInfo?["error"] as? Error else{
            return nil
        }
        return (client,error)
    }
}
extension MQTT{
    public enum ObserverType:String{
        case error = "swift.mqtt.received.error"
        case status = "swift.mqtt.status.changed"
        case message = "swift.mqtt.received.message"
        var notifyName:Notification.Name{ .init(rawValue: rawValue) }
    }
}

/// Auth workflow
public typealias Authflow = (@Sendable (Auth) -> Promise<Auth>)

extension MQTT{
    ///Contains common logic for both v3 and v5 clients
    open class Client: @unchecked Sendable{
        private let notify = NotificationCenter()
        private let socket:Socket
        @Safely private var packetId: UInt16 = 0
        /// readonly confg
        public var config:Config { socket.config }
        /// readonly mqtt client connection status
        public var status:Status { socket.status }
        /// mqtt client version
        public var version:Version { socket.config.version }
        /// readonly
        public var isOpened:Bool { socket.status == .opened }
        /// network endpoint
        public var endpoint:MQTT.Endpoint { socket.endpoint }
        /// The delegate and observers callback queue
        public var delegateQueue:DispatchQueue = .main
        /// mqtt delegate
        public weak var delegate:MQTTDelegate?{
            didSet{
                guard let delegate else{
                    socket.onMessage = nil
                    socket.onStatus = nil
                    socket.onError = nil
                    return
                }
                socket.onMessage = {[weak self] msg in
                    if let self{
                        self.delegateQueue.async {
                            delegate.mqtt(self, didReceive: msg)
                            let info = ["message":msg]
                            self.notify.post(name: ObserverType.message.notifyName, object: self, userInfo: info)
                        }
                    }
                }
                socket.onStatus = {[weak self]  new,old in
                    if let self{
                        self.delegateQueue.async {
                            delegate.mqtt(self, didUpdate: new, prev: old)
                            let info:[String:Status] = ["old":old,"new":new]
                            self.notify.post(name: ObserverType.status.notifyName, object: self, userInfo: info)
                        }
                    }
                }
                socket.onError = {[weak self] err in
                    if let self{
                        self.delegateQueue.async {
                            delegate.mqtt(self, didReceive: err)
                            let info:[String:Error] = ["error":err]
                            self.notify.post(name: ObserverType.error.notifyName, object: self, userInfo:info)
                        }
                    }
                }
            }
        }
        
        /// Initial mqtt  client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        ///   - version: The mqtt client version
        init(_ clientId: String, endpoint:Endpoint,version:MQTT.Version) {
            socket = Socket(clientId, endpoint: endpoint,version: version)
        }
        /// Start the auto reconnect mechanism
        ///
        /// - Parameters:
        ///    - policy: Retry policcy
        ///    - limits: max retry times
        ///    - filter: filter retry when some reason,  return `true` if retrying are not required
        ///
        public func startRetrier(_ policy:Retrier.Policy = .exponential(),limits:UInt = 10,filter:Retrier.Filter? = nil){
            socket.startRetrier(Retrier(policy, limits: limits, filter: filter))
        }
        ///  Stop the auto reconnect mechanism
        public func stopRetrier(){
            socket.stopRetrier()
        }
        /// Enable the network mornitor mechanism
        ///
        public func startMonitor(){
            socket.setMonitor(true)
        }
        /// Disable the network mornitor mechanism
        ///
        public func stopMonitor(){
            socket.setMonitor(false)
        }
        /// Add observer for some type
        /// - Parameters:
        ///    - target:the observer target
        ///    - type: observer type
        ///    - selector: callback selector
        /// - Important:Note that this operation will strongly references `target`
        public func addObserver(_ target:AnyObject,of type:ObserverType,selector:Selector){
            notify.addObserver(target, selector: selector, name: type.notifyName, object: self)
        }
        /// Remove some observer of target
        /// - Important:References must be removed when not in use
        public func removeObserver(_ target:Any,of type:ObserverType){
            notify.removeObserver(target, name: type.notifyName, object: self)
        }
        /// Remove all observer of target
        /// - Important:References must be removed when not in use
        public func removeObserver(_ target:Any){
            let all:[ObserverType] = [.error,.status,.message]
            all.forEach {
                self.notify.removeObserver(target, name: $0.notifyName, object: self)
            }
        }
        private func nextPacketId() -> UInt16 {
            return $packetId.write { id in
                if id == UInt16.max {  id = 0 }
                id += 1
                return id
            }
        }
    }
}

extension MQTT.Client{
    open class V3:MQTT.Client, @unchecked Sendable{
        /// Initial v3 client object
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
        self.socket.close(code,properties: [])
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
    /// - Returns: `Promise<Bool>` to be updated with whether server holds a session for this client
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
        var properties = Properties()
        if self.config.version == .v5_0, cleanStart == false {
            properties.append(.sessionExpiryInterval(0xFFFF_FFFF))
        }
        let packet = ConnectPacket(
            cleanSession: cleanStart,
            keepAlive: config.keepAlive,
            clientId: config.clientId,
            username: config.username,
            password: config.password,
            properties: properties,
            will: message
        )
        return self.socket.open(packet).then(\.sessionPresent)
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
    public func publish(
        to topic: String,
        payload: Data,
        qos: MQTTQoS  = .atLeastOnce,
        retain: Bool = false
    ) -> Promise<Void> {
        let message = MQTT.Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: [])
        let packet = PublishPacket(id: nextPacketId(), message: message)
        return self.socket.publish(packet: packet).then { _ in }
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
    public func publish(to topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, retain:Bool = false)->Promise<Void>{
        let data = payload.data(using: .utf8) ?? Data()
        return self.publish(to:topic, payload: data,qos: qos,retain: retain)
    }
    /// Subscribe to topic
    /// - Parameter topic: Subscription infos
    /// - Returns: `Promise<Suback>` waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    public func subscribe(to topic: String,qos:MQTTQoS = .atLeastOnce) -> Promise<Suback> {
        return self.subscribe(to: [.init(topicFilter: topic, qos: qos)])
    }
    
    /// Subscribe to topic
    /// - Parameter subscriptions: Subscription infos
    /// - Returns: `Promise<Suback>` waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    public func subscribe(to subscriptions: [Subscribe]) -> Promise<Suback> {
        let subscriptions: [Subscribe.V5] = subscriptions.map { .init(topicFilter: $0.topicFilter, qos: $0.qos) }
        let packet = SubscribePacket(id: nextPacketId(), properties: [],subscriptions: subscriptions)
        return self.socket.subscribe(packet: packet).then { try $0.suback() }
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: `Promise<Void>` waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
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
        let packet = UnsubscribePacket(id: nextPacketId(),subscriptions: subscriptions, properties: [])
        return self.socket.unsubscribe(packet: packet).then { _ in }
    }
}


extension MQTT.Client{
    open class V5:MQTT.Client, @unchecked Sendable{
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
    /// - Returns: `Promise<Puback?>` waiting for publish to complete.
    /// Depending on `QoS` setting the promise will complete  after message is sent, when `PUBACK` is received or when `PUBREC` and following `PUBCOMP` are received.
    /// `QoS0` retrun nil. `QoS1` and above return an `Puback` which contains a `code` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = [])->Promise<Puback?>{
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
    /// - Returns: `Promise<Puback?>` waiting for publish to complete.
    /// Depending on `QoS` setting the promise will complete  after message is sent, when `PUBACK` is received or when `PUBREC` and following `PUBCOMP` are received.
    /// `QoS0` retrun nil. `QoS1` and above return an `Puback` which contains a `code` and `properties`
    @discardableResult
    public func publish(to topic:String,payload:Data,qos:MQTTQoS = .atLeastOnce, retain:Bool = false,properties:Properties = []) ->Promise<Puback?> {
        let message = MQTT.Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: properties)
        return socket.publish(packet: PublishPacket(id: nextPacketId(), message: message))
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
        return self.subscribe(to: [Subscribe.V5(topicFilter: topic, qos: qos)], properties: properties)
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
    public func subscribe(to subscriptions:[Subscribe.V5],properties:Properties = [])->Promise<Suback>{
        let packet = SubscribePacket(id: nextPacketId(), properties: properties, subscriptions: subscriptions)
        return self.socket.subscribe(packet: packet).then { try $0.suback() }
    }
    
    /// Unsubscribe from topic
    /// - Parameters:
    ///   - topic: Topic to unsubscribe from
    ///   - properties: properties to attach to unsubscribe message
    /// - Returns: `Promise<Unsuback>` waiting for unsubscribe to complete. Will wait for `UNSUBACK` message from server and
    ///     return its contents
    @discardableResult
    public func unsubscribe(from topic:String,properties:Properties = []) -> Promise<Unsuback> {
        return self.unsubscribe(from:[topic], properties: properties)
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
        return self.socket.unsubscribe(packet: packet).then { try $0.unsuback() }
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
            keepAlive: config.keepAlive,
            clientId: config.clientId,
            username: config.username,
            password: config.password,
            properties: properties,
            will: publish
        )
        return socket.open(packet, authflow: authflow).then{ $0.ack() }
    }
    /// Close from server
    /// - Parameters:
    ///   - code: The close reason code send to the server
    ///   - properties: The close properties send to the server
    /// - Returns: `Promise<Void>` waiting on disconnect message to be sent
    ///
    @discardableResult
    public func close(_ code:ResultCode.Disconnect = .normal ,properties:Properties = [])->Promise<Void>{
        socket.close(code,properties: properties)
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
        socket.auth(properties: properties, authflow: authflow)
    }
}
