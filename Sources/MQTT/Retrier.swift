//
//  Retrier.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Network
import Foundation

///
/// The retries filter out some cases that definitely do not need to be retried, and the rest need to be filtered by the user.
/// The unfiltered cases are considered to need to be retried
public final class Retrier:@unchecked Sendable{
    /// Filter out causes that do not need to be retry. Return true if retries are not required
    public typealias Filter = @Sendable (CloseReason)->Bool
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
    private var delayItem:DispatchWorkItem?
    init(_ policy:Policy,limits:UInt,filter:Filter?){
        self.limits = limits
        self.policy = policy
        self.filter = filter
        self.times = 0
    }
    func cancel(){
        self.times = 0
        if let delayItem{
            delayItem.cancel()
            self.delayItem = nil
        }
    }
    /// get retry delay. nil means don't retry
    func delay(when reason:CloseReason) -> TimeInterval? {
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
    func retry(in queue:DispatchQueue,after:TimeInterval,exec:@escaping ()->Void){
        let item = DispatchWorkItem(block: exec)
        self.delayItem = item
        queue.asyncAfter(deadline: .now()+after, execute: item)
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
    func start(in queue:DispatchQueue){
        if impl.queue == nil{
            impl.start(queue: queue)
        }
    }
    func stop(){
        impl.cancel()
    }
}
final class Pinging:@unchecked Sendable{
    private var queue:DispatchQueue?
    private let config:Config
    private var execTime:DispatchTime
    private var worker:DispatchWorkItem?
    private weak var client:MQTTClient?
    init(client:MQTTClient){
        execTime = .now()
        config = client.config
        self.client = client
    }
    func start(in queue:DispatchQueue){
        guard self.config.pingEnabled else { return }
        guard self.worker == nil else{ return }
        guard self.queue == nil else{ return }
        self.execTime = .now()
        self.queue = queue
        self.schedule()
    }
    func cancel(){
        guard let queue else{
            return
        }
        queue.async {
            if self.worker != nil{
                self.worker?.cancel()
                self.worker = nil
                self.queue = nil
            }
        }
    }
    func update(){
        self.execTime = .now()
    }
    private func schedule(){
        guard let queue else{
            return
        }
        let worker = DispatchWorkItem{[weak self] in
            guard let self else{ return }
            guard let client = self.client else{ return }
            guard self.execTime+TimeInterval(self.config.keepAlive) <= .now() else{
                self.schedule()
                return
            }
            client.ping().finally{result in
                if case .failure = result{
                    client.pingTimeout()
                }
            }
            self.schedule()
        }
        self.worker = worker
        queue.asyncAfter(deadline: execTime + TimeInterval(config.keepAlive), execute: worker)
    }
}
