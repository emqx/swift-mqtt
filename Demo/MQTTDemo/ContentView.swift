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
    init() {
        client.onStatus = { status in
            DispatchQueue.main.async {
                self.title = status.description
            }
        }
        client.onMessage = {message in
            DispatchQueue.main.async {
                let str = String(data: message.payload, encoding: .utf8) ?? ""
                self.messages.append("\(self.messages.count): "+str)
            }
        }
    }
}
struct ContentView: View {
    @ObservedObject var state:State = .init()
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 25) {
                Button("OPEN MQTT") {
                    client.open()
                }
                Button("CLOSE MQTT") {
                    client.close()
                }
                Button("SUBSCRIBE") {
                    client.subscribe(to:"g/u/p/111")
                }
                Button("UNSUBSCRIBE") {
                    client.unsubscribe(from:"g/u/p/111")
                }
                Button("SEND MESSAGE Qos0") {
                    client.publish(to:"g/u/p/111", payload: "hello mqtt qos0",qos: .atMostOnce)
                }
                Button("SEND MESSAGE Qos1") {
                    client.publish(to:"g/u/p/111", payload: "hello mqtt qos1",qos: .atLeastOnce)
                }
                Button("SEND MESSAGE Qos2") {
                    client.publish(to:"g/u/p/111", payload: "hello mqtt qos2",qos: .exactlyOnce)
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
