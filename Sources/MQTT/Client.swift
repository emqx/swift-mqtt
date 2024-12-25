//
//  Client.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/24.
//



import Foundation
import Network
import Promise

public protocol MQTTDelegate:AnyObject{
    func mqtt(_ mqtt: MQTT, didUpdate status:MQTT.Status,prev:MQTT.Status)
    func mqtt(_ mqtt: MQTT, didReceive error:Message)
    func mqtt(_ mqtt: MQTT, didReceive error:Error)

}
extension MQTT{
    public final class Client: @unchecked Sendable{
        private let socket:Socket
        private var inflight: Inflight = .init()
        private var connParams = ConnectParams()
        
        public let config:Config
        public var status:Status { self.socket.status }
        public var isOpened:Bool { self.socket.status == .opened }
        @Atomic
        private var packetId: UInt16 = 0
        /// Initial v3 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        ///   - params: The connection parameters `default` is `.tls`
        public init(_ clientId: String, endpoint:NWEndpoint,params:NWParameters = .tls) {
            self.config = Config(.v3_1_1,clientId:clientId)
            self.socket = Socket(self.config,endpoint: endpoint, params: params)
        }
    }
}
extension MQTT{
    /// connection parameters. Limits set by either client or server
    struct ConnectParams{
        var maxQoS: MQTTQoS = .exactlyOnce
        var maxPacketSize: Int?
        var retainAvailable: Bool = true
        var maxTopicAlias: UInt16 = 65535
    }
}
extension MQTT.Client{
    
