# swift-mqtt
![Platform](https://img.shields.io/badge/platforms-iOS%2013.0%20%7C%20macOS%2010.15%20%7C%20tvOS%2013.0%20%7C%20watchOS%206.0-F28D00.svg)
- An MQTT Client over TCP and QUIC protocol
- QUIC protocol only available in `macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *`

## Why
- We already have some mqtt clients available like [mqtt-nio](https://github.com/swift-server-community/mqtt-nio.git), [CocoaMQTT](https://github.com/emqx/CocoaMQTT.git) and so on, why do we write another one?

- [mqtt-nio](https://github.com/swift-server-community/mqtt-nio.git) is built on [swift-nio](https://github.com/apple/swift-nio.git), and `swift-nio` needs to consider compatibility with platforms other than iOS, so the code dependency is a little too onerous for the iOS client. Although `swift-nio` can make the underlying implementation of `swift-nio` directly provided by the iOS Network framework through the introduction of [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services.git), it is also difficult to accept.

- [CocoaMQTT](https://github.com/emqx/CocoaMQTT.git) is built on  [CocoaAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket.git) that is too old and doesn't support the `QUIC` protocol.

- `swift-mqtt` is a lightweight mqtt client focused on the iOS platform and provides `QUIC` protocol support. Of course, many of these implementations also refer to the previous two

## Requirements

- iOS 13.0+ | macOS 10.15+ | tvOS 13.0+ | watchOS 6.0+
- Xcode 8

## Integration

#### Swift Package Manager

You can use [The Swift Package Manager](https://swift.org/package-manager) to install `swift-mqtt` by adding the proper description to your `Package.swift` file:

```swift
// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "YOUR_PROJECT_NAME",
    dependencies: [
        .package(url: "https://github.com/emqx/swift-mqtt.git", from: "0.2.1"),
    ]
)
```


## Usage
```swift
import MQTT
import Foundation

let client = Client()

class Observer{
    @objc func statusChanged(_ notify:Notification){
        guard let info = notify.mqttStatus() else{
            return
        }
        Logger.info("observed: status: \(info.old)--> \(info.new)")
    }
    @objc func recivedMessage(_ notify:Notification){
        guard let info = notify.mqttMesaage() else{
            return
        }
        let str = String(data: info.message.payload, encoding: .utf8) ?? ""
        Logger.info("observed: message: \(str)")
    }
    @objc func recivedError(_ notify:Notification){
        guard let info = notify.mqttError() else{
            return
        }
        Logger.info("observed: error: \(info.error)")
    }
}
class Client:MQTTClient.V5,@unchecked Sendable{
    let observer = Observer()
    init() {
        var options = TLSOptions()
        options.trust = .trustAll
        options.credential = try? .create(from: "", passwd: "")
        options.serverName = "example.com"
        options.minVersion = .v1_2
        options.falseStartEnable = true
        super.init(UUID().uuidString, endpoint: .quic(host: "172.16.2.7",tls: options))
        MQTT.Logger.level = .debug
        self.config.keepAlive = 60
        self.config.pingTimeout = 5
        self.config.username = "test"
        self.config.password = "test"
        self.config.pingEnabled = true
        self.delegateQueue = .main
        /// start network monitor
        self.startMonitor()
        /// start auto reconnecting
        self.startRetrier{reason in
            switch reason{
            case .serverClose(let code):
                switch code{
                case .serverBusy,.connectionRateExceeded:// don't retry when server is busy
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }
        /// eg
        /// set simple delegate
        self.delegate = self
        /// eg.
        /// add multiple observer.
        /// Don't observe self. If necessary use delegate
        self.addObserver(observer, for: .status, selector: #selector(Observer.statusChanged(_:)))
        self.addObserver(observer, for: .message, selector: #selector(Observer.recivedMessage(_:)))
        self.addObserver(observer, for: .error, selector: #selector(Observer.recivedError(_:)))
    }
    
}
extension Client:MQTTDelegate{
    func mqtt(_ mqtt: MQTTClient, didUpdate status: Status, prev: Status) {
        Logger.info("delegate: status \(prev)--> \(status)")

    }
    func mqtt(_ mqtt: MQTTClient, didReceive error: any Error) {
        Logger.info("delegate: error \(error)")
    }
    func mqtt(_ mqtt: MQTTClient, didReceive message: Message) {
        let str = String(data: message.payload, encoding: .utf8) ?? ""
        Logger.info("delegate: message: \(str)")
    }
}


client.open()
client.close()
client.subscribe(to:"topic")
client.unsubscribe(from:"topic")
client.publish(to:"topic", payload: "hello mqtt qos2",qos: .exactlyOnce)

```
