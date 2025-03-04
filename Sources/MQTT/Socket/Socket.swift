//
//  Socket.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation
import Network

extension MQTT{
    final class Socket:@unchecked Sendable{
        let queue:DispatchQueue
        var onError:((Error)->Void)?
        var onStatus:((Status,Status)->Void)?
        var onMessage:((Message)->Void)?
        let endpoint:Endpoint
        let config:Config
        private var conn:NWConnection?
        private var retrier:Retrier?
        private var pinging:Pinging?
        private var monitor:Monitor?
        private var activeTasks:[UInt16:Task] = [:] // active workflow tasks
        private var passiveTasks:[UInt16:Task] = [:] // passive workflow tasks
        private var connTask:Task?
        private var authTask:Task?
        private var reader:Reader?
        private var retrying:Bool = false
        private var version:Version { config.version }
        private var inflight:Inflight = .init()
        private var authflow:Authflow?
        private var connPacket:ConnectPacket?
        private var connParams:ConnectParams = .init()

        /// Initial v3 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        init(_ clientId: String, endpoint:Endpoint,version:Version){
            self.config = .init(version, clientId: clientId)
            self.endpoint = endpoint
            self.queue = DispatchQueue.init(label: "swift.mqtt.socket.queue")
            if config.pingEnabled{
                self.pinging = MQTT.Pinging(self, timeout: config.pingTimeout, interval: .init(config.keepAlive))
            }
        }
        deinit {
            self.pinging?.suspend()
            self.conn?.forceCancel()
            self.conn = nil
        }
        private(set) var status:MQTT.Status = .closed(){
            didSet{
                if oldValue != status {
                    MQTT.Logger.debug("Status changed: \(oldValue) --> \(status)")
                    switch status{
                    case .opened:
                        retrier?.reset()
                        pinging?.resume()
                    case .closed(let reason):
                        retrier?.reset()
                        pinging?.suspend()
                        conn = nil
                        if let task = self.connTask{
                            switch reason{
                            case .normalError(let error):
                                task.done(with: error)
                            case .networkError(let error):
                                task.done(with: error)
                            case .clientClosed(let code):
                                task.done(with: MQTTError.clientClosed(code))
                            case .serverClosed(let code):
                                task.done(with: MQTTError.serverClosed(code))
                            default:
                                task.done(with:MQTTError.connectFailed())
                            }
                        }
                        connTask = nil
                        conn?.cancel()
                        conn = nil
                    case .opening:
                        self.pinging?.suspend()
                    case .closing:
                        self.pinging?.suspend()
                    }
                    self.onStatus?(status,oldValue)
                }
            }
        }
        /// Called by the underlying `NWConnection` when its internal state has changed.
        private func handle(state:NWConnection.State){
            switch state{
            case .cancelled:
                // This is the network telling us we're closed.
                // We don't need to actually do anything here
                // other than check our state is ok.
                self.status = .closed()
            case .failed(let error):
                // The connection has failed for some reason.
                self.tryClose(reason: .networkError(error))
                self.onError?(error)
            case .ready:
                print("Network ready")
                break
                // Transitioning to ready means the connection was succeeded. Hooray!
    //            self.doReady()
            case .preparing:
                // This just means connections are being actively established. We have no specific action
                // here.
                self.status = .opening
            case .setup:
                /// inital state
                self.status = .closed()
            case .waiting(let error):
                if case .opening = self.status {
                    // This means the connection cannot currently be completed. We should notify the pipeline
                    // here, or support this with a channel option or something, but for now for the sake of
                    // demos we will just allow ourselves into this stage.tage.
                    // But let's not worry about that right now. so noting happend
                }
                // In this state we've transitioned into waiting, presumably from active or closing. In this
                // version of NIO this is an error, but we should aim to support this at some stage.
                MQTT.Logger.error("connection wating error = \(error)")
                self.tryClose(reason: .networkError(error))
                self.onError?(error)
            default:
                // This clause is here to help the compiler out: it's otherwise not able to
                // actually validate that the switch is exhaustive. Trust me, it is.
                fatalError("Unreachable")
            }
        }
    }
}
extension MQTT.Socket{
    /// Close network connection diirectly
    private func directClose(reason:MQTT.CloseReason?){
        switch self.status{
        case .opened,.opening:
            if case .ready = self.conn?.state{
                self.status = .closing
                self.conn?.cancel()
            }else{
                self.status = .closed(reason)
            }
        case .closing,.closed:
            break
        }
    }
    /// Internal method run in delegate queue
    /// try close when no need retry
    private func tryClose(reason:MQTT.CloseReason?){
        MQTT.Logger.debug("Try close reason:\(reason?.description ?? "")")
        if self.retrying{
            return
        }
        // not retry when reason is nil(close no reason)
        guard let reason else{
            status = .closed()
            return
        }
        // posix network unreachable
        // check your borker address is reachable
        // the monitor just known internet is reachable
        if case .networkError(let err) = reason,
           case .posix(let posix) = err{
            switch posix{
            case .ENETUNREACH,.ENETDOWN:
                self.status = .closed(reason)
                return
            default:
                break
            }
        }
        // not retry when network unsatisfied
        if let monitor = self.monitor, monitor.status == .unsatisfied{
            status = .closed(reason)
            return
        }
        // not retry when retrier is nil
        guard let retrier = self.retrier else{
            status = .closed(reason)
            return
        }
        // not retry when limits or filter
        guard let delay = retrier.retry(when: reason) else{
            status = .closed(reason)
            return
        }
        // not retry when no prev conn packet
        guard let connPacket else{
            status = .closed(reason)
            return
        }
        // not clean session when auto reconnection
        if connPacket.cleanSession{
            self.connPacket = connPacket.copyNotClean()
        }
        self.retrying = true
        self.status = .opening
        self.queue.asyncAfter(deadline: .now() + delay){
            self.connect()
            self.retrying = false
        }
    }
    @discardableResult
    func connect() -> Promise<ConnackPacket> {
        guard let packet = self.connPacket else{
            return .init(MQTTError.connectFailed())
        }
        self.start()
        return self.sendPacket(packet).then { packet in
            switch packet {
            case let connack as ConnackPacket:
                try self.processConnack(connack)
                self.status = .opened
                if connack.sessionPresent {
                    self.resendOnRestart()
                } else {
                    self.inflight.clear()
                }
                return Promise<ConnackPacket>(connack)
            case let auth as AuthPacket:
                guard let authflow = self.authflow else { throw MQTTError.authflowRequired}
                return self.processAuth(auth, authflow: authflow).then{ result in
                    if let packet = result as? ConnackPacket{
                        self.status = .opened
                        return packet
                    }
                    throw MQTTError.unexpectMessage
                }
            default:
                throw MQTTError.unexpectMessage
            }
        }.catch { error in
            self.directClose(reason: .normalError(error))
        }
    }
    private func start(){
        let params = endpoint.params(config: config)
        let conn = NWConnection(to: params.0, using: params.1)
        conn.stateUpdateHandler = self.handle(state:)
        conn.start(queue: queue)
        self.conn = conn
        self.reader = Reader(self,conn: conn)
        self.reader?.start()
    }
}
extension MQTT.Socket{
    @discardableResult
    private func sendNoWait(_ packet: Packet)->Promise<Void> {
        guard self.status == .opened else{
            return .init(MQTTError.noConnection)
        }
        do {
            MQTT.Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: version, to: &buffer)
            return self.send(data: buffer.data)
        } catch {
            return .init(error)
        }
    }
    @discardableResult
    private func sendPacket(_ packet: Packet,timeout:UInt64? = nil)->Promise<Packet> {
        guard self.status == .opened || packet.type == .CONNECT else{
            return Promise<Packet>(MQTTError.noConnection)
        }
        let task = MQTT.Task()
        switch packet.type{
        case .CONNECT: /// send `CONNECT` is active workflow but packetId is 0
            self.connTask = task
        case .AUTH: /// send `AUTH` is active workflow but packetId is 0
            self.authTask = task
        case .PUBREC: /// send `PUBREC` is passive workflow so put it into `passiveTasks`
            self.passiveTasks[packet.id] = task
        ///send  these packets  is active workflow so put it into `passiveTasks`
        case .PUBLISH,.PUBREL,.SUBSCRIBE,.UNSUBSCRIBE:
            self.activeTasks[packet.id] = task
        case .PUBACK,.PUBCOMP: /// send `PUBACK` `PUBCOMP` is passive workflow but we will `sendNoWait`.  so error here
            break
        case .PINGREQ,.DISCONNECT: /// send `PINGREQ` `DISCONNECT` is active workflow but we will `sendNoWait`.  so error here
            break
        case .CONNACK,.SUBACK,.UNSUBACK,.PINGRESP: ///client never send them
            break
        }
        do {
            MQTT.Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: version, to: &buffer)
            return send(data: buffer.data).then { _ in
                return task.start(in: self.queue,timeout:timeout)
            }
        } catch {
            return .init(error)
        }
    }
    @discardableResult
    private func send(data:Data)->Promise<Void>{
        guard let conn = self.conn else{
            return .init(MQTTError.noConnection)
        }
        let promise = Promise<Void>()
        conn.send(content: data,contentContext: .default(timeout: config.writingTimeout), completion: .contentProcessed({ error in
            if let error{
                MQTT.Logger.error("SOCKET SEND: \(data.count) bytes failed. error:\(error)")
                promise.done(error)
            }else{
                promise.done(())
            }
        }))
        return promise
    }
}
// MARK: Ping Pong  Retry Monitor
extension MQTT.Socket{
    // monitor
    private func newMonitor()->MQTT.Monitor{
        let m = MQTT.Monitor{[weak self] new in
            guard let self else { return }
            switch new{
            case .satisfied:
                if self.status == .opening || self.status == .opened{
                    return
                }
                guard let packet = self.connPacket else{
                    return
                }
                // not clean session when auto reconnection
                if packet.cleanSession{
                    self.connPacket = packet.copyNotClean()
                }
                self.status = .opening
                self.connect()
            case .unsatisfied:
                self.directClose(reason: .unsatisfied)
            default:
                break
            }
        }
        self.monitor = m
        return m
    }
    func setMonitor(_ enable:Bool){
        guard enable else{
            self.monitor?.stop()
            self.monitor = nil
            return
        }
        let monitor = self.monitor ?? newMonitor()
        monitor.start(queue: queue)
    }
    // ping pong
    private func resetPing(){
        if self.config.pingEnabled{
            self.pinging = MQTT.Pinging(self,timeout:config.pingTimeout, interval: .init(config.keepAlive))
            self.pinging?.resume()
        }else{
            self.pinging?.suspend()
            self.pinging = nil
        }
    }
    func sendPingreq(){
        sendNoWait(PingreqPacket())
    }
    func pingTimeout(){
        directClose(reason: .pingTimeout)
    }
    // retrier
    func startRetrier(_ retrier:MQTT.Retrier){
        self.retrier = retrier
    }
    func stopRetrier(){
        self.retrier = nil
    }
}
// MARK: Reader Delegate
extension MQTT.Socket{
    /// Respond to PUBREL message by sending PUBCOMP. Do this separate from `ackPublish` as the broker might send
    /// multiple PUBREL messages, if the client is slow to respond
    private func ackPubrel(_ packet: PubackPacket){
        self.sendNoWait(PubackPacket(id: packet.id, type: .PUBCOMP))
    }
    /// Respond to PUBLISH message
    /// If QoS is `.atMostOnce` then no response is required
    /// If QoS is `.atLeastOnce` then send PUBACK
    /// If QoS is `.exactlyOnce` then send PUBREC, wait for PUBREL and then respond with PUBCOMP (in `ackPubrel`)
    private func ackPublish(_ pubpkg: PublishPacket) {
        switch pubpkg.message.qos {
        case .atMostOnce:
            self.onMessage?(pubpkg.message)
        case .atLeastOnce:
            self.sendNoWait(PubackPacket(id:pubpkg.id,type: .PUBACK)).then { _ in
                self.onMessage?(pubpkg.message)
            }
        case .exactlyOnce:
            let packet = PubackPacket(id:pubpkg.id,type: .PUBREC)
            self.sendPacket(packet,timeout: self.config.publishTimeout)
                .then { newpkg in
                    /// if we have received the PUBREL we can process the published message. `PUBCOMP` is sent by `ackPubrel`
                    if newpkg.type == .PUBREL {
                        return pubpkg.message
                    }
                    if  let _ = (newpkg as? PublishPacket)?.message {
                        /// if we receive a publish message while waiting for a `PUBREL` from broker
                        /// then replace data to be published and retry `PUBREC`. `PUBREC` is sent by self `ackPublish`
                        /// but there wo do noting because task will be replace by the same packetId
                        /// so never happen here
                    }
                    throw MQTTError.unexpectMessage
                }
                .then{ msg in
                    self.onMessage?(msg)
                }.catch { err in
                    if case MQTTError.timeout = err{
                        //Always try again when timeout
                        return self.sendPacket(packet,timeout: self.config.publishTimeout)
                    }
                    throw err
                }
        }
    }
    func readCompleted(_ reader: Reader) {
        self.directClose(reason: nil)
    }
    func reader(_ reader: Reader, didReceive error: any Error) {
        MQTT.Logger.error("RECV: \(error)")
        self.clearAllTask(with: error)
        switch error{
        case let err as NWError:
            self.tryClose(reason: .networkError(err))
        default:
            self.tryClose(reason: .normalError(error))
        }
        self.onError?(error)
    }
    func reader(_ reader: Reader, didReceive packet: Packet) {
        MQTT.Logger.debug("RECV: \(packet)")
        switch packet.type{
        //----------------------------------no need callback--------------------------------------------
        case .PINGRESP:
            self.pinging?.onPong()
        case .DISCONNECT:
            let disconnect = packet as! DisconnectPacket
            self.clearAllTask(with: MQTTError.serverClosed(disconnect.code))
            self.tryClose(reason: .serverClosed(disconnect.code))
        case .PINGREQ:
            self.sendNoWait(PingrespPacket())
        //----------------------------------need callback by packet type----------------------------------
        case .CONNACK:
            self.doneConnTask(with: packet)
        case .AUTH:
            self.doneAuthTask(with: packet)
        // --------------------------------need callback by packetId-------------------------------------
        case .PUBLISH:
            self.ackPublish(packet as! PublishPacket)
        case .PUBREL:
            self.donePassiveTask(with: packet)
            self.ackPubrel(packet as! PubackPacket)
        case .PUBACK:  // when publish qos=1 recv ack from broker
            self.doneActiveTask(with: packet)
        case .PUBREC:  // when publish qos=2 recv ack from broker
            self.doneActiveTask(with: packet)
        case .PUBCOMP: // when qos=2 recv ack from broker after pubrel(re pubrec)
            self.doneActiveTask(with: packet)
        case .SUBACK:  // when subscribe packet send recv ack from broker
            self.doneActiveTask(with: packet)
        case .UNSUBACK:// when unsubscribe packet send recv ack from broker
            self.doneActiveTask(with: packet)
        // ---------------------------at client we only send them never recv-------------------------------
        case .CONNECT, .SUBSCRIBE, .UNSUBSCRIBE:
            // MQTTError.unexpectedMessage
            MQTT.Logger.error("Unexpected MQTT Message:\(packet)")
        }
    }
    private func clearAllTask(with error:Error){
        self.passiveTasks.forEach { id,task in
            task.done(with: error)
        }
        self.activeTasks.forEach { id,task in
            task.done(with: error)
        }
        self.passiveTasks = [:]
        self.activeTasks = [:]
    }
    private func doneConnTask(with packet:Packet){
        if let task = self.connTask{
            task.done(with: packet)
            self.connTask = nil
        }
    }
    private func doneAuthTask(with packet:Packet){
        if let task = self.authTask{
            task.done(with: packet)
            self.authTask = nil
        }else if let task = self.connTask{
            task.done(with: packet)
            self.connTask = nil
        }
    }
    private func doneActiveTask(with packet:Packet){
        guard let task = self.activeTasks[packet.id] else{
            /// process packets where no equivalent task was found we only send response to v5 server
            if case .PUBREC = packet.type,case .v5_0 = self.config.version{
                self.sendNoWait(PubackPacket(id:packet.id,type: .PUBREL, code: .packetIdentifierNotFound))
            }
            return
        }
        task.done(with: packet)
        self.activeTasks.removeValue(forKey: packet.id)
    }
    private func donePassiveTask(with packet:Packet){
        guard let task = self.passiveTasks[packet.id] else{
            /// process packets where no equivalent task was found we only send response to v5 server
            if case .PUBREL = packet.type,case .v5_0 = self.config.version{
                self.sendNoWait(PubackPacket(id:packet.id,type: .PUBCOMP, code: .packetIdentifierNotFound))
            }
            return
        }
        task.done(with: packet)
        self.passiveTasks.removeValue(forKey: packet.id)
    }
}
//MARK: Core Implemention for OPEN/AUTH/CLOSE
extension MQTT.Socket{
    @discardableResult
    func open(_ packet: ConnectPacket,authflow: Authflow? = nil) -> Promise<ConnackPacket> {
        self.connPacket = packet
        self.authflow = authflow
        switch self.status{
        case .opened,.opening:
            return .init(MQTTError.alreadyOpened)
        default:
            break
        }
        self.status = .opening
        return self.connect()
    }
    func auth(properties: Properties,authflow: (@Sendable (AuthV5) -> Promise<AuthV5>)? = nil) -> Promise<AuthV5> {
        let authPacket = AuthPacket(code: .reAuthenticate, properties: properties)
        return self.reAuth(packet: authPacket).then { packet -> Promise<AuthPacket> in
            if packet.code == .success{
                return .init(packet)
            }
            guard let authflow else {
                throw MQTTError.authflowRequired
            }
            return self.processAuth(packet, authflow: authflow).then {
                guard let auth = $0 as? AuthPacket else{
                    throw MQTTError.unexpectMessage
                }
                return auth
            }
        }.then {
            AuthV5(code: $0.code, properties: $0.properties)
        }
    }
    func close(_ code:ResultCode.Disconnect = .normal,properties:Properties)->Promise<Void>{
        var packet:DisconnectPacket
        switch config.version {
        case .v5_0:
            packet = .init(code: code,properties: properties)
        case .v3_1_1:
            packet = .init(code: code)
        }
        switch self.status{
        case .closing,.closed:
            return .init(MQTTError.alreadyClosed)
        case .opening:
            self.directClose(reason: .normalError(MQTTError.clientClosed(code)))
            return .init()
        case .opened:
            return self.sendNoWait(packet).then{ _ in
                self.directClose(reason: .normalError(MQTTError.clientClosed(code)))
            }
        }
    }
    
