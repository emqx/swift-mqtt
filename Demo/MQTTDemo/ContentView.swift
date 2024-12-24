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
                mqtt.publish(to:"g/u", payload: "hello mqtt",qos: .exactlyOnce)
            }
            Button("订阅主题") {
                mqtt.subscribe(to:"g/u/p/111")
            }
            Button("取消订阅") {
                mqtt.unsubscribe(from:"g/u/p/111")

            }
            Button("测试"){
            }
        }
    }
}

#Preview {
    ContentView()
}
