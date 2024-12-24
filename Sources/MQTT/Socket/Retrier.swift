//
//  Retrier.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation

public final class Retrier{
    /// Retry filter not retry when return true
    public typealias Filter = @Sendable (ReasonCode,MQTT.CloseReason)->Bool
    /// Retry backoff policy
    public enum Policy{
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
    /// fillter when check  retry
    ///
    /// - Important: return true means no retry
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
    /// get retry delay. nil means not retry
    func retry(when reason:MQTT.CloseReason,code:ReasonCode) -> TimeInterval? {
        if self.filter?(code,reason) == true {
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
