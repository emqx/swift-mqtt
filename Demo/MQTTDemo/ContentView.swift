//
//  ContentView.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import SwiftUI
import MQTT

class State:ObservableObject{
    @Published var title:String = "closed"
    @Published var messages:[String] = ["RECV Message:"]
    deinit{
        client.removeObserver(self)
    }
    init() {
        client.addObserver(self, of: .status, selector: #selector(statusChanged(_:)))
        client.addObserver(self, of: .message, selector: #selector(recivedMessage(_:)))
    }
    @objc func statusChanged(_ notify:Notification){
        guard let info = notify.mqttStatus() else{
            return
        }
        self.title = info.new.description
    }
    @objc func recivedMessage(_ notify:Notification){
        guard let info = notify.mqttMesaage() else{
            return
        }
        let str = String(data: info.message.payload, encoding: .utf8) ?? ""
        self.messages.append("\(self.messages.count): "+str)
    }
}
struct ContentView: View {
    @ObservedObject var state:State = .init()
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 25) {
                Button("OPEN MQTT") {
                    client.open().catch { err in
                        print(err)
                    }
                }
                Button("CLOSE MQTT") {
                    client.close().catch { err in
                        print(err)
                    }
                }
                Button("SUBSCRIBE") {
                    client.subscribe(to:"topic",qos: .exactlyOnce).catch { err in
                        print(err)
                    }
                }
                Button("UNSUBSCRIBE") {
                    client.unsubscribe(from:"topic").catch { err in
                        print(err)
                    }
                }
                Button("SEND MESSAGE Qos0") {
                    client.publish(to:"topic", payload: "hello mqtt qos0",qos: .atMostOnce).catch { err in
                        print(err)
                    }
                }
                Button("SEND MESSAGE Qos1") {
                    client.publish(to:"topic", payload: "hello mqtt qos1",qos: .atLeastOnce).catch { err in
                        print(err)
                    }
                }
                Button("SEND MESSAGE Qos2") {
                    client.publish(to:"topic", payload: "hello mqtt qos2",qos: .exactlyOnce).catch { err in
                        print(err)
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(state.messages, id: \.self) { item in
                                Text(item)
                                    .frame(width:350,alignment: .leading)
                                    .id(item)
                            }
                        }
                    }
                    .onChange(of: state.messages, initial: true, { oldValue, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue.last, anchor: .bottom)
                        }
                    })
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(5)
                    .frame(height: 200)
                }
            }
            .padding()
            .navigationTitle(state.title)
        }
    }
}

#Preview {
    ContentView()
}
