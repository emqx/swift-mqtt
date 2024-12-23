//
//  Socket.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Foundation
import Network
import Promise

final class Socket:@unchecked Sendable{
    internal let queue:DispatchQueue
    internal var retrier:Retrier?
    private let lock = Lock()
    private var nw:NWConnection?
    private let endpoint:NWEndpoint
    private let params:NWParameters
    private var pinging:Pinging?
    private var monitor:Monitor?
    private var allTasks:[UInt16:MQTT.Task] = [:]
    private var connTask:MQTT.Task?
    private var authTask:MQTT.Task?
    private var reader:Reader?
    private var retrying:Bool = false
    private var version:MQTT.Version = .v5_0
    private var openTask:Promise<Packet>?
    private var config:MQTT.Config?
    private var connProperties:Properties = .init()
    private var will:Message?
    init(_ version:MQTT.Version,endpoint:NWEndpoint,params:NWParameters ){
        self.version = version
        self.endpoint = endpoint
        self.params = params
        self.queue = DispatchQueue.init(label: "swift.mqtt.queue")
    }
    deinit {
        self.pinging?.suspend()
        self.nw?.forceCancel()
        self.nw = nil
    }
    var status:MQTT.Status = .closed(.success){
        didSet{
            if oldValue != status {
                MQTT.Logger.debug("Status changed: \(oldValue) --> \(status)")
                switch status{
                case .opened:
                    self.retrier?.reset()
                    self.pinging?.resume()
                case .closed:
                    self.retrier?.reset()
                    self.pinging?.suspend()
                    self.nw = nil
                    if let task = self.openTask{
                        task.done(MQTTError.connectionError(.accepted))
                    }
                    self.openTask = nil
                case .opening:
                    self.pinging?.suspend()
                case .closing:
                    self.pinging?.suspend()
                }
                self.notify(status: status, old: oldValue)
            }
        }
    }
    func open(config:MQTT.Config,properties:Properties = .init() ,will:Message? = nil)->Promise<Packet>{
        self.lock.lock(); defer { self.lock.unlock() }
        switch self.status{
        case .opened:
            return .init(MQTTError.alreadyConnected)
        case .opening:
            return .init(MQTTError.alreadyConnecting)
        default:
            break
        }
        self.config = config
        self.connProperties = properties
        self.will = will
        
        self.status = .opening
        self.resume()
        let promise = Promise<Packet>()
        self.openTask = promise
        return promise
    }
    private func reopen(){
        self.lock.lock(); defer { self.lock.unlock() }
        switch self.status{
        case .opened:
            return
        case .opening:
            return
        default:
            break
        }
        self.status = .opening
        self.resume()
    }
    /// Close network connection diirectly
    func directClose(_ code:ReasonCode = .success,reason:MQTT.CloseReason? = nil){
        self.lock.lock(); defer { self.lock.unlock() }
        switch self.status{
        case .closing,.closed:
            return
        default:
            break
        }
        self.tryClose(code: code, reason: reason)
//        switch self.conn?.state{
//        case .ready,.canceling:
//            self.tryClose(code: code, reason: reason)
//        default:
//            if let scode = code.server{
//                self.status = .closing
//                self.conn?.cancel()
//            }else{
//                self.tryClose(code: code, reason: reason)
//            }
//        }
    }
    private func handle(state:NWConnection.State){
        switch state{
        case .cancelled:
            self.status = .closed(.success)
        case .failed(let error):
            self.tryClose(code: .unspecifiedError, reason: .error(error))
        case .ready://wen network ready send connect frame
            self.doReady()
        case .preparing:
            self.status = .opening
        case .setup:
            self.status = .closed(.success)
        case .waiting(let error):
            switch error{
            case .dns(let type):
                print("dns type:",type)
            case .posix(let code):
                print("posix code:",code)
            case .tls(let status):
                print("tls status:",status)
            @unknown default:
                print("@unknown error")
            }
            print(error)
//            Logger.debug("connection wating error = \(error.debugDescription)")
//            self.tryClose(code: .unspecifiedError, reason: .error(error))
        @unknown default:
            break
        }
    }
    private func doReady(){
        guard let config else{
            return
        }
        let packet = ConnectPacket.init(
            cleanSession: config.cleanSession,
            keepAliveSeconds: config.keepAlive,
            clientId: config.clientId,
            username: config.username,
            password: config.password,
            properties: self.connProperties,
            will: self.will)
        
        self.sendPacket(packet).then { packet in
            self.connTask?.done(with: packet)
            self.connTask = nil
            guard let connack = packet as? ConnackPacket else {
                return
            }
            if connack.returnCode == 0{
                self.status = .opened
            }
        }
        self.reader?.start()
    }
    /// Internal method run in delegate queue
    /// try close when no need retry
    private func tryClose(code:ReasonCode,reason:MQTT.CloseReason?){
        MQTT.Logger.debug("Try close code:\(code),reason:\(reason.debugDescription)")
        if self.retrying{
            return
        }
        // not retry when network unsatisfied
        if let monitor = self.monitor, monitor.status == .unsatisfied{
            status = .closed(code,reason)
            return
        }
        // not retry when reason is nil(close no reason)
        guard let reason else{
            status = .closed(code, nil)
            return
        }
        // not retry when retrier is nil
        guard let retrier = self.retrier else{
            status = .closed(code,reason)
            return
        }
        // not retry when limits
        guard let delay = retrier.retry(when: reason, code: code) else{
            status = .closed(code,reason)
            return
        }
        self.retrying = true
        self.status = .opening
        self.queue.asyncAfter(deadline: .now() + delay){
            self.resume()
            self.retrying = false
        }
    }
    private func resume(){
        let conn = NWConnection(to: endpoint, using: params)
        conn.stateUpdateHandler = {state in
            self.handle(state: state)
        }
        conn.start(queue: queue)
        self.nw = conn
        self.reader = Reader(self, conn: conn, version: version)
    }
    private func notify(status:MQTT.Status,old:MQTT.Status){
//        self.queue.async {
//            self.delegate?.mqtt(self, didUpdate: status,prev: old)
//        }
    }
    private func notify(error:Error){
//        self.queue.async {
//            self.delegate?.mqtt(self, didReceive: error)
//        }
    }
}
extension Socket{
    func updatePing(){
        guard let config else{
            return
        }
        self.pinging = Pinging(self, timeout: config.pingTimeout, interval: TimeInterval(config.keepAlive))
        self.pinging?.resume()
    }
    func usingMonitor(_ enable:Bool){
        guard enable else{
            self.monitor?.stop()
            self.monitor = nil
            return
        }
        let monitor = self.monitor ?? newMonitor()
        monitor.start(queue: queue)
    }
    private func newMonitor()->Monitor{
        let m = Monitor{[weak self] new in
            guard let self else { return }
            switch new{
            case .satisfied:
                if case let .closed(_, reason) = self.status, reason != nil{
                    self.reopen()
                }
            case .unsatisfied:
                self.directClose(reason: .monitor)
            default:
                break
            }
        }
        self.monitor = m
        return m
    }
}
extension Socket{
    @discardableResult
    func sendNoWait(_ packet: Packet,timeout:UInt64 = 5000)->Promise<Void> {
        do {
            MQTT.Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: version, to: &buffer)
            return self.send(data: buffer.data, timeout: timeout)
        } catch {
            return Promise<Void>(error)
        }
    }
    @discardableResult
    func sendPacket(_ packet: Packet,timeout:UInt64 = 5000)->Promise<Packet> {
        guard self.status == .opened || packet.type == .CONNECT else{
            return .init(MQTTError.noConnection)
        }
        let task = MQTT.Task(packet)
        switch packet.type{
        case .CONNECT:
            self.connTask = task
        case .AUTH:
            self.authTask = task
        default:
            if packet.id>0{
                self.allTasks[packet.id] = task
            }
        }
        do {
            MQTT.Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: version, to: &buffer)
            self.send(data: buffer.data, timeout: timeout)
        } catch {
            return .init(error)
        }
        return task.promise
    }
    @discardableResult
    private func send(data:Data,timeout:UInt64 = 5000)->Promise<Void>{
        guard let conn = self.nw else{
            return .init(MQTTError.noConnection)
        }
        let promise = Promise<Void>()
        conn.send(content: data,contentContext: .default(timeout: timeout), completion: .contentProcessed({ error in
            if let error{
                MQTT.Logger.error("socket send \(data.count) bytes failed. error:\(error)")
                promise.done(error)
            }else{
                promise.done(())
            }
        }))
        return promise
    }
}
extension Socket:ReaderDelegate{
    func readCompleted(_ reader: Reader) {
        
    }
    func reader(_ reader: Reader, didReceive error: any Error) {
        MQTT.Logger.debug("RECV: \(error)")
    }
    func reader(_ reader: Reader, didReceive packet: any Packet) {
        MQTT.Logger.debug("RECV: \(packet)")
        switch packet.type{
        case .DISCONNECT:
            self.tryClose(code: (packet as! DisconnectPacket).reason , reason: .server)
        case .AUTH:
            if let task = self.authTask{
                task.done(with: packet)
                self.authTask = nil
            }else if let task = self.connTask{
                task.done(with: packet)
                self.connTask = nil
            }
        case .CONNACK:
            if let task = self.connTask{
                task.done(with: packet)
                self.connTask = nil
            }
        case .PINGREQ:
            self.pinging?.onPong()
        default:
            guard let task = self.allTasks[packet.id] else{
                return
            }
            task.done(with: packet)
            self.allTasks.removeValue(forKey: packet.id)
        }
    }
}

extension Socket{
    /// connection parameters. Limits set by either client or server
    struct Params{
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
