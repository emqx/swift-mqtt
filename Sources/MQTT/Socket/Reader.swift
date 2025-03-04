//
//  Reader.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/17.
//

import Foundation
import Network

class Reader:@unchecked Sendable{
    private let conn:NWConnection
    private var header:UInt8 = 0
    private var length:Int = 0
    private var multiply = 1
    private let version:MQTT.Version
    private weak var socket:MQTT.Socket?//Informal agency
    init(_ socket: MQTT.Socket,conn:NWConnection) {
        self.socket = socket
        self.version = socket.config.version
        self.conn = conn
    }
    func start(){
        switch self.socket?.endpoint.type{
        case .ws,.wss:
            self.readMessage()
        default:
            self.readHeader()
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
                    self.socket?.reader(self, didReceive: MQTTError.decodeError(.varintOverflow))
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
            self.socket?.reader(self, didReceive: MQTTError.decodeError(.unrecognisedPacketType))
            return
        }
        let incoming:IncomingPacket = .init(type: type, flags: self.header & 0xF, remainingData: .init(data: data))
        do {
            let message = try incoming.packet(with: self.version)
            self.socket?.reader(self, didReceive: message)
        } catch {
            self.socket?.reader(self, didReceive: error)
        }
        self.readHeader()
    }
    private func readData(_ length:Int,finish:(@Sendable (Data)->Void)?){
        conn.receive(minimumIncompleteLength: length, maximumLength: length, completion: {[weak self] content, contentContext, isComplete, error in
            guard let self else{
                return
            }
            if isComplete{
                self.socket?.readCompleted(self)
                return
            }
            if let error{
                self.socket?.reader(self, didReceive: error)
                return
            }
            guard let data = content,data.count == length else{
                self.socket?.reader(self, didReceive: MQTTError.decodeError(.unexpectedDataLength))
                return
            }
            finish?(data)
        })
    }
    private func readMessage(){
        conn.receiveMessage {[weak self] content, contentContext, isComplete, error in
            guard let self else{ return }
            if let error{
                self.socket?.reader(self, didReceive: error)
                return
            }
            guard let data = content else{
                self.socket?.reader(self, didReceive: MQTTError.decodeError(.unexpectedDataLength))
                return
            }
            do {
                var buffer = DataBuffer(data: data)
                let incoming = try IncomingPacket.read(from: &buffer)
                let message = try incoming.packet(with: self.version)
                self.socket?.reader(self, didReceive: message)
            }catch{
                self.socket?.reader(self, didReceive: error)
            }
        }
    }
    private func reset(){
        header = 0
        length = 0
        multiply = 1
    }
}
