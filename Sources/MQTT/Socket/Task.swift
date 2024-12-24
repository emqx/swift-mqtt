//
//  Task.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/23.
//

import Promise


extension MQTT{
    class Task{
        let promise:Promise<Packet>
        var sendPacket: any Packet
        init(_ packet:Packet){
            self.promise = .init()
            self.sendPacket = packet
        }
        func done(with packet: any Packet){
            self.promise.done(packet)
        }
        func done(with error: any Error){
            self.promise.done(error)
        }
    }
}
