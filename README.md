# swift-mqtt
- A MQTT Client over TCP and QUIC protocol
- QUIC protocol mark with `@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)`
### Usage
```swift
let mqtt = {
    let endpoint:MQTT.Endpoint
    if #available(iOS 15.0, *) {
        endpoint = .quic(host: "127.0.0.1")
    } else {
        endpoint = .tls(host: "127.0.0.1")
    }
    
    let m = MQTT.Client.V5("swift-mqtt", endpoint: endpoint)
    m.config.username = "test"
    m.config.password = "test"
    m.stopMonitor()
    m.startRetrier{reason in
        switch reason{
        case .serverClosed(let code, _):
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
    MQTT.Logger.level = .debug
    return m
}()
mqtt.open()
mqtt.close()
mqtt.subscribe(to:"topic")
mqtt.publish(to:"topic", payload: "hello mqtt",qos: .atMostOnce)
...

```