    /// Enabling the retry mechanism
    ///
    /// - Parameters:
    ///    - policy: Retry policcy
    ///    - limits: max retry times
    ///    - filter: filter retry when some code and reason
    ///
    public func usingRetrier(
        _ policy:Retrier.Policy = .exponential(),
        limits:UInt = 10,
        filter:Retrier.Filter? = nil)
    {
        self.socket.retrier = Retrier(policy, limits: limits, filter: filter)
    }
    /// Enabling the network mornitor mechanism
    ///
    /// - Parameters:
    ///    - enable: use monitor or not.
    ///
    public func usingMonitor(_ enable:Bool = true){
        self.socket.usingMonitor(enable)
    }
}
extension MQTT.Client{
    /// Close  gracefully by sending close frame
    @discardableResult
    public func close(_ code:ReasonCode = .success)->Promise<Void>{
        self.close(packet: DisconnectPacket(reason: code))
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
    /// - Returns: EventLoopFuture to be updated with whether server holds a session for this client
    ///
    @discardableResult
    public func open(
        will: (topic: String, payload: Data, qos: MQTTQoS, retain: Bool)? = nil,
        cleanStart: Bool = true
    ) -> Promise<Bool> {
        
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
    /// - Returns: Future waiting for publish to complete. Depending on QoS setting the future will complete
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
        let message = Message(qos: qos, dup: false, topic: topic, retain: retain, payload: payload, properties: [])
        let packetId = self.nextPacketId()
        let packet = PublishPacket(id:packetId,message: message)
        return self.publish(packet: packet).then { _ in }
    }
    /// Subscribe to topic
    /// - Parameter topic: Subscription infos
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    public func subscribe(to topic: String,qos:MQTTQoS = .atLeastOnce) -> Promise<Suback> {
        return self.subscribe(to: [.init(topicFilter: topic, qos: qos)])
    }
    
    /// Subscribe to topic
    /// - Parameter subscriptions: Subscription infos
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server
    ///
    @discardableResult
    public func subscribe(to subscriptions: [Subscribe]) -> Promise<Suback> {
        let packetId = self.nextPacketId()
        let subscriptions: [Subscribe.V5] = subscriptions.map { .init(topicFilter: $0.topicFilter, qos: $0.qos) }
        let packet = SubscribePacket(subscriptions: subscriptions, properties: .init(), id: packetId)
        return self.subscribe(packet: packet)
            .then { message in
                let returnCodes = message.reasons.map { Suback.ReturnCode(rawValue: $0.rawValue) ?? .failure }
                return Suback(returnCodes: returnCodes)
            }
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: Future waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
    ///
    @discardableResult
    public func unsubscribe(from topic: String) -> Promise<Void> {
        return self.unsubscribe(from: [topic])
    }
    /// Unsubscribe from topic
    /// - Parameter subscriptions: List of subscriptions to unsubscribe from
    /// - Returns: Future waiting for unsubscribe to complete. Will wait for UNSUBACK message from server
    ///
    @discardableResult
    public func unsubscribe(from subscriptions: [String]) -> Promise<Void> {
        let packetId = self.nextPacketId()
        let packet = UnsubscribePacket(subscriptions: subscriptions, properties: .init(), id: packetId)
        return self.unsubscribe(packet: packet).then { _ in }
    }
}

extension MQTT.Client {
    
    
    func open(_ packet: ConnectPacket,authflow: (@Sendable(AuthV5) -> Promise<AuthV5>)? = nil) -> Promise<ConnackPacket> {
        self.socket.open(packet: packet).then { packet -> Promise<ConnackPacket> in
            switch packet {
            case let connack as ConnackPacket:
                if connack.sessionPresent {
                    self.resendOnRestart()
                } else {
                    self.inflight.clear()
                }
                return Promise<ConnackPacket>(try self.processConnack(connack))
            case let auth as AuthPacket:
                // auth messages require an auth workflow closure
                guard let authflow else { throw MQTTError.authWorkflowRequired}
                return self.processAuth(auth, authflow: authflow).then({ result in
                    if let packet = result as? ConnackPacket{
                        return packet
                    }
                    throw MQTTError.unexpectedMessage
                })
            default:
                throw MQTTError.unexpectedMessage
            }
        }
    }

    /// Resend PUBLISH and PUBREL messages
    func resendOnRestart() {
        let inflight = self.inflight.packets
        self.inflight.clear()
        inflight.forEach { packet in
            switch packet {
            case let publish as PublishPacket:
                let newPacket = PublishPacket(
                    id: publish.id,
                    message: .init(
                        qos: publish.message.qos,
                        dup: true,
                        topic: publish.message.topic,
                        retain: publish.message.retain,
                        payload: publish.message.payload,
                        properties: publish.message.properties
                    )
                )
                _ = self.publish(packet: newPacket)
            case let pubRel as PubackPacket:
                _ = self.pubRel(packet: pubRel)
            default:
                break
            }
        }
    }
    func processConnack(_ connack: ConnackPacket) throws -> ConnackPacket {
        // connack doesn't return a packet id so this is always 32767. Need a better way to choose first packet id
//        self.globalPacketId.store(connack.packetId + 32767, ordering: .relaxed)
        switch self.config.version {
        case .v3_1_1:
            if connack.returnCode != 0 {
                let returnCode = MQTTError.ConnectionReturnValue(rawValue: connack.returnCode) ?? .unrecognizedReturnValue
                throw MQTTError.connectionError(returnCode)
            }
        case .v5_0:
            if connack.returnCode > 0x7F {
                let returnCode = ReasonCode(rawValue: connack.returnCode) ?? .unrecognisedReason
                throw MQTTError.reasonError(returnCode)
            }
        }
        for property in connack.properties {
            switch property{
            // alter pingreq interval based on session expiry returned from server
            case .serverKeepAlive(let keepAliveInterval):
                self.config.keepAlive = keepAliveInterval
                self.socket.resetPing()
            // client identifier
            case .assignedClientIdentifier(let identifier):
                self.config.clientId = identifier
            // max QoS
            case .maximumQoS(let qos):
                self.connParams.maxQoS = qos
            // max packet size
            case .maximumPacketSize(let maxPacketSize):
                self.connParams.maxPacketSize = Int(maxPacketSize)
            // supports retain
            case .retainAvailable(let retainValue):
                self.connParams.retainAvailable = (retainValue != 0 ? true : false)
            // max topic alias
            case .topicAliasMaximum(let max):
                self.connParams.maxTopicAlias = max
            default:
                break
            }
        }
        return connack
    }
   
    func pubRel(packet: PubackPacket) -> Promise<AckV5?> {
        guard socket.status == .opened else {
            return .init(MQTTError.noConnection)
        }
        self.inflight.add(packet: packet)
        return self.socket.sendPacket(packet).then{ message in
            guard message.type != .PUBREC else {
                throw MQTTError.unexpectedMessage
            }
            self.inflight.remove(id: packet.id)
            guard let pubcomp = message as? PubackPacket else{
                throw MQTTError.unexpectedMessage
            }
            if pubcomp.reason.rawValue > 0x7F {
                throw MQTTError.reasonError(pubcomp.reason)
            }
            return AckV5(reason: pubcomp.reason, properties: pubcomp.properties)
        }
    }
    /// Publish message to topic
    /// - Parameters:
    ///     - packet: Publish packet
    func publish(packet: PublishPacket) -> Promise<AckV5?> {
        guard socket.status == .opened else { return .init(MQTTError.noConnection) }
        // check publish validity
        // check qos against server max qos
        guard self.connParams.maxQoS.rawValue >= packet.message.qos.rawValue else {
            return .init(MQTTPacketError.qosInvalid)
        }
        // check if retain is available
        guard packet.message.retain == false || self.connParams.retainAvailable else {
            return .init(MQTTPacketError.retainUnavailable)
        }
        for p in packet.message.properties {
            // check topic alias
            if case .topicAlias(let alias) = p {
                guard alias <= self.connParams.maxTopicAlias, alias != 0 else {
                    return .init(MQTTPacketError.topicAliasOutOfRange)
                }
            }
            if case .subscriptionIdentifier = p {
                return .init(MQTTPacketError.publishIncludesSubscription)
            }
        }
        // check topic name
        guard !packet.message.topic.contains(where: { $0 == "#" || $0 == "+" }) else {
            return .init(MQTTPacketError.invalidTopicName)
        }

        if packet.message.qos == .atMostOnce {
            return self.socket.sendNoWait(packet).then { nil }
        }

        self.inflight.add(packet: packet)
        return self.socket.sendPacket(packet)
            .then { message -> PubackPacket in
                self.inflight.remove(id: packet.id)
                switch packet.message.qos {
                case .atMostOnce:
                    throw MQTTError.unexpectedMessage
                case .atLeastOnce:
                    guard message.type == .PUBACK else {
                        throw MQTTError.unexpectedMessage
                    }
                case .exactlyOnce:
                    guard message.type == .PUBREC else {
                        throw MQTTError.unexpectedMessage
                    }
                }
                guard let puback = message as? PubackPacket else{
                    throw MQTTError.unexpectedMessage
                }
                if puback.reason.rawValue > 0x7F {
                    throw MQTTError.reasonError(puback.reason)
                }
                return puback
            }
            .then { puback -> Promise<AckV5?>  in
                if puback.type == .PUBREC{
                    return self.pubRel(packet: PubackPacket(id: puback.id,type: .PUBREL))
                }
                return .init(AckV5(reason: puback.reason, properties: puback.properties))
            }
            .catch { error in
                if case MQTTError.serverDisconnection(let ack) = error, ack.reason == .malformedPacket{
                    self.inflight.remove(id: packet.id)
                }
                if case MQTTError.timeout = error{
                    // how to resend here
                }
                throw error
            }
    }
    /// Subscribe to topic
    /// - Parameter packet: Subscription packet
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server
    func subscribe(packet: SubscribePacket) -> Promise<SubackPacket> {
        guard packet.subscriptions.count > 0 else {
            return .init((MQTTPacketError.atLeastOneTopicRequired))
        }
        return self.socket.sendPacket(packet).then { ack in
            if let suback = ack as? SubackPacket{
                return suback
            }
            throw MQTTError.unexpectedMessage
        }
    }
    /// Subscribe to topic
    /// - Parameter packet: Unubscription packet
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server
    func unsubscribe(packet: UnsubscribePacket) -> Promise<SubackPacket> {
        guard packet.subscriptions.count > 0 else {
            return .init((MQTTPacketError.atLeastOneTopicRequired))
        }
        return self.socket.sendPacket(packet).then { ack in
            if let suback = ack as? SubackPacket{
                return suback
            }
            throw MQTTError.unexpectedMessage
        }
    }
    /// Close  from server
    /// - Returns: Future waiting on disconnect message to be sent
    func close(packet: DisconnectPacket) -> Promise<Void> {
        return self.socket.sendNoWait(packet)
    }
    
    func auth(packet: AuthPacket) -> Promise<Packet> {
        return self.socket.sendPacket(packet)
    }
    
    func reAuth(packet: AuthPacket) -> Promise<AuthPacket> {
        guard socket.status == .opened else { return .init(MQTTError.noConnection) }
        return self.socket.sendPacket(packet).then { ack in
            if let authack = ack as? AuthPacket{
                return authack
            }
            throw MQTTError.failedToConnect
        }
    }
    
    func processAuth(_ packet: AuthPacket, authflow:  @escaping @Sendable(AuthV5) -> Promise<AuthV5>) -> Promise<Packet> {
        let promise = Promise<Packet>()
        @Sendable func workflow(_ packet: AuthPacket) {
            let auth = AuthV5(reason: packet.reason, properties: packet.properties)
            authflow(auth)
                .then{ _ in
                    let responsePacket = AuthPacket(reason: packet.reason, properties: packet.properties)
                    return self.auth(packet: responsePacket)
                }
                .then{ result in
                    switch result {
                    case let connack as ConnackPacket:
                        promise.done(connack)
                    case let auth as AuthPacket:
                        switch auth.reason {
                        case .continueAuthentication:
                            workflow(auth)
                        case .success:
                            promise.done(auth)
                        default:
                            promise.done(MQTTError.badResponse)
                        }
                    default:
                        promise.done(MQTTError.unexpectedMessage)
                    }
                }
        }
        workflow(packet)
        return promise
    }
    
    func nextPacketId() -> UInt16 {
        return self.$packetId.write { id in
            if id == UInt16.max {  id = 0 }
            id += 1
            return id
        }
    }
}

//extension MQTT: ReaderDelegate{
//    func readCompleted(_ reader: Reader) {
//
//    }
//    func reader(_ reader: Reader, didReceive error: any Error) {
//        Logger.debug("RECV: \(error)")
//    }
//    func reader(_ reader: Reader, didReceive packet: any Packet) {
//        Logger.debug("RECV: \(packet)")
//        switch packet.type{
//        case .DISCONNECT:
//            self.tryClose(code: (packet as! MQTTDisconnectPacket).reason , reason: .server)
//        case .AUTH:
//            if let task = self.authTask{
//                task.done(with: packet)
//                self.authTask = nil
//            }else if let task = self.connTask{
//                task.done(with: packet)
//                self.connTask = nil
//            }
//        case .CONNACK:
//            if let task = self.connTask{
//                task.done(with: packet)
//                self.connTask = nil
//            }
//        case .PINGREQ:
//            self.pinging?.onPong()
//        default:
//            guard let task = self.allTasks[packet.packetId] else{
//                return
//            }
//            task.done(with: packet)
//            self.allTasks.removeValue(forKey: packet.packetId)
//        }
//        switch packet{
//        case let disconn as MQTTDisconnectPacket:
//            self.tryClose(code: disconn.reason , reason: .server)
//        case let authack as MQTTAuthPacket:
//            if let task = self.authTask{
//                task.done(with: authack)
//                self.authTask = nil
//            }else if let task = self.connTask{
//                task.done(with: authack)
//                self.connTask = nil
//            }
//        case let connack as MQTTConnAckPacket:
//            if let task = self.connTask{
//                task.done(with: connack)
//                self.connTask = nil
//            }
//            if connack.returnCode == 0 {
//                if cleanSession {
////                    deliver.cleanAll()
//                } else {
//                    if let storage = Storage(by: identifier) {
////                        deliver.recoverSessionBy(storage)
//                    } else {
//                        Logger.warning("Localstorage initial failed for key: \(identifier)")
//                    }
//                }
//                self.status = .opened
//            } else {
//                self.close()
//            }
//        case let pong as MQTTPingrespPacket:
//            if let task = self.pingTask{
//                task.done(with: pong)
//                self.pingTask = nil
//            }
//        case let ack as MQTTPubAckPacket:
//            guard var task = self.pubTasks[ack.packetId] else{
//                return
//            }
//            switch task.packet{
//            case let taskpub as MQTTPublishPacket:
//                switch taskpub.publish.qos{
//                case .atMostOnce:
//                    task.promise.done(MQTTError.unexpectedMessage)
//                    self.pubTasks[ack.packetId] = nil
//                    self.inflight.remove(id: ack.packetId)
//                case .atLeastOnce:
//                    if ack.type == .PUBACK {// success
//                        task.promise.done(.init(reason: ack.reason,properties: ack.properties))
//                    }else{
//                        task.promise.done(MQTTError.unexpectedMessage)
//                    }
//                    self.pubTasks[ack.packetId] = nil
//                    self.inflight.remove(id: ack.packetId)
//                case .exactlyOnce:
//                    guard ack.type == .PUBREC else {
//                        task.promise.done(MQTTError.unexpectedMessage)
//                        self.pubTasks[ack.packetId] = nil
//                        self.inflight.remove(id: ack.packetId)
//                        return
//                    }
//                    task.packet = ack
//                    self.send(MQTTPubAckPacket(type: .PUBREL, packetId: packet.packetId))
//                }
//            case let taskack as MQTTPubAckPacket:
//                if taskack.type == .PUBREC,ack.type == .PUBCOMP{ // success
//                    task.promise.done(.init(reason: ack.reason,properties: ack.properties))
//                }else{
//                    task.promise.done(MQTTError.unexpectedMessage)
//                }
//                self.pubTasks[ack.packetId] = nil
//                self.inflight.remove(id: ack.packetId)
//
//            default:
//                //never
//                break
//            }
//        case let suback as MQTTSubAckPacket:
//            if let promise = self.subTasks[packet.packetId] {
//
//                promise.done(suback)
//                self.subTasks[packet.packetId] = nil
//            }
//        default:
//            break
//        }
//    }
//}


