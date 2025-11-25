//
//  Client.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation
import Network

public struct Identity:Sendable{
    /// MQTT client id it will be send in `CONNECT` Packet
    public internal(set) var clientId:String
    /// MQTT client username it will be send in `CONNECT` Packet
    public let username:String?
    /// MQTT  client password it will be send in `CONNECT` Packet
    public let password:String?
    public init(_ clientId: String = UUID().uuidString, username: String? = nil, password: String? = nil) {
        self.clientId = clientId
        self.username = username
        self.password = password
    }
}

/// Auth workflow
public typealias Authflow = (@Sendable (Auth) -> Promise<Auth>)

public protocol MQTTDelegate:AnyObject,Sendable{
    func mqtt(_ mqtt: MQTTClient, didUpdate status:Status, prev :Status)
    func mqtt(_ mqtt: MQTTClient, didReceive message:Message)
    func mqtt(_ mqtt: MQTTClient, didReceive error:Error)
}
open class MQTTClient:@unchecked Sendable{
    ///client configuration
    /// - Note: It not thread safe. please config it before client working
    public let config:Config
    /// readonly mqtt client connection status
    /// mqtt client version
    public var version:Version { config.version }
    /// readonly
    public var isOpened:Bool { status == .opened }
    /// network endpoint
    public let endpoint:Endpoint
    /// message delegate
    /// - Note: It not thread safe. please config it before client working
    public weak var delegate:MQTTDelegate?
    /// current mqtt client identity . It  will be set affter `client.open(_ identity:)`
    public internal(set)var identity:Identity?
    /// The delegate and observers callback queue
    /// By default use internal task queue.  change it for custom
    /// - Note: It not thread safe. please config it before client working
    public var delegateQueue:DispatchQueue
    //--- private zone
    /// internal async task process queue
    private let queue:DispatchQueue
    /// internal socket instance
    private let socket:Socket
    //--- Keep safely by sharing a same status lock ---
    private let safe = Safely()//status safe lock
    private var retrying:Bool = false
    private var authflow:Authflow?
    private var connPacket:ConnectPacket?
    private var connParams:ConnectParams = .init()
    //--- Keep safely themself ---
    @Safely private var notify:NotificationCenter?//it will auto create when some observer has been added
    @Safely private var pinging:Pinging?//not nil after client become opened. Of course,the config.pingEnable must be true.
    @Safely private var retrier:Retrier?//not nil after startRetrier.
    @Safely private var monitor:Monitor?//not nil after startMonitor.
    @Safely private var packetId:UInt16 = 0//auto-increment safely
    @Safely private var connTask:MQTTTask?//current connection task
    @Safely private var authTask:MQTTTask?//current auth task
    @Safely private var pingTask:MQTTTask?//current pinging task
    @Safely private var inflight:[UInt16:Packet] = [:]// inflight messages
    @Safely private var activeTasks:[UInt16:MQTTTask] = [:] // active workflow tasks
    @Safely private var passiveTasks:[UInt16:MQTTTask] = [:] // passive workflow tasks
    
    /// Initial mqtt  client object
    ///
    /// - Parameters:
    ///   - clientID: Client Identifier
    ///   - endpoint:The network endpoint
    ///   - version: The mqtt client version
    public init(_ endpoint:Endpoint,version:Version){
        let config = Config(version)
        let queue = DispatchQueue(label: "mqtt.client.queue",qos: .default,attributes: .concurrent)
        self.config = config
        self.queue = queue
        self.delegateQueue = queue
        self.endpoint = endpoint
        self.socket = Socket(endpoint: endpoint, config: config)
        self.socket.delegate = self
    }
    deinit {
        retrier?.stop()
        monitor?.stop()
        stopPing()
    }
    
