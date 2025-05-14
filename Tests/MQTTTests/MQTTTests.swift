import XCTest
import Network

@testable import MQTT

final class mqttTests: XCTestCase {
    let id = Identity("swift-mqtt-\(UInt.random(in:1..<10000))",username: "test",password: "test")
    func create()->MQTTClient.V5 {
        let endpoint:Endpoint
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            endpoint = .quic(host: "broker.emqx.io",tls: .trustAll())
        } else {
            endpoint = .tls(host: "broker.emqx.io",tls: .trustAll())
        }
        let m = MQTTClient.V5(endpoint)
        m.stopMonitor()
        m.startRetrier{reason in
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
        MQTT.Logger.level = .debug
        return m
    }

    func testSubscript() async throws {
        let mqtt = create()
        try await mqtt.open(id).wait()
        let ack = try await mqtt.subscribe(to: [.init("d/u/p/1234567"),.init("d/u/p/1231233")]).wait()
        XCTAssert(ack.codes.reduce(true, { prev, next in
            prev && (next.rawValue < 0x80)
        }))
    }
    func testQos0() async throws {
        let mqtt = create()
        try await mqtt.open(id).wait()
        let ack = try await mqtt.publish(to: "d/u/p/1234567", payload: "Hello World",qos: .atMostOnce).wait()
        XCTAssert(ack == nil)
    }
    func testQos1() async throws {
        let mqtt = create()
        try await mqtt.open(id).wait()
        let ack = try await mqtt.publish(to: "d/u/p/1231233", payload: "Hello World",qos: .atLeastOnce).wait()
        XCTAssert(ack!.code.rawValue < 0x80)
    }
    func testQos3() async throws {
        let mqtt = create()
        try await mqtt.open(id).wait()
        let ack = try await mqtt.publish(to: "d/u/p/1231dfffd", payload: "Hello World",qos: .exactlyOnce).wait()
        XCTAssert(ack!.code.rawValue < 0x80)
    }
}
