//
//  Client.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/24.
//



import Foundation
import Promise


extension MQTT{
    final class CoreImpl: @unchecked Sendable{
        let socket:Socket
        let config:Config
        private var inflight: Inflight = .init()
        private var connParams = ConnectParams()
        @Atomic
        private var packetId: UInt16 = 0
        /// Initial v3 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        init(_ clientId: String, endpoint:Endpoint,version:Version) {
            self.config = Config(version,clientId:clientId)
            self.socket = Socket(self.config,endpoint: endpoint)
        }
        /// Close from server
        /// - Parameters:
        ///   - code: close reason code send to the server
        /// - Returns: `Promise` waiting on disconnect message to be sent
        func close(_ code:ResultCode.Disconnect = .normal,properties:Properties)->Promise<Void>{
            var packet:DisconnectPacket
            switch config.version {
            case .v5_0:
                packet = .init(result: code,properties: properties)
            case .v3_1_1:
                packet = .init(result: code)
            }
            return self.socket.sendNoWait(packet).map { _ in
                self.socket.directClose(reason: .clientClosed(code, properties))
                return Promise(())
            }
        }
        /// Re-authenticate with server
        ///
        /// - Parameters:
        ///   - properties: properties to attach to auth packet. Must include `authenticationMethod`
        ///   - authflow: Respond to auth packets from server
        /// - Returns: final auth packet returned from server
        ///
        func auth(
            properties: Properties,
            authflow: (@Sendable (AuthV5) -> Promise<AuthV5>)? = nil
        ) -> Promise<AuthV5> {
            let authPacket = AuthPacket(reason: .reAuthenticate, properties: properties)
            return self.reAuth(packet: authPacket)
                .then { packet -> Promise<AuthPacket> in
                    if packet.reason == .success{
                        return .init(packet)
                    }
                    guard let authflow else {
                        throw MQTTError.authflowRequired
                    }
                    return self.processAuth(packet, authflow: authflow).then {
                        guard let auth = $0 as? AuthPacket else{
                            throw MQTTError.unexpectedMessage
                        }
                        return auth
                    }
                }
                .then {
                    AuthV5(reason: $0.reason, properties: $0.properties)
                }
        }
    }
}


extension MQTT.CoreImpl {
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
                guard let authflow else { throw MQTTError.authflowRequired}
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
                let returnCode = ResultCode.ConnectV3(rawValue: connack.returnCode) ?? .unrecognisedReason
                throw MQTTError.connectFailV3(returnCode)
            }
        case .v5_0:
            if connack.returnCode > 0x7F {
                let returnCode = ResultCode.ConnectV5(rawValue: connack.returnCode) ?? .unrecognisedReason
                throw MQTTError.connectFailV5(returnCode)
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
   
    func pubRel(packet: PubackPacket) -> Promise<PubackV5?> {
        guard socket.status == .opened else {
            return .init(MQTTError.noConnection)
        }
        self.inflight.add(packet: packet)
        return self.socket.sendPacket(packet,timeout: self.config.publishTimeout)
            .then{
                guard $0.type != .PUBREC else {
                    throw MQTTError.unexpectedMessage
                }
                self.inflight.remove(id: packet.id)
                guard let pubcomp = $0 as? PubackPacket,pubcomp.type == .PUBCOMP else{
                    throw MQTTError.unexpectedMessage
                }
                if pubcomp.reason.rawValue > 0x7F {
                    throw MQTTError.reasonError(.puback(pubcomp.reason))
                }
                return PubackV5(reason: pubcomp.reason, properties: pubcomp.properties)
            }.catch { err in
                if case MQTTError.timeout = err{
                    //Always try again when timeout
                    return self.socket.sendPacket(packet,timeout: self.config.publishTimeout)
                }
                throw err
            }
    }
    /// Publish message to topic
    /// - Parameters:
    ///     - packet: Publish packet
    func publish(packet: PublishPacket) -> Promise<PubackV5?> {
        guard socket.status == .opened else { return .init(MQTTError.noConnection) }
        // check publish validity
        // check qos against server max qos
        guard self.connParams.maxQoS.rawValue >= packet.message.qos.rawValue else {
            return .init(MQTTError.packetError(.qosInvalid))
        }
        // check if retain is available
        guard packet.message.retain == false || self.connParams.retainAvailable else {
            return .init(MQTTError.packetError(.retainUnavailable))
        }
        for p in packet.message.properties {
            // check topic alias
            if case .topicAlias(let alias) = p {
                guard alias <= self.connParams.maxTopicAlias, alias != 0 else {
                    return .init(MQTTError.packetError(.topicAliasOutOfRange))
                }
            }
            if case .subscriptionIdentifier = p {
                return .init(MQTTError.packetError(.publishIncludesSubscription))
            }
        }
        // check topic name
        guard !packet.message.topic.contains(where: { $0 == "#" || $0 == "+" }) else {
            return .init(MQTTError.packetError(.invalidTopicName))
        }
        if packet.message.qos == .atMostOnce {
            return self.socket.sendNoWait(packet).then { nil }
        }

        self.inflight.add(packet: packet)
        return self.socket.sendPacket(packet,timeout: config.publishTimeout)
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
                    throw MQTTError.reasonError(.puback(puback.reason))
                }
                return puback
            }
            .then { puback -> Promise<PubackV5?>  in
                if puback.type == .PUBREC{
                    return self.pubRel(packet: PubackPacket(id: puback.id,type: .PUBREL))
                }
                return .init(PubackV5(reason: puback.reason, properties: puback.properties))
            }
            .catch { error in
                if case MQTTError.serverDisconnection(let ack) = error, ack == .malformedPacket{
                    self.inflight.remove(id: packet.id)
                }
                if case MQTTError.timeout = error{
                    //Always try again when timeout
                    return self.socket.sendPacket(packet,timeout: self.config.publishTimeout)
                }
                throw error
            }
    }
    /// Subscribe to topic
    /// - Parameter packet: Subscription packet
    /// - Returns: Future waiting for subscribe to complete. Will wait for SUBACK message from server
    func subscribe(packet: SubscribePacket) -> Promise<SubackPacket> {
        guard packet.subscriptions.count > 0 else {
            return .init(MQTTError.packetError(.atLeastOneTopicRequired))
        }
        return self.socket.sendPacket(packet).then {
            if let suback = $0 as? SubackPacket {
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
            return .init(MQTTError.packetError(.atLeastOneTopicRequired))
        }
        return self.socket.sendPacket(packet).then {
            if let suback = $0 as? SubackPacket {
                return suback
            }
            throw MQTTError.unexpectedMessage
        }
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
            authflow(AuthV5(reason: packet.reason, properties: packet.properties))
                .then{
                    self.auth(packet: AuthPacket(reason: $0.reason, properties: $0.properties.properties))
                }
                .then{
                    switch $0 {
                    case let connack as ConnackPacket:
                        promise.done(connack)
                    case let auth as AuthPacket:
                        switch auth.reason {
                        case .continueAuthentication:
                            workflow(auth)
                        case .success:
                            promise.done(auth)
                        default:
                            promise.done(MQTTError.decodeError(.unexpectedTokens))
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


extension MQTT{
    /// connection parameters. Limits set by either client or server
    struct ConnectParams{
        var maxQoS: MQTTQoS = .exactlyOnce
        var maxPacketSize: Int?
        var retainAvailable: Bool = true
        var maxTopicAlias: UInt16 = 65535
    }
}

