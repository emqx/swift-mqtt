//
//  Pinging.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation

extension MQTT{
    /// Implementation of ping pong mechanism
    final class Pinging{
        /// current pinging timeout tolerance
        public let timeout:TimeInterval
        /// current pinging time interval
        public let interval:TimeInterval
        /// mqtt client
        private weak var mqtt:MQTT!
        /// task 
        private var task:DelayTask? = nil
        private var pongRecived:Bool = false
        init(_ mqtt:MQTT,timeout:TimeInterval,interval:TimeInterval) {
            self.mqtt = mqtt
            self.timeout = timeout
            self.interval = interval
        }
        /// resume the pinging task
        public func resume(){
            if self.task == nil{
                self.sendPing()
            }
        }
        /// suspend the pinging task
        /// cancel running task
        public func suspend(){
            self.task = nil
        }
        func onPong(){
            self.pongRecived = true
        }
        private func sendPing(){
            self.pongRecived = false
            mqtt.send(MQTTPingreqPacket())
            self.task = DelayTask(host: self)
        }
        private func checkPong(){
            if !self.pongRecived{
                self.mqtt.directClose(reason: .pinging)
            }
        }
        private class DelayTask {
            private weak var host:Pinging? = nil
            private var item1:DispatchWorkItem? = nil
            private var item2:DispatchWorkItem? = nil
            deinit{
                self.item1?.cancel()
                self.item2?.cancel()
            }
            init(host:Pinging) {
                self.host = host
                let timeout = host.timeout
                let interval = host.interval
                self.item1 = after(timeout){[weak self] in
                    guard let self else { return }
                    self.host?.checkPong()
                    self.item2 = self.after(interval){[weak self] in
                        guard let self else { return }
                        self.host?.sendPing()
                    }
                }
            }
            private func after(_ time:TimeInterval,block:@escaping (()->Void))->DispatchWorkItem{
                let item = DispatchWorkItem(block: block)
                DispatchQueue.global().asyncAfter(deadline: .now() + time, execute: item)
                return item
            }
        }
    }
}