    /// Start the auto reconnect mechanism
    ///
    /// - Parameters:
    ///    - policy: Retry policcy
    ///    - limits: max retry times
    ///    - filter: filter retry when some reason,  return `true` if retrying are not required
    ///
    public func startRetrier(_ policy:Retrier.Policy = .exponential(),limits:UInt = 10,filter:Retrier.Filter? = nil){
        retrier = Retrier(policy, limits: limits, filter: filter)
    }
    ///  Stop the auto reconnect mechanism
    public func stopRetrier(){
        retrier = nil
    }
    /// Enable the network mornitor mechanism
    ///
    public func startMonitor(){
        setMonitor(true)
    }
    /// Disable the network mornitor mechanism
    ///
    public func stopMonitor(){
        setMonitor(false)
    }
    /// current client status
    public private(set) var status:Status{
        get {
            safe.lock(); defer{ safe.unlock() }
            return _status
        }
        set {
            safe.lock();  defer{ safe.unlock() }
            _status = newValue
        }
    }
    private var _status:Status = .closed(){
        didSet{
            if oldValue == _status { return }
            Logger.debug("STATUS: \(oldValue) --> \(_status)")
            defer{
                notify(status: _status, old: oldValue)
            }
            switch _status{
            case .opened:
                starPing()
                retrier?.stop()
            case .opening:
                stopPing()
            case .closing:
                stopPing()
            case .closed(let reason):
                socket.stop()
                stopPing()
                retrier?.stop()
                guard let task = self.connTask else{ return }
                switch reason{
                case .mqttError(let error):
                    task.done(with: error)
                case .otherError(let error):
                    task.done(with: error)
                case .networkError(let error):
                    task.done(with: error)
                case .clientClose(let code):
                    task.done(with: MQTTError.clientClose(code))
                case .serverClose(let code):
                    task.done(with: MQTTError.serverClose(code))
                default:
                    task.done(with:MQTTError.connectFailed())
                }
                connTask = nil
            }
            
        }
    }
}

extension MQTTClient{
    /// Internal method run in delegate queue
    /// try close when no need retry
    private func tryClose(reason:CloseReason?){
        safe.lock(); defer{ safe.unlock() }
        if self.retrying{
            return
        }
        Logger.debug("RETRY: START reason is \(reason == nil ? "nil" : reason!.description)")
        if case .closed = _status{
            return
        }
        if case .closing = _status{
            return
        }
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
        guard let delay = retrier.delay(when: reason) else{
            _status = .closed(reason)
            return
        }
        // not retry when no prev conn packet
        guard let connPacket else{
            _status = .closed(reason)
            return
        }
        // close prev socket and prepare to reconnect
        socket.stop()
        // not clean session when auto reconnection
        if connPacket.cleanSession{
            self.connPacket = connPacket.copyNotClean()
        }
        retrying = true
        _status = .opening
        Logger.debug("RETRY: OK! will reconnect after \(delay) seconds")
        retrier.retry(in: queue,after: delay) {[weak self] in
            if let self{
                self.connect()
                self.retrying = false
            }
        }
    }
    @discardableResult
    func connect() -> Promise<ConnackPacket> {
        guard let packet = self.connPacket else{
            return .init(MQTTError.connectFailed())
        }
        socket.start()
        return self.sendPacket(packet).then { packet in
            switch packet {
            case let connack as ConnackPacket:
                try self.processConnack(connack)
                self.status = .opened
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
                        self.status = .opened
                        return packet
                    }
                    throw MQTTError.unexpectMessage
                }
            default:
                throw MQTTError.unexpectMessage
            }
        }.catch { error in
            self.tryClose(reason: .init(error: error))
        }
    }
}
// MARK: Ping Pong  Retry Monitor
extension MQTTClient{
    func setMonitor(_ enable:Bool){
        self.$monitor.write { monitor in
            if !enable {
                if monitor != nil{
                    monitor?.stop()
                    monitor = nil
                }
                return
            }
            if monitor == nil{
                monitor = Monitor{[weak self] new in
                    guard let self else { return }
                    switch new{
                    case .satisfied:
                        self.monitorConnect()
                    case .unsatisfied:
                        self.status = .closed(.unsatisfied)
                    default:
                        break
                    }
                }
            }
            monitor?.start()
        }
    }
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
    
    private func starPing(){
        if config.pingEnabled{
            pinging = Pinging(client: self)
            pinging?.start()
        }
    }
    private func stopPing(){
        self.pinging?.stop()
        self.pingTask?.cancelTimeout()
        self.pingTask = nil
        self.pinging = nil
    }
    func pingTimeout(){
        tryClose(reason: .pingTimeout)
    }
}

