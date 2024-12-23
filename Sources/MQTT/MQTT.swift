//
//  MQTT.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//


import Foundation
import Network
import Promise

public protocol MQDelegate:AnyObject{
    func mqtt(_ mqtt: MQTT, didUpdate status:MQTT.Status,prev:MQTT.Status)
    func mqtt(_ mqtt: MQTT, didReceive error:Message)
    func mqtt(_ mqtt: MQTT, didReceive error:Error)

}

public final class MQTT:@unchecked Sendable{
    private let socket:Socket
    private let version:Version
    private var inflight: Inflight = .init()
    private var connParams = Socket.Params()
    @Atomic private var packetId: UInt16 = 1
    public var config:Config
    nonisolated(unsafe) static var logger:Logger = .init(minLevel: .warning)
    public class var logLevel:Logger.Level{
        get {logger.minLevel}
        set {logger = .init(minLevel: newValue)}
    }
    /// Initial client object
    ///
    /// - Parameters:
    ///   - clientID: Client Identifier
    ///   - endpoint:
    ///   - params: 
    public init(_ clientID: String, endpoint:NWEndpoint,params:NWParameters = .tls,version:Version = .v5_0) {
        self.version = version
        self.config = Config(clientId:clientID)
        self.socket = Socket(version,endpoint: endpoint, params: params)
    }
}
extension MQTT {
    /// Provides implementations of functions that expose MQTT Version 5.0 features
    public struct V5:Sendable {
        let client: MQTT
    }
    /// access MQTT v5 functionality
    public var v5: V5 {
        precondition(self.version == .v5_0, "Cannot use v5 functions with v3.1 client")
        return V5(client: self)
    }
}
extension MQTT{
    
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

extension MQTT {
    /// Close  gracefully by sending close frame
    func close(_ code:ReasonCode = .success)->Promise<Void>{
        self.close(packet: DisconnectPacket(reason: code))
    }
    
