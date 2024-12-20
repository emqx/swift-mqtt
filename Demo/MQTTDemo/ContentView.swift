//
//  ContentView.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import SwiftUI
import MQTT

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 50) {

            Button("连接MQTT") {
                mqtt.open()
            }
            Button("断开MQTT") {
                mqtt.close()
            }
            Button("发送消息") {
                mqtt.publish("g/u", payload: "hello mqtt",qos: .exactlyOnce)
            }
            Button("订阅主题") {
                mqtt.subscribe("g/u/p/111",qos: .atLeastOnce)
            }
            Button("取消订阅") {
                mqtt.unsubscribe("g/u/p/111")

            }
            Button("测试"){
                mqtt.test()
            }
        }
    }
}

#Preview {
    ContentView()
}