extension MQTTClient{
    @discardableResult
    private func sendNoWait(_ packet: Packet)->Promise<Void> {
        do {
            Logger.debug("SEND: \(packet)")
            pinging?.update()
            var buffer = DataBuffer()
            try packet.write(version: config.version, to: &buffer)
            self.pinging?.update()
            return socket.send(data: buffer.data).then { _ in }
        } catch {
            return .init(error)
        }
    }
    @discardableResult
    private func sendPacket(_ packet: Packet,timeout:TimeInterval? = nil)->Promise<Packet> {
        let task = MQTTTask()
        switch packet.type{
        case .AUTH: /// send `AUTH` is active workflow but packetId is 0
            self.authTask = task
        case .CONNECT: /// send `CONNECT` is active workflow but packetId is 0
            self.connTask = task
        case .PINGREQ:/// send `PINGREQ` is active workflow but packetId is 0
            self.pingTask = task
        case .PUBREC: /// send `PUBREC` is passive workflow so put it into `passiveTasks`
            self.passiveTasks[packet.id] = task
        ///send  these packets  is active workflow so put it into `passiveTasks`
        case .PUBLISH,.PUBREL,.SUBSCRIBE,.UNSUBSCRIBE:
            self.activeTasks[packet.id] = task
        case .PUBACK,.PUBCOMP: /// send `PUBACK` `PUBCOMP` is passive workflow but we will `sendNoWait`.  so error here
            break
        case .DISCONNECT: /// send `DISCONNECT` is active workflow but we will `sendNoWait`.  so error here
            break
        case .CONNACK,.SUBACK,.UNSUBACK,.PINGRESP: ///client never send them
            break
        }
        do {
            Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: config.version, to: &buffer)
            self.pinging?.update()
            return socket.send(data: buffer.data).then { _ in
                return task.start(in: self.queue,timeout:timeout)
            }
        } catch {
            return .init(error)
        }
    }
}

