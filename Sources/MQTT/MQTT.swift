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
    func mqtt(_ mqtt: MQTT, didReceive error:MQTTPublishInfo)
    func mqtt(_ mqtt: MQTT, didReceive error:Error)

}
/// MQTTDelegate
public protocol MQTTDelegate:AnyObject {
    ///
    func mqtt(_ mqtt: MQTT, didUpdate status:MQTT.Status,prev:MQTT.Status)
    ///
    func mqtt(_ mqtt: MQTT, didConnectAck ack: ConnAckReasonCode, connAckData: DecodeConnAck?)
    ///
    func mqtt(_ mqtt: MQTT, didPublishMessage message: MQTT.Message, id: UInt16)
    ///
    func mqtt(_ mqtt: MQTT, didPublishAck id: UInt16, pubAckData: DecodePubAck?)
    ///
    func mqtt(_ mqtt: MQTT, didPublishRec id: UInt16, pubRecData: DecodePubRec?)
    ///
    func mqtt(_ mqtt: MQTT, didReceiveMessage message: MQTT.Message, id: UInt16, publishData: DecodePublish?)
    ///
    func mqtt(_ mqtt: MQTT, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: DecodeSubAck?)
    ///
    func mqtt(_ mqtt: MQTT, didUnsubscribeTopics topics: [String], unsubAckData: DecodeUnsubAck?)
    ///
    func mqtt(_ mqtt: MQTT, didReceiveAuthReasonCode reasonCode: AuthReasonCode)
    /// socket did recevied error.
    /// Most of the time you don't have to care about this, because it's already taken care of internally
    func mqtt(_ mqtt:MQTT, didReceive error:Error)
    ///
    func mqtt(_ mqtt: MQTT, didPublishComplete id: UInt16,  pubCompData: DecodePubComp?)
    ///
    func mqttDidPing(_ mqtt: MQTT)
    ///
    func mqttDidReceivePong(_ mqtt: MQTT)
}

open class MQTT{
    private let endpoint:NWEndpoint
    private let params:NWParameters
    private let lock:NSLock = NSLock()
    internal let queue:DispatchQueue
    private let version:Version = .v5_0
    private let deliver = Deliver()
    
    private var publishCallbacks:[UInt16:Promise<MQTTAckV5>] = [:]
    private var subscribeCallbackss:[UInt16:Promise<MQTTSubackV5>] = [:]
    private var conn:NWConnection?
    private var retrying:Bool = false
    private var retrier:Retrier?
    private var pinging:Pinging?
    private var monitor:Monitor?
    private var reader:PacketReader?
    
    /// The subscribed topics in current communication
    private var subscriptions: [String:MQTTQos] = [:]
    private var subscriptionsWaitingAck: [UInt16:[Subscription]] = [:]
    private var unsubscriptionsWaitingAck: [UInt16:[Subscription]] = [:]
    private var sendingMessages: [UInt16: Message] = [:]
    private var _msgid: UInt16 = 0
    public var clientID: String
    public var username: String?
    public var password: String?
    public var cleanSession = true
    /// Setup a **Last Will Message** to client before connecting to broker
    public var willMessage: Message?
    public weak var delegate: MQTTDelegate?
    
