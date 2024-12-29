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
    internal var retrier:MQTT.Retrier?
    internal var statusChanged:(((new:MQTT.Status,old:MQTT.Status))->Void)?
    internal var onMessage:((MQTT.Message)->Void)?
    private let lock = Lock()
    private var nw:NWConnection?
    private let endpoint:MQTT.Endpoint
    private var pinging:MQTT.Pinging?
    private var monitor:MQTT.Monitor?
    private var activeTasks:[UInt16:MQTT.Task] = [:] // active workflow tasks
    private var passiveTasks:[UInt16:MQTT.Task] = [:] // passive workflow tasks
    private var connTask:MQTT.Task?
    private var authTask:MQTT.Task?
    private var reader:Reader?
    private var retrying:Bool = false
    private var openTask:Promise<Packet>?
    private let config:MQTT.Config
    private var version:MQTT.Version { config.version }
    
    private var packet:ConnectPacket?
    init(_ config:MQTT.Config,endpoint:MQTT.Endpoint){
        self.config = config
        self.endpoint = endpoint
        self.queue = DispatchQueue.init(label: "swift.mqtt.queue")
        if config.pingEnabled{
            self.pinging = MQTT.Pinging(self, timeout: config.pingTimeout, interval: .init(config.keepAlive))
        }
    }
    deinit {
        self.pinging?.suspend()
        self.nw?.forceCancel()
        self.nw = nil
    }
    var status:MQTT.Status = .closed(.normalClose){
        didSet{
            if oldValue != status {
                MQTT.Logger.debug("Status changed: \(oldValue) --> \(status)")
                switch status{
                case .opened:
                    self.retrier?.reset()
                    self.pinging?.resume()
                case .closed(let reason):
                    self.retrier?.reset()
                    self.pinging?.suspend()
                    self.nw = nil
                    if let task = self.openTask{
                        switch reason{
                        case .networkError(let error):
                            task.done(error)
                        case .connectFail(let code):
                            task.done(MQTTError.connectionError(code))
                        case .disconnect(let code, _):
                            task.done(MQTTError.reasonError(code))
                        default:
                            task.done(MQTTError.failedToConnect)
                        }
                    }
                    self.openTask = nil
                    self.nw?.cancel()
                    self.nw = nil
                case .opening:
                    self.pinging?.suspend()
                case .closing:
                    self.pinging?.suspend()
                }
                self.statusChanged?((new:status,old:oldValue))
            }
        }
    }
    func open(packet:ConnectPacket)->Promise<Packet>{
        self.lock.lock(); defer { self.lock.unlock() }
        switch self.status{
        case .opened:
            return .init(MQTTError.alreadyConnected)
        case .opening:
            return .init(MQTTError.alreadyConnecting)
        default:
            break
        }
        self.packet = packet
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
    /// Called by the underlying `NWConnection` when its internal state has changed.
    private func handle(state:NWConnection.State){
        switch state{
        case .cancelled:
            // This is the network telling us we're closed. We don't need to actually do anything here
            // other than check our state is ok.
            self.status = .closed(.normalClose)
        case .failed(let error):
            // The connection has failed for some reason.
            self.tryClose(reason: .networkError(error))
        case .ready:
            // Transitioning to ready means the connection was succeeded. Hooray!
            self.doReady()
        case .preparing:
            // This just means connections are being actively established. We have no specific action
            // here.
            self.status = .opening
        case .setup:
            /// inital state
            self.status = .closed(.normalClose)
        case .waiting(let error):
            if case .opening = self.status {
                // This means the connection cannot currently be completed. We should notify the pipeline
                // here, or support this with a channel option or something, but for now for the sake of
                // demos we will just allow ourselves into this stage.tage.
                // But let's not worry about that right now. so noting happend
            }
            // In this state we've transitioned into waiting, presumably from active or closing. In this
            // version of NIO this is an error, but we should aim to support this at some stage.
            MQTT.Logger.debug("connection wating error = \(error.debugDescription)")
            self.tryClose(reason: .networkError(error))
        default:
            // This clause is here to help the compiler out: it's otherwise not able to
            // actually validate that the switch is exhaustive. Trust me, it is.
            fatalError("Unreachable")
        }
    }
        
    private func doReady(){
        guard let packet else{
            return
        }
        self.sendPacket(packet).then { packet in
            self.openTask?.done(packet)
            self.openTask = nil
            guard let connack = packet as? ConnackPacket else {
                return
            }
            if connack.returnCode == 0{
                self.status = .opened
            }
        }
        self.reader?.start()
    }
    /// Close network connection diirectly
    func directClose(reason:MQTT.CloseReason){
        self.lock.lock(); defer { self.lock.unlock() }
        switch self.status{
        case .opened,.opening:
            if case .ready = self.nw?.state{
                self.status = .closing
                self.nw?.cancel()
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
        MQTT.Logger.debug("Try close reason:\(reason.debugDescription)")
        if self.retrying{
            return
        }
        // not retry when reason is nil(close no reason)
        guard let reason else{
            status = .closed(.normalClose)
            return
        }
        // posix network unreachable
        // check your borker address is reachable
        // the monitor just known internet is reachable
        if case .networkError(let err) = reason,case .posix(let posix) = err{
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
        // not retry when limits
        guard let delay = retrier.retry(when: reason) else{
            status = .closed(reason)
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
        let params = endpoint.params()
        let conn = NWConnection(to: params.0, using: params.1)
        conn.stateUpdateHandler = self.handle(state:)
        conn.start(queue: queue)
        self.nw = conn
        self.reader = Reader(self, conn: conn, version: version)
    }
}
extension Socket{
    func resetPing(){
        self.pinging = MQTT.Pinging(self, timeout: config.pingTimeout, interval: TimeInterval(config.keepAlive))
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
    private func newMonitor()->MQTT.Monitor{
        let m = MQTT.Monitor{[weak self] new in
            guard let self else { return }
            switch new{
            case .satisfied:
                if case .closed = self.status{
                    self.reopen()
                }
            case .unsatisfied:
                self.directClose(reason: .unsatisfied)
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
        guard self.status == .opened else{
            return Promise<Void>(MQTTError.noConnection)
        }
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
            return Promise<Packet>(MQTTError.noConnection)
        }
        let task = MQTT.Task(packet)
        switch packet.type{
        case .CONNECT: /// send `CONNECT` is active workflow but packetId is zero
            self.connTask = task
        case .AUTH: /// send `AUTH` is active workflow but packetId is zero
            self.authTask = task
        case .PUBREC: /// send `PUBREC` is passive workflow so put it into `passiveTasks`
            self.passiveTasks[packet.id] = task
        ///send  these packets  is active workflow so put it into `passiveTasks`
        case .PUBLISH,.PUBREL,.SUBSCRIBE,.UNSUBSCRIBE:
            self.activeTasks[packet.id] = task
        case .PUBACK,.PUBCOMP: /// send `PUBACK` `PUBCOMP` is passive workflow but we will `sendNoWait` so error here
            break
        case .PINGREQ,.DISCONNECT: /// send `PINGREQ` `DISCONNECT` is active workflow but we will `sendNoWait` so error here
            break
        case .CONNACK,.SUBACK,.UNSUBACK,.PINGRESP: ///client never send them
            break
        }
        do {
            MQTT.Logger.debug("SEND: \(packet)")
            var buffer = DataBuffer()
            try packet.write(version: version, to: &buffer)
            return self.send(data: buffer.data, timeout: timeout).then { _ in
                return task.start(timeout)
            }
        } catch {
            return Promise<Packet>(error)
        }
        
    }
    @discardableResult
    private func send(data:Data,timeout:UInt64)->Promise<Void>{
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
            self.sendPacket(PubackPacket(id:pubpkg.id,type: .PUBREC))
                .then { newpkg in
                    // if we have received the PUBREL we can process the published message. PUBCOMP is sent by `ackPubrel`
                    if newpkg.type == .PUBREL {
                        return pubpkg.message
                    }
                    if  let _ = (newpkg as? PublishPacket)?.message {
                        // if we receive a publish message while waiting for a PUBREL from broker
                        // then replace data to be published and retry PUBREC. PUBREC is sent by self `ackPublish`
                        // but there wo do noting because task will be replace by the same packetId
                        // so never happen here
                    }
                    throw MQTTError.unexpectedMessage
                }
                .then{ msg in
                    self.onMessage?(msg)
                }
        }
    }

    

    func readCompleted(_ reader: Reader) {
        self.directClose(reason: .normalClose)
    }
    func reader(_ reader: Reader, didReceive error: any Error) {
        MQTT.Logger.debug("RECV: \(error)")
    }
    func reader(_ reader: Reader, didReceive packet: any Packet) {
        MQTT.Logger.debug("RECV: \(packet)")
        switch packet.type{
        //----------------------------------no need callback--------------------------------------------
        case .PINGRESP:
            self.pinging?.onPong()
        case .DISCONNECT:
            let disconnect = packet as! DisconnectPacket
            self.tryClose(reason: .disconnect(disconnect.reason,disconnect.properties))
        //----------------------------------need callback by packet type----------------------------------
        case .CONNACK:
            self.doneConnTask(with: packet)
        case .AUTH:
            self.doneAuthTask(with: packet)
        // --------------------------------need callback by packetId-------------------------------------
        case .PUBLISH:
            self.ackPublish(packet as! PublishPacket)
            self.donePassiveTask(with: packet)
        case .PUBREL:
            self.ackPubrel(packet as! PubackPacket)
            self.donePassiveTask(with: packet)
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
        case .CONNECT, .SUBSCRIBE, .UNSUBSCRIBE, .PINGREQ:
            // MQTTError.unexpectedMessage
            MQTT.Logger.error("Unexpected MQTT Message:\(packet)")
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
        guard let task = self.activeTasks[packet.id] else{
            /// process packets where no equivalent task was found we only send response to v5 server
            if case .PUBREC = packet.type,case .v5_0 = self.config.version{
                self.sendNoWait(PubackPacket(id:packet.id,type: .PUBREL, reason: .packetIdentifierNotFound))
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
                self.sendNoWait(PubackPacket(id:packet.id,type: .PUBCOMP, reason: .packetIdentifierNotFound))
            }
            return
        }
        task.done(with: packet)
        self.passiveTasks.removeValue(forKey: packet.id)
    }
}

extension NWConnection.ContentContext{
    static func `default`(timeout:UInt64)->NWConnection.ContentContext{
        return .init(identifier: "swift-mqtt",expiration: timeout)
    }
}

