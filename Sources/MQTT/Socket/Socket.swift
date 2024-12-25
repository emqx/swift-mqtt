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
    internal var statusChanged:(((new:MQTT.Status,old:MQTT.Status))->Void)?
    internal var onMessage:((Message)->Void)?
    private let lock = Lock()
    private var nw:NWConnection?
    private let endpoint:NWEndpoint
    private let params:NWParameters
    private var pinging:Pinging?
    private var monitor:Monitor?
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
    init(_ config:MQTT.Config,endpoint:NWEndpoint,params:NWParameters ){
        self.config = config
        self.endpoint = endpoint
        self.params = params
        self.queue = DispatchQueue.init(label: "swift.mqtt.queue")
        if config.pingEnabled{
            self.pinging = Pinging(self, timeout: config.pingTimeout, interval: .init(config.keepAlive))
        }
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
//    func close(packet:DisconnectPacket)->Promise<Void>{
//        
//    }
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
            self.status = .closed(.success)
        case .failed(let error):
            // The connection has failed for some reason.
            self.tryClose(code: .unspecifiedError, reason: .error(error))
        case .ready:
            // Transitioning to ready means the connection was succeeded. Hooray!
            self.doReady()
        case .preparing:
            // This just means connections are being actively established. We have no specific action
            // here.
            self.status = .opening
        case .setup:
            self.status = .closed(.success)
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
            self.tryClose(code: .unspecifiedError, reason: .error(error))
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
        conn.stateUpdateHandler = self.handle(state:)
        conn.start(queue: queue)
        self.nw = conn
        self.reader = Reader(self, conn: conn, version: version)
    }
}
extension Socket{
    func resetPing(){
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
        case .PUBLISH,.PUBREL,.PINGREQ,.SUBSCRIBE,.UNSUBSCRIBE:
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
                    if  let newmsg = (newpkg as? PublishPacket)?.message {
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
        
    }
    func reader(_ reader: Reader, didReceive error: any Error) {
        MQTT.Logger.debug("RECV: \(error)")
    }
    func reader(_ reader: Reader, didReceive packet: any Packet) {
        switch packet.type{
        //----------------------------------no need callback--------------------------------------------
        case .PINGRESP:
            self.pinging?.onPong()
        case .DISCONNECT:
//            let disconnectMessage = packet as! DisconnectPacket
//            let ack = AckV5(reason: disconnectMessage.reason, properties: disconnectMessage.properties)
            self.tryClose(code: (packet as! DisconnectPacket).reason , reason: .server)
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