    public class var logLevel:Logger.Level {
        get { Logger.minLevel }
        set { Logger.minLevel = newValue}
    }
    /// Re-deliver the un-acked messages
    public var deliverTimeout: Double {
        get { return deliver.retryTimeInterval }
        set { deliver.retryTimeInterval = newValue }
    }
    /// Message queue size. default 1000
    /// The new publishing messages of Qos1/Qos2 will be drop, if the queue is full
    public var messageQueueSize: UInt {
        get { return deliver.mqueueSize }
        set { deliver.mqueueSize = newValue }
    }
    /// In-flight window size. default 10
    public var inflightWindowSize: UInt {
        get { return deliver.inflightWindowSize }
        set { deliver.inflightWindowSize = newValue }
    }
    /// Keep alive time interval
    public var keepAlive: UInt16 = 60{
        didSet{
            assert(keepAlive>0, "The keepAlive value must be greater than 0!")
        }
    }
    /// 3.1.2.11 CONNECT Properties
    public var connectProperties: ConnectProperties?
    /// 3.15.2.2 AUTH Properties
    public var authProperties: AuthProperties?
    public var status:Status = .closed(.success){
        didSet{
            if oldValue != status {
                Logger.debug("Status changed: \(oldValue) --> \(status)")
                switch status{
                case .opened:
                    self.retrier?.reset()
                    self.pinging?.resume()
                case .closed:
                    self.retrier?.reset()
                    self.pinging?.suspend()
                    self.conn = nil
                case .opening:
                    self.pinging?.suspend()
                case .closing:
                    self.pinging?.suspend()
                }
                self.notify(status: status, old: oldValue)
            }
        }
    }
    /// Initial client object
    ///
    /// - Parameters:
    ///   - clientID: Client Identifier
    ///   - host: The MQTT broker host domain or IP address. Default is "localhost"
    ///   - port: The MQTT service port of host. Default is 1883
    public init(_ clientID: String, endpoint:NWEndpoint,params:NWParameters = .tls) {
        self.clientID = clientID
        self.endpoint = endpoint
        self.params = params
        self.queue = DispatchQueue.init(label: "swift.mqtt.queue")
        deliver.delegate = self
        if let storage = Storage() {
            storage.setMQTTVersion("5.0")
        } else {
            Logger.warning("Localstorage initial failed for key: \(clientID)")
        }
    }
    deinit {
        self.pinging?.suspend()
        self.conn?.forceCancel()
        self.conn = nil
    }
}
extension MQTT{
    public func open(){
        self.lock.lock(); defer { self.lock.unlock() }
        switch self.status{
        case .opening,.opened:
            return
        default:
            break
        }
        self.status = .opening
        self.resume()
    }
    /// Close  gracefully by sending close frame
    public func close(_ code:MQTTReasonCode = .success,properties:[String:String]? = nil){
        
        let packet = MQTTDisconnectPacket(reason: code)
//        if let properties{
//            frame.userProperties = properties
//        }
        self.send(packet)
    }
    /// Close network connection diirectly
    public func directClose(_ code:MQTTReasonCode = .success,reason:CloseReason? = nil){
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
    internal func send(_ frame: Frame,timeout:UInt64 = 5000, finish:((NWError?)->Void)? = nil) {
        Logger.debug("SEND: \(frame)")
        let data = frame.bytes(version: version.string)
        self.send(data: data, finish: finish)
    }
    internal func send(_ packet: MQTTPacket,timeout:UInt64 = 5000, finish:((NWError?)->Void)? = nil) {
        Logger.debug("SEND: \(packet)")
        var buffer = DataBuffer()
        try? packet.write(version: version, to: &buffer)
        self.send(data: buffer.data, finish: finish)
    }
    private func send(data:[UInt8],timeout:UInt64 = 5000,finish:((NWError?)->Void)? = nil){
        self.send(data: Data(bytes: data, count: data.count),finish: finish)
    }
    private func send(data:Data,timeout:UInt64 = 5000,finish:((NWError?)->Void)? = nil){
        guard let conn else{
            return
        }
        conn.send(content: data,contentContext: .default(timeout: timeout), completion: .contentProcessed({ error in
            if let error{
                Logger.error("socket send \(data.count) bytes failed. error:\(error)")
            }
            finish?(error)
        }))
    }
}
extension NWConnection.ContentContext{
    static func `default`(timeout:UInt64)->NWConnection.ContentContext{
        return .init(identifier: "swift-mqtt",expiration: timeout)
    }
}
extension MQTT{
    