    func connect(
        packet: ConnectPacket,
        authflow: (@Sendable(AuthV5) -> Promise<AuthV5>)? = nil
    ) -> Promise<ConnackPacket> {
//        let pingInterval = self.configuration.pingInterval ?? TimeAmount.seconds(max(Int64(packet.keepAliveSeconds - 5), 5))
        self.socket.open(config: self.config).then { pkg -> Promise<ConnackPacket> in
            switch pkg {
            case let connack as ConnackPacket:
                if connack.sessionPresent {
                    self.resendOnRestart()
                } else {
                    self.inflight.clear()
                }
                return .init(try self.processConnack(connack))
            case let auth as AuthPacket:
                // auth messages require an auth workflow closure
                guard let authflow else { throw MQTTError.authWorkflowRequired}
                return self.processAuth(auth, authflow: authflow).then({ result in
                    guard let result = result as? ConnackPacket else { throw MQTTError.unexpectedMessage }
                    return result
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
                    publish: .init(
                        qos: publish.publish.qos,
                        retain: publish.publish.retain,
                        dup: true,
                        topicName: publish.publish.topicName,
                        payload: publish.publish.payload,
                        properties: publish.publish.properties
                    ),
                    id: publish.id
                )
                _ = self.publish(packet: newPacket)
            case let pubRel as PubAckPacket:
                _ = self.pubRel(packet: pubRel)
            default:
                break
            }
        }
    }

    func processConnack(_ connack: ConnackPacket) throws -> ConnackPacket {
        // connack doesn't return a packet id so this is always 32767. Need a better way to choose first packet id
//        self.globalPacketId.store(connack.packetId + 32767, ordering: .relaxed)
        switch self.version {
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
        for property in connack.properties.properties {
            // alter pingreq interval based on session expiry returned from server
            if case .serverKeepAlive(let keepAliveInterval) = property {
                self.config.keepAlive = keepAliveInterval
            }
            self.socket.updatePing()
            // client identifier
            if case .assignedClientIdentifier(let identifier) = property {
                self.config.clientId = identifier
            }
            // max QoS
            if case .maximumQoS(let qos) = property {
                self.connParams.maxQoS = qos
            }
            // max packet size
            if case .maximumPacketSize(let maxPacketSize) = property {
                self.connParams.maxPacketSize = Int(maxPacketSize)
            }
            // supports retain
            if case .retainAvailable(let retainValue) = property, let retainAvailable = (retainValue != 0 ? true : false) {
                self.connParams.retainAvailable = retainAvailable
            }
            // max topic alias
            if case .topicAliasMaximum(let max) = property {
                self.connParams.maxTopicAlias = max
            }
        }
        return connack
    }
   
    func pubRel(packet: PubAckPacket) -> Promise<Packet> {
        guard socket.status == .opened else { return .init(MQTTError.noConnection) }
        self.inflight.add(packet: packet)
        return self.socket.sendPacket(packet).then{ message in
            guard message.type != .PUBREC else {
                throw MQTTError.unexpectedMessage
            }
            self.inflight.remove(id: packet.id)
            guard message.type == .PUBCOMP else {
                throw MQTTError.unexpectedMessage
            }
            if let pubAckPacket = message as? PubAckPacket {
                if pubAckPacket.reason.rawValue > 0x7F {
                    throw MQTTError.reasonError(pubAckPacket.reason)
                }
            }
            return message
        }
    }
    /// Publish message to topic
    /// - Parameters:
    ///     - packet: Publish packet
    func publish(packet: PublishPacket) -> Promise<AckV5?> {
        guard socket.status == .opened else { return .init(MQTTError.noConnection) }
        // check publish validity
        // check qos against server max qos
        guard self.connParams.maxQoS.rawValue >= packet.publish.qos.rawValue else {
            return .init(MQTTPacketError.qosInvalid)
        }
        // check if retain is available
        guard packet.publish.retain == false || self.connParams.retainAvailable else {
            return .init(MQTTPacketError.retainUnavailable)
        }
        for p in packet.publish.properties {
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
        guard !packet.publish.topicName.contains(where: { $0 == "#" || $0 == "+" }) else {
            return .init(MQTTPacketError.invalidTopicName)
        }

        if packet.publish.qos == .atMostOnce {
            return self.socket.sendNoWait(packet).then { nil }
        }

        self.inflight.add(packet: packet)
        return self.socket.sendPacket(packet)
            .then { message -> PubAckPacket in
                self.inflight.remove(id: packet.id)
                if packet.publish.qos == .atLeastOnce {
                    guard message.type == .PUBACK else {
                        throw MQTTError.unexpectedMessage
                    }
                } else if packet.publish.qos == .exactlyOnce {
                    guard message.type == .PUBREC else {
                        throw MQTTError.unexpectedMessage
                    }
                }
                if let pubAckPacket = message as? PubAckPacket {
                    if pubAckPacket.reason.rawValue > 0x7F {
                        throw MQTTError.reasonError(pubAckPacket.reason)
                    }
                    return pubAckPacket
                }
                throw MQTTError.unexpectedMessage
            }
            .then { ackPacket -> Promise<AckV5?>  in
                let ackInfo = AckV5(reason: ackPacket.reason, properties: ackPacket.properties)
                if packet.publish.qos == .exactlyOnce {
                    let pubRelPacket = PubAckPacket(type: .PUBREL, packetId: packet.id)
                    return self.pubRel(packet: pubRelPacket).then { _ in ackInfo }
                }
                return .init(ackInfo)
            }
            .catch { error in
                if case MQTTError.serverDisconnection(let ack) = error,
                   ack.reason == .malformedPacket
                {
                    self.inflight.remove(id: packet.id)
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
    func unsubscribe(packet: UnsubPacket) -> Promise<SubackPacket> {
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
                .then({ _ in
                    let responsePacket = AuthPacket(reason: packet.reason, properties: packet.properties)
                    return self.auth(packet: responsePacket)
                })
                .then({ result in
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
                })
//                .flatMap { _ -> EventLoopFuture<MQTTPacket> in
//                    let responsePacket = MQTTAuthPacket(reason: packet.reason, properties: packet.properties)
//                    return self.auth(packet: responsePacket)
//                }
//                .map { result in
//                    switch result {
//                    case let connack as MQTTConnAckPacket:
//                        promise.succeed(connack)
//                    case let auth as MQTTAuthPacket:
//                        switch auth.reason {
//                        case .continueAuthentication:
//                            workflow(auth)
//                        case .success:
//                            promise.succeed(auth)
//                        default:
//                            promise.fail(MQTTError.badResponse)
//                        }
//                    default:
//                        promise.fail(MQTTError.unexpectedMessage)
//                    }
//                }
//                .cascadeFailure(to: promise)
        }
        workflow(packet)
        return promise
    }
    
    func nextPacketId() -> UInt16 {
        return self.$packetId.write { id in
            if id == UInt16.max {
                id = 0
            }
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


