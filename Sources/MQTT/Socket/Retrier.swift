//
//  Retrier.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Network
import Foundation

extension MQTT{
    ///
    /// The retries filter out some cases that definitely do not need to be retried, and the rest need to be filtered by the user.
    /// The unfiltered cases are considered to need to be retried
    public final class Retrier:@unchecked Sendable{
        /// Filter out causes that do not need to be retry. Return true if retries are not required
        public typealias Filter = @Sendable (MQTT.CloseReason)->Bool
        /// Retry backoff policy
        public enum Policy:Sendable{
            /// The retry time grows linearly
            case linear(scale:Double = 1)
            /// The retry time does not grow. Use equal time interval
            case equals(interval:TimeInterval = 3)
            /// The retry time random in min...max
            case random(min:TimeInterval = 2,max:TimeInterval = 5)
            /// The retry time grows exponentially
            case exponential(base:Int = 2,scale:Double = 1,max:TimeInterval = 120)
        }
        private var times:UInt
        /// retry delay policy
        public let policy:Policy
        /// retry limit times
        public let limits:UInt
        /// Filter when check  retry
        /// Filter out causes that do not need to be retry, and return true if retries are not required
        ///
        /// - Important: return true means no need to be retried. false or nil means need to be retried
        ///
        public let filter:Filter?
        /// create a retrier
        ///
        /// - Parameters:
        ///    - policy:Retry policcy
        ///    - limits:max retry times
        ///    - filter:filter retry when some code and reasons
        ///
        init(_ policy:Policy,limits:UInt,filter:Filter?){
            self.limits = limits
            self.policy = policy
            self.filter = filter
            self.times = 0
        }
        func reset(){
            self.times = 0
        }
        /// get retry delay. nil means don't retry
        func retry(when reason:MQTT.CloseReason) -> TimeInterval? {
            if self.filter?(reason) == true {
                return nil
            }
            if times > limits {
                return nil
            }
            times += 1
            switch self.policy {
            case .linear(let scale):
                return scale * Double(times)
            case .equals(let time):
                return time
            case .random(let min,let max):
                return TimeInterval.random(in: min...max)
            case .exponential(let base, let scale,let max):
                return min(pow(Double(base),Double(times))*scale,max)
            }
        }
    }
    final class Monitor:@unchecked Sendable{
        private let impl:NWPathMonitor
        private let onChange:((NWPath.Status)->Void)?
        init(_ onChange:((NWPath.Status)->Void)?){
            self.impl = NWPathMonitor()
            self.onChange = onChange
            self.impl.pathUpdateHandler = {[weak self] newPath in
                guard let self else { return }
                self.status = newPath.status
            }
        }
        var status:NWPath.Status = .unsatisfied{
            didSet{
                if status == oldValue{ return }
                self.onChange?(status)
            }
        }
        func start(queue:DispatchQueue){
            if impl.queue == nil{
                impl.start(queue: queue)
            }
        }
        func stop(){
            impl.cancel()
        }
    }

    /// Implementation of ping pong mechanism
    final class Pinging:@unchecked Sendable{
        private var times:Int = 0
        /// current pinging timeout tolerance
        public let timeout:TimeInterval
        /// current pinging time interval
        public let interval:TimeInterval
        /// mqtt client
        private weak var delegate:Socket!
        /// task
        private var task:DelayTask? = nil
        private var pongRecived:Bool = false
        init(_ delegate:Socket,timeout:TimeInterval,interval:TimeInterval) {
            self.delegate = delegate
            self.timeout = timeout
            self.interval = interval
        }
        /// resume the pinging task
        func resume(){
            if task == nil{
                times = 0
                task = DelayTask(host: self)
            }
        }
        /// suspend the pinging task
        /// cancel running task
        func suspend(){
            task = nil
        }
        func onPong(){
            pongRecived = true
        }
        private func sendPing(){
            pongRecived = false
            delegate.sendPingreq()
        }
        private func checkPong(){
            if !pongRecived{
                times += 1
                if times >= delegate.config.pingTimes{
                    times = 0
                    delegate.pingTimeout()
                }
            }
            task = DelayTask(host: self)
        }
        private class DelayTask {
            private weak var host:Pinging!
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
                self.item1 = after(interval){[weak self] in
                    guard let self else { return }
                    self.host.sendPing()
                    self.item2 = self.after(timeout){[weak self] in
                        guard let self else { return }
                        self.host.checkPong()
                    }
                }
            }
            private func after(_ time:TimeInterval,block:@escaping (()->Void))->DispatchWorkItem{
                let item = DispatchWorkItem(block: block)
                self.host.delegate.queue.asyncAfter(deadline: .now() + time, execute: item)
                return item
            }
        }
    }
}
