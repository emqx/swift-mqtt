//
//  Connection.swift
//  swift-mqtt
//
//  Created by supertext on 2025/3/7.
//

import Foundation
import Network

protocol SocketDelegate:AnyObject{
    func socket(_ socket:Socket,didReceive error:Error)
    func socket(_ socket:Socket,didReceive packet:Packet)
}
class Socket:@unchecked Sendable{
    let endpoint:MQTT.Endpoint
    private var conn:NWConnection?
    private var header:UInt8 = 0
    private var length:Int = 0
    private var multiply = 1
    private let config:MQTT.Config
    private var cancelTask:Promise<Void>?
    weak var delegate:SocketDelegate?
    init(endpoint:MQTT.Endpoint,config:MQTT.Config){
        self.endpoint = endpoint
        self.config = config
    }
    func start(in queue:DispatchQueue){
        let params = endpoint.params(config: config)
        let conn = NWConnection(to: params.0, using: params.1)
        conn.stateUpdateHandler = self.handle(state:)
        conn.start(queue: queue)
        self.conn = conn
        switch self.endpoint.type{
        case .ws,.wss:
            self.readMessage()
        default:
            self.readHeader()
        }
    }
    func send(data:Data)->Promise<Void>{
        guard let conn = self.conn else{
            return .init(MQTTError.unconnected)
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
    @discardableResult
    func cancel()->Promise<Void>{
        guard self.cancelTask == nil else{
            return .init(MQTTError.alreadyClosed)
        }
        guard let conn else{
            return .init(MQTTError.alreadyClosed)
        }
        let promise = Promise<Void>()
        self.cancelTask = promise
        conn.cancel()
        return promise
    }
    private func handle(state:NWConnection.State){
        switch state{
        case .cancelled:
            // This is the network telling us we're closed.
            // We don't need to actually do anything here
            // other than check our state is ok.
            self.cancelTask?.done(())
            self.cancelTask = nil
            self.conn = nil
        case .failed(let error):
            // The connection has failed for some reason.
            self.delegate?.socket(self, didReceive: error)
        case .ready:
            break
        case .preparing:
            // This just means connections are being actively established. We have no specific action here.
            break
        case .setup:
            break
            /// inital state
        case .waiting(let error):
            // This means the connection cannot currently be completed. We should notify the pipeline
            // here, or support this with a channel option or something, but for now for the sake of
            // demos we will just allow ourselves into this stage.tage.
            // But let's not worry about that right now. so noting happend
            // In this state we've transitioned into waiting, presumably from active or closing. In this
            // version of NIO this is an error, but we should aim to support this at some stage.
            self.delegate?.socket(self, didReceive: error)
        default:
            // This clause is here to help the compiler out: it's otherwise not able to
            // actually validate that the switch is exhaustive. Trust me, it is.
            break
        }
    }
    
    private func readHeader(){
        self.reset()
        self.readData(1) { result in
            self.header = result[0]
            self.readLength()
        }
    }
    private func readLength(){
        self.readData(1) { result in
            let byte = result[0]
            self.length += Int(byte & 0x7f) * self.multiply
            if byte & 0x80 != 0{
                let result = self.multiply.multipliedReportingOverflow(by: 0x80)
                if result.overflow {
                    self.delegate?.socket(self, didReceive: MQTTError.decodeError(.varintOverflow))
                    return
                }
                self.multiply = result.partialValue
                return self.readLength()
            }
            if self.length > 0{
                return self.readPayload()
            }
            self.dispath(data: Data())
        }
    }
    
    private func readPayload(){
        self.readData(length) { data in
            self.dispath(data: data)
        }
    }
    private func dispath(data:Data){
        guard let type = PacketType(rawValue: header) ?? PacketType(rawValue: header & 0xF0) else {
            self.delegate?.socket(self, didReceive: MQTTError.decodeError(.unrecognisedPacketType))

            return
        }
        let incoming:IncomingPacket = .init(type: type, flags: self.header & 0xF, remainingData: .init(data: data))
        do {
            self.delegate?.socket(self, didReceive: try incoming.packet(with: self.config.version))
        } catch {
            self.delegate?.socket(self, didReceive: error)
        }
        self.readHeader()
    }
    private func readData(_ length:Int,finish:(@Sendable (Data)->Void)?){
        conn?.receive(minimumIncompleteLength: length, maximumLength: length, completion: {[weak self] content, contentContext, isComplete, error in
            guard let self else{
                return
            }
            if isComplete{
                self.delegate?.socket(self, didReceive: MQTTError.decodeError(.streamCompleted))
                return
            }
            if let error{
                self.delegate?.socket(self, didReceive: error)
                return
            }
            guard let data = content,data.count == length else{
                self.delegate?.socket(self, didReceive: MQTTError.decodeError(.unexpectedDataLength))

                return
            }
            finish?(data)
        })
    }
    private func readMessage(){
        conn?.receiveMessage {[weak self] content, contentContext, isComplete, error in
            guard let self else{ return }
            if isComplete{
                self.delegate?.socket(self, didReceive: MQTTError.decodeError(.streamCompleted))
                return
            }
            if let error{
                self.delegate?.socket(self, didReceive: error)
                return
            }
            guard let data = content else{
                self.delegate?.socket(self, didReceive: MQTTError.decodeError(.unexpectedDataLength))
                return
            }
            do {
                var buffer = DataBuffer(data: data)
                let incoming = try IncomingPacket.read(from: &buffer)
                let message = try incoming.packet(with: self.config.version)
                self.delegate?.socket(self, didReceive: message)
            }catch{
                self.delegate?.socket(self, didReceive: error)
            }
        }
    }
    private func reset(){
        header = 0
        length = 0
        multiply = 1
    }
}
extension NWConnection.ContentContext{
    static func `default`(timeout:TimeInterval)->NWConnection.ContentContext{
        return .init(identifier: "swift-mqtt",expiration: .init(timeout*1000))
    }
}