// MARK: Socket Delegate
extension MQTTClient:SocketDelegate{
    func socket(_ socket: Socket, didReceive packet: any Packet) {
        Logger.debug("RECV: \(packet)")
        switch packet.type{
        //----------------------------------no need callback--------------------------------------------
        case .PINGRESP:
            self.donePingTask(with: packet)
        case .DISCONNECT:
            let disconnect = packet as! DisconnectPacket
            self.clearAllTask(with: MQTTError.serverClose(disconnect.code))
            self.tryClose(reason: .serverClose(disconnect.code))
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
            Logger.error("Unexpected MQTT Message:\(packet)")
        }
    }
    func socket(_ socket: Socket, didReceive error: any Error) {
        Logger.error("RECV: \(error)")
        self.clearAllTask(with: error)
        self.tryClose(reason: .init(error: error))
        self.notify(error: error)
    }
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
            self.notify(message: packet.message)
        case .atLeastOnce:
            self.sendNoWait(packet.puback()).then { _ in
                self.notify(message: packet.message)
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
                    self.notify(message: msg)
                }.catch { err in
                    if case MQTTError.timeout = err{
                        //Always try again when timeout
                        return self.sendPacket(packet.pubrec(),timeout: self.config.publishTimeout)
                    }
                    throw err
                }
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
    private func donePingTask(with packet:Packet){
        if let task = self.pingTask{
            task.done(with: packet)
            self.pingTask = nil
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
extension MQTTClient{
    func ping()->Promise<Void>{
        self.sendPacket(PingreqPacket(),timeout: config.pingTimeout).then { _ in }
    }
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
        guard case .opened = status else { return .init(MQTTError.unconnected) }
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
    func _close(_ code:ResultCode.Disconnect = .normal,properties:Properties)->Promise<Void>{
        var packet:DisconnectPacket
        switch config.version {
        case .v5_0:
            packet = .init(code: code,properties: properties)
        case .v3_1_1:
            packet = .init(code: code)
        }
        safe.lock();defer { safe.unlock() }
        switch _status{
        case .closing,.closed:
            return .init(MQTTError.alreadyClosed)
        case .opening:
            _status = .closed(.mqttError(MQTTError.clientClose(code)))
            return .init(())
        case .opened:
            _status = .closing
            return self.sendNoWait(packet).map{ _ in
                self.status = .closed(.mqttError(MQTTError.clientClose(code)))
                return .success(())
            }
        }
    }
    func nextPacketId() -> UInt16 {
        return $packetId.write { id in
            if id == UInt16.max {  id = 0 }
            id += 1
            return id
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
            authflow(packet.ack())
                .then{
                    self.sendPacket($0.packet())
                }
                .then{
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
            switch packet.value {
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
            // client identifier
            case .assignedClientIdentifier(let identifier):
                self.identity?.clientId = identifier
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
extension MQTTClient {
    func pubrel(packet: PubackPacket) -> Promise<Puback?> {
        guard case .opened = status else { return .init(MQTTError.unconnected) }
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
        guard case .opened = status else { return .init(MQTTError.unconnected) }
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
        }.then { puback  in
            if puback.type == .PUBREC{
                return self.pubrel(packet: PubackPacket(id: puback.id,type: .PUBREL))
            }
            return Promise<Puback?>(puback.ack())
        }.catch { error in
            if case MQTTError.serverClose(let ack) = error, ack == .malformedPacket{
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
        guard case .opened = status else { return .init(MQTTError.unconnected) }
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
        guard case .opened = status else { return .init(MQTTError.unconnected) }
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
/// connection parameters. Limits set by either client or server
struct ConnectParams:Sendable{
    var maxQoS: MQTTQoS = .exactlyOnce
    var maxPacketSize: Int?
    var retainAvailable: Bool = true
    var maxTopicAlias: UInt16 = 65535
}

extension Safely where Value == [UInt16:Packet] {
    func clear(){
        self.write { values in
            values = [:]
        }
    }
    func add(packet: Packet) {
        self.write { pkgs in
            pkgs[packet.id] = packet
        }
    }
    /// remove packert
    func remove(id: UInt16) {
        self.write { pkgs in
            pkgs.removeValue(forKey: id)
        }
    }
}
//MARK: Delegate implmention
public enum ObserverType:String,CaseIterable{
    case error = "mqtt.observer.error"
    case status = "mqtt.observer.status"
    case message = "mqtt.observer.message"
    var notifyName:Notification.Name{ .init(rawValue: rawValue) }
}
/// Quickly get mqtt parameters from the notification
public extension Notification{
    /// Parse mqtt message from `Notification` conveniently
    func mqttMesaage()->(client:MQTTClient,message:Message)?{
        guard let client = object as? MQTTClient else{
            return nil
        }
        guard let message = userInfo?["message"] as? Message else{
            return nil
        }
        return (client,message)
    }
    /// Parse mqtt status from `Notification` conveniently
    func mqttStatus()->(client:MQTTClient,new:Status,old:Status)?{
        guard let client = object as? MQTTClient else{
            return nil
        }
        guard let new = userInfo?["new"] as? Status else{
            return nil
        }
        guard let old = userInfo?["old"] as? Status else{
            return nil
        }
        return (client,new,old)
    }
    /// Parse mqtt error from `Notification` conveniently
    func mqttError()->(client:MQTTClient,error:Error)?{
        guard let client = object as? MQTTClient else{
            return nil
        }
        guard let error = userInfo?["error"] as? Error else{
            return nil
        }
        return (client,error)
    }
}

extension MQTTClient{
    /// Add observer for some type
    /// - Parameters:
    ///    - observer:the observer
    ///    - type: observer type
    ///    - selector: callback selector
    /// - Important:Note that this operation will strongly references `observer`. The observer must be removed when not in use. Don't add `self`. If really necessary please use `delegate`
    public func addObserver(_ observer:Any,for type:ObserverType,selector:Selector){
        if self.notify == nil {
            self.notify = NotificationCenter()
        }
        notify?.addObserver(observer, selector: selector, name: type.notifyName, object: self)
    }
    /// Remove some type of observer
    public func removeObserver(_ observer:Any,for type:ObserverType){
        notify?.removeObserver(observer, name: type.notifyName, object: self)
    }
    /// Remove all types of observer
    public func removeObserver(_ observer:Any){
        ObserverType.allCases.forEach {
            self.notify?.removeObserver(observer, name: $0.notifyName, object: self)
        }
    }
    func notify(message:Message){
        self.delegateQueue.async {[weak self] in
            guard let self else { return }
            self.delegate?.mqtt(self, didReceive: message)
            guard let notify = self.notify else{ return }
            let info:[String:Message] = ["message":message]
            notify.post(name: ObserverType.message.notifyName, object: self, userInfo: info)
        }
    }
    func notify(error:Error){
        self.delegateQueue.async {[weak self] in
            guard let self else { return }
            self.delegate?.mqtt(self, didReceive: error)
            guard let notify = self.notify else{ return }
            let info:[String:Error] = ["error":error]
            notify.post(name: ObserverType.error.notifyName, object: self, userInfo:info)
        }
    }
    func notify(status:Status,old:Status){
        self.delegateQueue.async {[weak self] in
            guard let self else { return }
            self.delegate?.mqtt(self, didUpdate: status, prev: old)
            guard let notify = self.notify else{ return }
            let info:[String:Status] = ["old":old,"new":status]
            notify.post(name: ObserverType.status.notifyName, object: self, userInfo: info)
        }
    }
}