    /// Enabling the  ping pong heartbeat mechanism
    ///
    /// - Parameters:
    ///    - policy: `Pinging.Policy` by default use `.standard`
    ///    - timeout: Ping pong timeout tolerance.
    ///    - interval: Ping pong time  interval.
    ///
    public func usingPinging(timeout:TimeInterval = 5)
    {
        self.pinging = Pinging(self, timeout: timeout, interval: TimeInterval(keepAlive))
    }
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
        self.retrier = Retrier(policy, limits: limits, filter: filter)
    }
    /// Enabling the network mornitor mechanism
    ///
    /// - Parameters:
    ///    - enable: use monitor or not.
    ///
    public func usingMonitor(_ enable:Bool = true){
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
                    self.open()
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

extension MQTT {
    
    @discardableResult
    public func publish(_ topic:String,payload:String,qos:MQTTQoS = .atLeastOnce, dup:Bool = false, retain:Bool = false,properties:MQTTProperties = [])->Promise<MQTTAckV5>{
        var buffer = DataBuffer()
        buffer.writeString(payload)
        let info = MQTTPublishInfo(qos: qos, retain: retain,dup: dup, topicName: topic, payload: buffer, properties: properties)
        let packet = MQTTPublishPacket(publish: info, packetId: nextMessageID())
        self.send(packet)
        let promise = Promise<MQTTAckV5>.init()
        self.publishCallbacks[packet.packetId] = promise
        return promise
    }
    
    @discardableResult
    public func publish(_ topic:String,payload:Data,qos:MQTTQoS = .atLeastOnce, dup:Bool = false, retain:Bool = false,properties:MQTTProperties = []) ->Promise<MQTTAckV5> {
        let info = MQTTPublishInfo(qos: qos, retain: retain,dup: dup, topicName: topic, payload: .init(data: payload), properties: properties)
        let packet = MQTTPublishPacket(publish: info, packetId: nextMessageID())
        self.send(packet)
        let promise = Promise<MQTTAckV5>.init()
        self.publishCallbacks[packet.packetId] = promise
        self.send(packet)
        return promise
    }
    
    public func subscribe(_ topic:String,qos:MQTTQoS = .atLeastOnce,properties:MQTTProperties = [])->Promise<MQTTSubackV5>{
        let info = MQTTSubscribeInfoV5(topicFilter: topic, qos: qos)
        let packet = MQTTSubscribePacket(subscriptions: [info], properties: properties, packetId: nextMessageID())
        let promise = Promise<MQTTSubackV5>.init()
        self.subscribeCallbackss[packet.packetId] = promise
        self.send(packet)
        return promise
    }
    public func subscribe(_ topics:[MQTTSubscribeInfoV5],properties:MQTTProperties = [])->Promise<MQTTSubackV5>{
        let packet = MQTTSubscribePacket(subscriptions: topics, properties: properties, packetId: nextMessageID())
        let promise = Promise<MQTTSubackV5>.init()
        self.subscribeCallbackss[packet.packetId] = promise
        self.send(packet)
        return promise
    }
    public func unsubscribe(_ topic:String,properties:MQTTProperties = []) -> Promise<MQTTSubackV5> {
        let packet = MQTTUnsubscribePacket(subscriptions: [topic], properties: properties, packetId: nextMessageID())
        let promise = Promise<MQTTSubackV5>.init()
        self.subscribeCallbackss[packet.packetId] = promise
        self.send(packet)
        return promise
    }
    public func unsubscribe(_ topics:[String],properties:MQTTProperties = []) -> Promise<MQTTSubackV5> {
        let packet = MQTTUnsubscribePacket(subscriptions: topics, properties: properties, packetId: nextMessageID())
        let promise = Promise<MQTTSubackV5>.init()
        self.subscribeCallbackss[packet.packetId] = promise
        self.send(packet)
        return promise
    }
    
    /// Publish a message to broker
    ///
    /// - Parameters:
    ///    - topic: Topic Name. It can not contain '#', '+' wildcards
    ///    - string: Payload string
    ///    - qos: Qos. Default is Qos1
    ///    - retained: Retained flag. Mark this message is a retained message. default is false
    ///    - properties: Publish Properties
    /// - Returns:
    ///     - 0 will be returned, if the message's qos is qos0
    ///     - 1-65535 will be returned, if the messages's qos is qos1/qos2
    ///     - -1 will be returned, if the messages queue is full
    @discardableResult
    public func publish(_ topic: String, withString string: String, qos: MQTTQos = .qos1, DUP: Bool = false, retained: Bool = false, properties: PublishProperties) -> Int {
        var fixQus = qos
        if !DUP{
            fixQus = .qos0
        }
        let message = Message(topic: topic, string: string, qos: fixQus, retained: retained)
        return publish(message, DUP: DUP, retained: retained, properties: properties)
    }

    /// Publish a message to broker
    ///
    /// - Parameters:
    ///   - message: Message
    ///   - properties: Publish Properties
    @discardableResult
    public func publish(_ message: Message, DUP: Bool = false, retained: Bool = false, properties: PublishProperties) -> Int {
        let msgid: UInt16

        if message.qos == .qos0 {
            msgid = 0
        } else {
            msgid = nextMessageID()
        }

        Logger.debug("message.topic \(message.topic )   = message.payload \(message.payload)")
        
        var frame = Publish(topic: message.topic,
                                 payload: message.payload,
                                 qos: message.qos,
                                 msgid: msgid)
        frame.qos = message.qos
        frame.dup = DUP
        frame.publishProperties = properties
        frame.retained = message.retained

        queue.async {
            self.sendingMessages[msgid] = message
        }
        // Push frame to deliver message queue
        guard deliver.add(frame) else {
            queue.async {
                self.sendingMessages.removeValue(forKey: msgid)
            }
            return -1
        }

        return Int(msgid)
    }

    /// Subscribe a `<Topic Name>/<Topic Filter>`
    ///
    /// - Parameters:
    ///   - topic: Topic Name or Topic Filter
    ///   - qos: Qos. Default is qos1
    public func subscribe(_ topic: String, qos: MQTTQos = .qos1) {
        let filter = Subscription(topic: topic, qos: qos)
        return subscribe([filter])
    }

    /// Subscribe a lists of topics
    ///
    /// - Parameters:
    ///   - topics: A list of tuples presented by `(<Topic Names>/<Topic Filters>, Qos)`
    public func subscribe(_ topics: [Subscription]) {
        let msgid = nextMessageID()
        let frame = Subscribe(msgid: msgid, subscriptionList: topics)
        send(frame)
        subscriptionsWaitingAck[msgid] = topics
    }

    /// Subscribe a lists of topics
    ///
    /// - Parameters:
    ///   - topics: A list of tuples presented by `(<Topic Names>/<Topic Filters>, Qos)`
    ///   - packetIdentifier: SUBSCRIBE Variable Header
    ///   - subscriptionIdentifier: Subscription Identifier
    ///   - userProperty: User Property
    public func subscribe(_ topics: [Subscription],  packetIdentifier: UInt16? = nil, subscriptionIdentifier: UInt32? = nil, userProperty: [String: String] = [:])  {
        let msgid = nextMessageID()
        let frame = Subscribe(msgid: msgid, subscriptionList: topics, packetIdentifier: packetIdentifier, subscriptionIdentifier: subscriptionIdentifier, userProperty: userProperty)
        send(frame)
        subscriptionsWaitingAck[msgid] = topics
    }

    /// Unsubscribe a Topic
    ///
    /// - Parameters:
    ///   - topic: A Topic Name or Topic Filter
    public func unsubscribe(_ topic: String) {
        let filter = Subscription(topic: topic)
        return unsubscribe([filter])
    }

    /// Unsubscribe a list of topics
    ///
    /// - Parameters:
    ///   - topics: A list of `<Topic Names>/<Topic Filters>`
    public func unsubscribe(_ topics: [Subscription]) {
        let msgid = nextMessageID()
        let frame = Unsub(msgid: msgid, topics: topics)
        unsubscriptionsWaitingAck[msgid] = topics
        send(frame)
    }

    public func auth(reasonCode : AuthReasonCode,authProperties : AuthProperties) {
        Logger.debug("auth")
        let frame = Auth(reasonCode: reasonCode, authProperties: authProperties)
        send(frame)
    }
    private func nextMessageID() -> UInt16 {
        if _msgid == UInt16.max {
            _msgid = 0
        }
        _msgid += 1
        return _msgid
    }
    private func connectFrame()->Connect{
        var connect = Connect(clientID: clientID)
        connect.keepAlive = keepAlive
        connect.username = username
        connect.password = password
        connect.willMsg5 = willMessage
        connect.cleansess = cleanSession
        connect.connectProperties = connectProperties
        return connect
    }
    private func connectPacket()->MQTTConnectPacket{
        return MQTTConnectPacket.init(cleanSession: cleanSession, keepAliveSeconds: keepAlive, clientIdentifier: clientID, userName: username, password: password, properties: [], will: nil)
    }
    private func puback(_ type: FrameType, msgid: UInt16) {
        switch type {
        case .puback:
            send(Puback(msgid: msgid, reasonCode: PubAckReasonCode.success))
        case .pubrec:
            send(Pubrec(msgid: msgid, reasonCode: PubRecReasonCode.success))
        case .pubcomp:
            send(Pubcomp(msgid: msgid, reasonCode: PubCompReasonCode.success))
        default: return
        }
    }
}
extension MQTT{
    private func notify(status:MQTT.Status,old:MQTT.Status){
        self.queue.async {
            self.delegate?.mqtt(self, didUpdate: status,prev: old)
        }
    }
    private func notify(error:Error){
        self.queue.async {
            self.delegate?.mqtt(self, didReceive: error)
        }
    }
    private func handle(state:NWConnection.State){
        switch state{
        case .cancelled:
            self.status = .closed(.success)
        case .failed(let error):
            self.tryClose(code: .unspecifiedError, reason: .error(error))
        case .ready://wen network ready send connect frame
            self.send(connectPacket())
            self.reader?.start()
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
    /// Internal method run in delegate queue
    /// try close when no need retry
    private func tryClose(code:MQTTReasonCode,reason:MQTT.CloseReason?){
        Logger.debug("Try close code:\(code),reason:\(reason.debugDescription)")
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
        self.conn = conn
        self.reader = PacketReader(self, conn: conn, version: .v5_0)
    }
}


// MARK: DeliverProtocol
extension MQTT: DeliverProtocol {
    func deliver(_ deliver: Deliver, wantToSend frame: Frame) {
        if let publish = frame as? Publish {
            let msgid = publish.msgid
            var message: Message? = nil
                        
            if let sendingMessage = sendingMessages[msgid] {
                message = sendingMessage
                //Logger.error("Want send \(frame), but not found in CocoaMQTT cache")
            } else {
                message = Message(topic: publish.topic, payload: publish.payload())
            }
            
            send(publish)
            
            if let message = message {
                self.delegate?.mqtt(self, didPublishMessage: message, id: msgid)
            }
        } else if let pubrel = frame as? Pubrel {
            // -- Send PUBREL
            send(pubrel)
        }
    }
}
extension MQTT: PacketReaderDelegate{
    func readCompleted(_ reader: PacketReader) {
        
    }
    func reader(_ reader: PacketReader, didReceive error: any Error) {
        Logger.debug("RECV: \(error)")
    }
    func reader(_ reader: PacketReader, didReceive packet: any MQTTPacket) {
        Logger.debug("RECV: \(packet)")
        switch packet.type{
        case .DISCONNECT:
            let disconnect = packet as! MQTTDisconnectPacket
            self.tryClose(code: disconnect.reason , reason: .server)
        case .CONNACK:
            let connack = packet as! MQTTConnAckPacket
            if connack.returnCode == 0 {
                if cleanSession {
                    deliver.cleanAll()
                } else {
                    if let storage = Storage(by: clientID) {
                        deliver.recoverSessionBy(storage)
                    } else {
                        Logger.warning("Localstorage initial failed for key: \(clientID)")
                    }
                }
                self.status = .opened
            } else {
                self.close()
            }
        case .PINGRESP:
            self.pinging?.onPong()
            self.delegate?.mqttDidReceivePong(self)
        case .PUBREC:
            let rel = MQTTPubAckPacket(type: .PUBREL, packetId: packet.packetId)
            self.send(rel)
        case .PUBACK:
            let puback = packet as! MQTTPubAckPacket
            if let promise = self.publishCallbacks[packet.packetId] {
                promise.done(.init(reason: puback.reason,properties: puback.properties))
                self.publishCallbacks[packet.packetId] = nil
            }
        case .SUBACK,.UNSUBACK:
            let suback = packet as! MQTTSubAckPacket
            if let promise = self.subscribeCallbackss[packet.packetId] {
                promise.done(.init(reasons: suback.reasons, properties: suback.properties))
                self.subscribeCallbackss[packet.packetId] = nil
            }
        default:
            break
        }
    }
}
// MARK: - ReaderDelegate
extension MQTT: ReaderDelegate {
    func readCompleted(_ reader: Reader) {
        self.directClose()
    }
    func reader(_ reader: Reader, didReceive error: Reader.Error) {
        Logger.debug("RECV: \(error)")
    }
    func reader(_ reader: Reader, didReceive disconnect: Disconnect) {
        Logger.debug("RECV: \(disconnect)")
//        self.tryClose(code: disconnect.receiveReasonCode ?? .normalDisconnection, reason: .server)
    }
    func reader(_ reader: Reader, didReceive auth: Auth) {
        Logger.debug("RECV: \(auth)")
        delegate?.mqtt(self, didReceiveAuthReasonCode: auth.receiveReasonCode!)
    }
    func reader(_ reader: Reader, didReceive connack: Connack) {
        Logger.debug("RECV: \(connack)")
        if connack.reasonCode == .success {
            if cleanSession {
                deliver.cleanAll()
            } else {
                if let storage = Storage(by: clientID) {
                    deliver.recoverSessionBy(storage)
                } else {
                    Logger.warning("Localstorage initial failed for key: \(clientID)")
                }
            }
            self.status = .opened
        } else {
            self.close()
        }
        delegate?.mqtt(self, didConnectAck: connack.reasonCode ?? ConnAckReasonCode.unspecifiedError, connAckData: connack.connackProperties ?? nil)
    }
    func reader(_ reader: Reader, didReceive publish: Publish) {
        Logger.debug("RECV: \(publish)")
        let message = Message(topic: publish.mqtt5Topic, payload: publish.payload5(), qos: publish.qos, retained: publish.retained)
        message.duplicated = publish.dup
        Logger.info("Received message: \(message)")
        delegate?.mqtt(self, didReceiveMessage: message, id: publish.msgid,  publishData: publish.publishRecProperties ?? nil)
        if message.qos == .qos1 {
            puback(FrameType.puback, msgid: publish.msgid)
        } else if message.qos == .qos2 {
            puback(FrameType.pubrec, msgid: publish.msgid)
        }
    }
    func reader(_ reader: Reader, didReceive puback: Puback) {
        Logger.debug("RECV: \(puback)")
        deliver.ack(by: puback)
        delegate?.mqtt(self, didPublishAck: puback.msgid, pubAckData: puback.pubAckProperties ?? nil)
    }
    func reader(_ reader: Reader, didReceive pubrec: Pubrec) {
        Logger.debug("RECV: \(pubrec)")
        deliver.ack(by: pubrec)
        delegate?.mqtt(self, didPublishRec: pubrec.msgid, pubRecData: pubrec.pubRecProperties ?? nil)
    }
    func reader(_ reader: Reader, didReceive pubrel: Pubrel) {
        Logger.debug("RECV: \(pubrel)")
        puback(FrameType.pubcomp, msgid: pubrel.msgid)
    }
    func reader(_ reader: Reader, didReceive pubcomp: Pubcomp) {
        Logger.debug("RECV: \(pubcomp)")
        deliver.ack(by: pubcomp)
        delegate?.mqtt(self, didPublishComplete: pubcomp.msgid, pubCompData: pubcomp.pubCompProperties ?? nil)
    }
    func reader(_ reader: Reader, didReceive suback: Suback) {
        Logger.debug("RECV: \(suback)")
        guard let topicsAndQos = subscriptionsWaitingAck.removeValue(forKey: suback.msgid) else {
            Logger.warning("UNEXPECT SUBACK Received: \(suback)")
            return
        }

        guard topicsAndQos.count == suback.grantedQos.count else {
            Logger.warning("UNEXPECT SUBACK Recivied: \(suback)")
            return
        }

        let success: NSMutableDictionary = NSMutableDictionary()
        var failed = [String]()
        for (idx,subscriptionList) in topicsAndQos.enumerated() {
            if suback.grantedQos[idx] != .FAILURE {
                subscriptions[subscriptionList.topic] = suback.grantedQos[idx]
                success[subscriptionList.topic] = suback.grantedQos[idx].rawValue
            } else {
                failed.append(subscriptionList.topic)
            }
        }

        delegate?.mqtt(self, didSubscribeTopics: success, failed: failed, subAckData: suback.subAckProperties ?? nil)
    }
    func reader(_ reader: Reader, didReceive unsuback: Unsuback) {
        Logger.debug("RECV: \(unsuback)")
        guard let topics = unsubscriptionsWaitingAck.removeValue(forKey: unsuback.msgid) else {
            Logger.warning("UNEXPECT UNSUBACK Received: \(unsuback.msgid)")
            return
        }
        // Remove local subscription
        var removeTopics : [String] = []
        for t in topics {
            removeTopics.append(t.topic)
            subscriptions.removeValue(forKey: t.topic)
        }
        delegate?.mqtt(self, didUnsubscribeTopics: removeTopics, unsubAckData: unsuback.unSubAckProperties ?? nil)
    }
    func reader(_ reader: Reader, didReceive pingresp: Pong) {
        Logger.debug("RECV: \(pingresp)")
        self.pinging?.onPong()
        delegate?.mqttDidReceivePong(self)
    }
}

