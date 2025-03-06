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
        //--- Keep safely by sharing a same status lock ---
        private let safe = Safely()//status safe lock
        private var conn:NWConnection?
        private var reader:Reader?
        private var retrier:Retrier?
        private var pinging:Pinging?
        private var monitor:Monitor?
        private var retrying:Bool = false
        private var authflow:Authflow?
        private var connPacket:ConnectPacket?
        private var connParams:ConnectParams = .init()
        //--- Keep safely themself ---
        @Safely private var connTask:Task?
        @Safely private var authTask:Task?
        @Safely private var inflight:[Packet] = []
        @Safely private var activeTasks:[UInt16:Task] = [:] // active workflow tasks
        @Safely private var passiveTasks:[UInt16:Task] = [:] // passive workflow tasks
        /// Initial v3 client object
        ///
        /// - Parameters:
        ///   - clientID: Client Identifier
        ///   - endpoint:The network endpoint
        init(_ clientId: String, endpoint:Endpoint,version:Version){
            self.config = .init(version, clientId: clientId)
            self.endpoint = endpoint
            self.queue = DispatchQueue(label: "swift.mqtt.socket.queue",qos: .default,attributes: .concurrent)
            if config.pingEnabled{
                self.pinging = MQTT.Pinging(self, timeout: config.pingTimeout, interval: .init(config.keepAlive))
            }
        }
        deinit {
            self.pinging?.suspend()
            self.reader = nil
            self.conn?.forceCancel()
            self.conn = nil
        }
        var status:Status{
            safe.lock(); defer{ safe.unlock() }
            return _status
        }
        private func setStatus(_ status:Status){
            safe.lock();  defer{ safe.unlock() }
            _status = status
        }
        private var _status:Status = .closed(){
            didSet{
                if oldValue != _status {
                    MQTT.Logger.debug("StatusChanged: \(oldValue) --> \(_status)")
                    switch _status{
                    case .opened:
                        retrier?.reset()
                        pinging?.resume()
                    case .closed(let reason):
                        MQTT.Logger.debug("CloseReason:\(reason.debugDescription)")
                        reader = nil
                        retrier?.reset()
                        pinging?.suspend()
                        conn?.cancel()
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
                    case .opening:
                        self.pinging?.suspend()
                    case .closing:
                        self.pinging?.suspend()
                    }
                    self.onStatus?(_status,oldValue)
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
                setStatus(.closed())
            case .failed(let error):
                // The connection has failed for some reason.
//                self.tryClose(reason: .networkError(error))
                self.onError?(error)
            case .ready:
//                print("Network ready")
                break
                //Transitioning to ready means the connection was succeeded. Hooray!
//                self.doReady()
            case .preparing:
                // This just means connections are being actively established. We have no specific action
                // here.
//                self.status = .opening
                break
            case .setup:
                /// inital state
                setStatus(.closed())
            case .waiting(let error):
                if case .opening = status {
                    // This means the connection cannot currently be completed. We should notify the pipeline
                    // here, or support this with a channel option or something, but for now for the sake of
                    // demos we will just allow ourselves into this stage.tage.
                    // But let's not worry about that right now. so noting happend
                }
                // In this state we've transitioned into waiting, presumably from active or closing. In this
                // version of NIO this is an error, but we should aim to support this at some stage.
                MQTT.Logger.error("wating error = \(error)")
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
    /// Internal method run in delegate queue
    /// try close when no need retry
    private func tryClose(reason:MQTT.CloseReason?,function:String=#function,line:Int=#line){
        safe.lock(); defer{ safe.unlock() }
        if self.retrying{
            return
        }
        if case .closed = _status{
            return
        }
        if case .closing = _status{
            return
        }
        MQTT.Logger.debug("TryClose[\(function)->\(line)]")
        if let reason { MQTT.Logger.debug("Reason[\(reason)]") }
        // not retry when reason is nil(close no reason)
        guard let reason else{
            _status = .closed()
            return
        }
        // posix network unreachable
        // check your borker address is reachable
        // the monitor just known internet is reachable
        if case .networkError(let err) = reason,case .posix(let posix) = err{
            switch posix{
            case .ENETUNREACH, .ENETDOWN: // network unrachable or down
                _status = .closed(reason)
                return
            default:
                break
            }
        }
        // not retry when network unsatisfied
        if let monitor = self.monitor, monitor.status == .unsatisfied{
            _status = .closed(reason)
            return
        }
        // not retry when retrier is nil
        guard let retrier = self.retrier else{
            _status = .closed(reason)
            return
        }
        // not retry when limits or filter
        guard let delay = retrier.retry(when: reason) else{
            _status = .closed(reason)
            return
        }
        // not retry when no prev conn packet
        guard let connPacket else{
            _status = .closed(reason)
            return
        }
        // not clean session when auto reconnection
        if connPacket.cleanSession{
            self.connPacket = connPacket.copyNotClean()
        }
        self.retrying = true
        _status = .opening
        print("Retry Delay = \(delay)")
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
                self.setStatus(.opened)
                if connack.sessionPresent {
                    self.resendOnRestart()
                } else {
                    self.$inflight.clear()
                }
                return Promise<ConnackPacket>(connack)
            case let auth as AuthPacket:
                guard let authflow = self.authflow else { throw MQTTError.authflowRequired}
                return self.processAuth(auth, authflow: authflow).then{ result in
                    if let packet = result as? ConnackPacket{
                        self.setStatus(.opened)
                        return packet
                    }
                    throw MQTTError.unexpectMessage
                }
            default:
                throw MQTTError.unexpectMessage
            }
        }.catch { error in
            self.setStatus(.closed(.normalError(error)))
        }
    }
    private func start(){
        let params = endpoint.params(config: config)
        let conn = NWConnection(to: params.0, using: params.1)
        conn.stateUpdateHandler = self.handle(state:)
        conn.start(queue: queue)
        self.reader = Reader(self,conn: conn)
        self.reader?.start()
        self.conn = conn
        
    }
}
extension MQTT.Socket{
    @discardableResult
    private func sendNoWait(_ packet: Packet)->Promise<Void> {
        do {
            MQTT.Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: config.version, to: &buffer)
            return self.send(data: buffer.data)
        } catch {
            return .init(error)
        }
    }
    @discardableResult
    private func sendPacket(_ packet: Packet,timeout:UInt64? = nil)->Promise<Packet> {
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
            try packet.write(version: config.version, to: &buffer)
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
    private func monitorConnect(){
        safe.lock(); defer{ safe.unlock() }
        switch _status{
        case .opened,.opening:
            return
        default:
            guard let packet = self.connPacket else{
                return
            }
            // not clean session when auto reconnection
            if packet.cleanSession{
                self.connPacket = packet.copyNotClean()
            }
            _status = .opening
            self.connect()
        }
    }
    // monitor
    private func newMonitor()->MQTT.Monitor{
        let m = MQTT.Monitor{[weak self] new in
            guard let self else { return }
            switch new{
            case .satisfied:
                self.monitorConnect()
            case .unsatisfied:
                self.setStatus(.closed(.unsatisfied))
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
        tryClose(reason: .pingTimeout)
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
        self.sendNoWait(packet.pubcomp())
    }
    /// Respond to PUBLISH message
    /// If QoS is `.atMostOnce` then no response is required
    /// If QoS is `.atLeastOnce` then send PUBACK
    /// If QoS is `.exactlyOnce` then send PUBREC, wait for PUBREL and then respond with PUBCOMP (in `ackPubrel`)
    private func ackPublish(_ packet: PublishPacket) {
        switch packet.message.qos {
        case .atMostOnce:
            self.onMessage?(packet.message)
        case .atLeastOnce:
            self.sendNoWait(packet.puback()).then { _ in
                self.onMessage?(packet.message)
            }
        case .exactlyOnce:
            self.sendPacket(packet.pubrec(),timeout: self.config.publishTimeout)
                .then { newpkg in
                    /// if we have received the PUBREL we can process the published message. `PUBCOMP` is sent by `ackPubrel`
                    if newpkg.type == .PUBREL {
                        return packet.message
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
                        return self.sendPacket(packet.pubrec(),timeout: self.config.publishTimeout)
                    }
                    throw err
                }
        }
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
        self.$passiveTasks.write { tasks in
            for ele in tasks{
                ele.value.done(with: error)
            }
            tasks = [:]
        }
        self.$activeTasks.write { tasks in
            for ele in tasks{
                ele.value.done(with: error)
            }
            tasks = [:]
        }
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
        guard let task = self.$activeTasks[packet.id] else{
            /// process packets where no equivalent task was found we only send response to v5 server
            if case .PUBREC = packet.type,case .v5_0 = self.config.version{
                self.sendNoWait(packet.pubrel(code: .packetIdentifierNotFound))
            }
            return
        }
        task.done(with: packet)
        self.$activeTasks[packet.id] = nil
    }
    private func donePassiveTask(with packet:Packet){
        guard let task = self.$passiveTasks[packet.id] else{
            /// process packets where no equivalent task was found we only send response to v5 server
            if case .PUBREL = packet.type,case .v5_0 = self.config.version{
                self.sendNoWait(packet.pubcomp(code: .packetIdentifierNotFound))
            }
            return
        }
        task.done(with: packet)
        self.$passiveTasks[packet.id] = nil
    }
}
//MARK: Core Implemention for OPEN/AUTH/CLOSE
extension MQTT.Socket{
    @discardableResult
    func open(_ packet: ConnectPacket,authflow: Authflow? = nil) -> Promise<ConnackPacket> {
        safe.lock(); defer { safe.unlock() }
        self.connPacket = packet
        self.authflow = authflow
        switch _status{
        case .opened,.opening:
            return .init(MQTTError.alreadyOpened)
        default:
            _status = .opening
            return connect()
        }
    }
    func auth(properties: Properties,authflow: Authflow? = nil) -> Promise<Auth> {
        guard case .opened = status else { return .init(MQTTError.noConnection) }
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
            Auth(code: $0.code, properties: $0.properties)
        }
    }
    func close(_ code:ResultCode.Disconnect = .normal,properties:Properties)->Promise<Void>{
        safe.lock(); defer { safe.unlock() }
        var packet:DisconnectPacket
        switch config.version {
        case .v5_0:
            packet = .init(code: code,properties: properties)
        case .v3_1_1:
            packet = .init(code: code)
        }
        switch _status{
        case .closing,.closed:
            return .init(MQTTError.alreadyClosed)
        case .opening:
            _status = .closed(.normalError(MQTTError.clientClosed(code)))
            return .init(())
        case .opened:
            _status = .closing
            return self.sendNoWait(packet).then{ _ in
                self.setStatus(.closed(.normalError(MQTTError.clientClosed(code))))
            }
        }
    }
    
    private func reAuth(packet: AuthPacket) -> Promise<AuthPacket> {
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
            authflow(packet.ack()).then{
                self.sendPacket($0.packet())
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
        let inflight = self.inflight
        self.$inflight.clear()
        inflight.forEach { packet in
            switch packet {
            case let publish as PublishPacket:
                let newpkg = PublishPacket( id: publish.id, message: publish.message.duplicate())
                _ = self.publish(packet: newpkg)
            case let newpkg as PubackPacket:
                _ = self.pubrel(packet: newpkg)
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
                let code = ResultCode.Connect(rawValue: connack.returnCode) ?? .unrecognisedReason
                throw MQTTError.connectFailed(.connect(code))
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
    func pubrel(packet: PubackPacket) -> Promise<Puback?> {
        guard case .opened = status else { return .init(MQTTError.noConnection) }
        self.$inflight.add(packet: packet)
        return self.sendPacket(packet,timeout: self.config.publishTimeout).then{
            guard $0.type != .PUBREC else {
                throw MQTTError.unexpectMessage
            }
            self.$inflight.remove(id: packet.id)
            guard let pubcomp = $0 as? PubackPacket,pubcomp.type == .PUBCOMP else{
                throw MQTTError.unexpectMessage
            }
            if pubcomp.code.rawValue > 0x7F {
                throw MQTTError.publishFailed(pubcomp.code)
            }
            return pubcomp.ack()
        }.catch { err in
            if case MQTTError.timeout = err{
                //Always try again when timeout
                return self.sendPacket(packet,timeout: self.config.publishTimeout)
            }
            throw err
        }
    }
    func publish(packet: PublishPacket) -> Promise<Puback?> {
        guard case .opened = status else { return .init(MQTTError.noConnection) }
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
        self.$inflight.add(packet: packet)
        return senPublish(packet:packet)
    }
    private func senPublish(packet:PublishPacket)->Promise<Puback?>{
        return self.sendPacket(packet,timeout: self.config.publishTimeout).then {pkg in
            self.$inflight.remove(id: packet.id)
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
        }.then {puback  in
            if puback.type == .PUBREC{
                return self.pubrel(packet: PubackPacket(id: puback.id,type: .PUBREL))
            }
            return Promise<Puback?>(puback.ack())
        }.catch { error in
            if case MQTTError.serverClosed(let ack) = error, ack == .malformedPacket{
                self.$inflight.remove(id: packet.id)
            }
            if case MQTTError.timeout = error{
                //Always try again when timeout
                return self.senPublish(packet:packet)
            }
            throw error
        }
    }
    func subscribe(packet: SubscribePacket) -> Promise<SubackPacket> {
        guard case .opened = status else { return .init(MQTTError.noConnection) }
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
        guard case .opened = status else { return .init(MQTTError.noConnection) }
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

extension Safely where Value == [Packet] {
    func clear(){
        self.write { values in
            values = []
        }
    }
    func add(packet: Packet) {
        self.write { pkgs in
            pkgs.append(packet)
        }
    }
    /// remove packert
    func remove(id: UInt16) {
        self.write { pkgs in
            guard let first = pkgs.firstIndex(where: { $0.id == id }) else { return }
            pkgs.remove(at: first)
        }
    }
}
