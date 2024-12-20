//
//  Subscription.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/10.
//

import Foundation

///3.8.3.1 Subscription Options
public class Subscription {
 
    public var topic: String
    public var qos = MQTTQos.qos1
    public var noLocal: Bool = false
    public var retainAsPublished: Bool = false
    public var retainHandling: RetainHandlingOption
    public var subscriptionOptions: Bool = false

    public init(topic: String) {
        self.topic = topic
        self.qos = MQTTQos.qos1
        self.noLocal = false
        self.retainAsPublished = false
        self.retainHandling = RetainHandlingOption.none
    }

    public init(topic: String, qos: MQTTQos) {
        self.topic = topic
        self.qos = qos
        self.noLocal = false
        self.retainAsPublished = false
        self.retainHandling = RetainHandlingOption.none
    }

    var subscriptionData:[UInt8]{
        var data = [UInt8]()

        data += topic.bytesWithLength

        var options:Int = 0;
        switch self.qos {
        case .qos0:
            options = options | 0b0000_0000
        case .qos1:
            options = options | 0b0000_0001
        case .qos2:
            options = options | 0b0000_0010
        default:
            MQTT.Logger.debug("topicFilter qos failure")
        }

        switch self.noLocal {
        case true:
            options = options | 0b0000_0100
        case false:
            options = options | 0b0000_0000
        }

        switch self.retainAsPublished {
        case true:
            options = options | 0b0000_1000
        case false:
            options = options | 0b0000_0000
        }

        switch self.retainHandling {
        case RetainHandlingOption.none:
            options = options | 0b0010_0000
        case RetainHandlingOption.sendOnlyWhenSubscribeIsNew:
            options = options | 0b0001_0000
        case RetainHandlingOption.sendOnSubscribe:
            options = options | 0b0000_0000
        }


        if subscriptionOptions {
            data += [UInt8(options)]
        }


        return data
    }

}