    private func reAuth(packet: AuthPacket) -> Promise<AuthPacket> {
        guard self.status == .opened else { return .init(MQTTError.noConnection) }
        return self.sendPacket(packet).then { ack in
            if let authack = ack as? AuthPacket{
                return authack
            }
            throw MQTTError.connectFailed()
        }
    }
    
    private func processAuth(_ packet: AuthPacket, authflow:@escaping Authflow) -> Promise<Packet> {
        let promise = Promise<Packet>()
        @Sendable func workflow(_ packet: AuthPacket) {
            authflow(AuthV5(code: packet.code, properties: packet.properties)).then{
                self.sendPacket(AuthPacket(code: $0.code, properties: $0.properties.properties))
            }.then{
                switch $0 {
                case let connack as ConnackPacket:
                    promise.done(connack)
                case let auth as AuthPacket:
                    switch auth.code {
                    case .continueAuthentication:
                        workflow(auth)
                    case .success:
                        promise.done(auth)
                    default:
                        promise.done(MQTTError.decodeError(.unexpectedTokens))
                    }
                default:
                    promise.done(MQTTError.unexpectMessage)
                }
            }
        }
        workflow(packet)
        return promise
    }
    private func resendOnRestart() {
        let inflight = self.inflight.packets
        self.inflight.clear()
        inflight.forEach { packet in
            switch packet {
            case let publish as PublishPacket:
                let newPacket = PublishPacket( id: publish.id, message: publish.message.duplicate())
                _ = self.publish(packet: newPacket)
            case let pubRel as PubackPacket:
                _ = self.pubRel(packet: pubRel)
            default:
                break
            }
        }
    }
    private func processConnack(_ connack: ConnackPacket)throws {
        switch self.config.version {
        case .v3_1_1:
            if connack.returnCode != 0 {
                let code = ResultCode.ConnectV3(rawValue: connack.returnCode) ?? .unrecognisedReason
                throw MQTTError.connectFailed(.connectv3(code))
            }
        case .v5_0:
            if connack.returnCode > 0x7F {
                let code = ResultCode.ConnectV5(rawValue: connack.returnCode) ?? .unrecognisedReason
                throw MQTTError.connectFailed(.connectv5(code))
            }
        }
        for property in connack.properties {
            switch property{
            // alter pingreq interval based on session expiry returned from server
            case .serverKeepAlive(let keepAliveInterval):
                self.config.keepAlive = keepAliveInterval
                self.resetPing()
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
    }
}
//MARK: Core Implemention for PUB/SUB
extension MQTT.Socket {
    func pubRel(packet: PubackPacket) -> Promise<PubackV5?> {
        guard self.status == .opened else {
            return .init(MQTTError.noConnection)
        }
        self.inflight.add(packet: packet)
        return self.sendPacket(packet,timeout: self.config.publishTimeout).then{
            guard $0.type != .PUBREC else {
                throw MQTTError.unexpectMessage
            }
            self.inflight.remove(id: packet.id)
            guard let pubcomp = $0 as? PubackPacket,pubcomp.type == .PUBCOMP else{
                throw MQTTError.unexpectMessage
            }
            if pubcomp.code.rawValue > 0x7F {
                throw MQTTError.publishFailed(pubcomp.code)
            }
            return PubackV5(code: pubcomp.code, properties: pubcomp.properties)
        }.catch { err in
            if case MQTTError.timeout = err{
                //Always try again when timeout
                return self.sendPacket(packet,timeout: self.config.publishTimeout)
            }
            throw err
        }
    }
    func publish(packet: PublishPacket) -> Promise<PubackV5?> {
        guard self.status == .opened else { return .init(MQTTError.noConnection) }
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
            return self.sendNoWait(packet).then { nil }
        }
        self.inflight.add(packet: packet)
        return self.sendPacket(packet,timeout: self.config.publishTimeout).then {pkg in
            self.inflight.remove(id: packet.id)
            switch packet.message.qos {
            case .atMostOnce:
                throw MQTTError.unexpectMessage
            case .atLeastOnce:
                guard pkg.type == .PUBACK else {
                    throw MQTTError.unexpectMessage
                }
            case .exactlyOnce:
                guard pkg.type == .PUBREC else {
                    throw MQTTError.unexpectMessage
                }
            }
            guard let ack = pkg as? PubackPacket else{
                throw MQTTError.unexpectMessage
            }
            if ack.code.rawValue > 0x7F {
                throw MQTTError.publishFailed(ack.code)
            }
            return ack
        }.then {ack  in
            if ack.type == .PUBREC{
                return self.pubRel(packet: PubackPacket(id: ack.id,type: .PUBREL))
            }
            return Promise<PubackV5?>(PubackV5(code: ack.code, properties: ack.properties))
        }.catch { error in
            if case MQTTError.serverClosed(let ack) = error, ack == .malformedPacket{
                self.inflight.remove(id: packet.id)
            }
            if case MQTTError.timeout = error{
                //Always try again when timeout
                return self.sendPacket(packet,timeout: self.config.publishTimeout)
            }
            throw error
        }
    }
    func subscribe(packet: SubscribePacket) -> Promise<SubackPacket> {
        guard packet.subscriptions.count > 0 else {
            return .init(MQTTError.packetError(.atLeastOneTopicRequired))
        }
        return self.sendPacket(packet).then {
            if let suback = $0 as? SubackPacket {
                return suback
            }
            throw MQTTError.unexpectMessage
        }
    }
    func unsubscribe(packet: UnsubscribePacket) -> Promise<SubackPacket> {
        guard packet.subscriptions.count > 0 else {
            return .init(MQTTError.packetError(.atLeastOneTopicRequired))
        }
        return self.sendPacket(packet).then {
            if let suback = $0 as? SubackPacket {
                return suback
            }
            throw MQTTError.unexpectMessage
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
extension NWConnection.ContentContext{
    static func `default`(timeout:UInt64)->NWConnection.ContentContext{
        return .init(identifier: "swift-mqtt",expiration: timeout)
    }
}

