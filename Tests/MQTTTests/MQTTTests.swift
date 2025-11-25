import XCTest
import Network

@testable import MQTT
struct TestSafely:Sendable{
    var a:Int
    var b:String
}
final class mqttTests: XCTestCase {
    @Safely var t:TestSafely = .init(a: 0, b: "")
    var id:Identity{
        Identity("swift-mqtt-\(UInt.random(in:1..<10000))",username: "test",password: "test")
    }
    func testTCP() async throws{
       try await useEndpoint(.tcp(host: "broker.emqx.io"))
    }
    func testTLS() async throws{
       try await useEndpoint(.tls(host: "broker.emqx.io",tls: .trustAll()))
    }
    func testWS() async throws{
       try await useEndpoint(.ws(host: "broker.emqx.io"))
    }
    func testWSS() async throws{
       try await useEndpoint(.wss(host: "broker.emqx.io",tls: .trustAll()))
    }
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testQUIC() async throws{
       try await useEndpoint(.quic(host: "broker.emqx.io",tls: .trustAll()))
    }
    func useEndpoint(_ endpoint:Endpoint) async throws {
        let mqtt = create(endpoint)
        try await mqtt.open(id).wait()
        let ack = try await mqtt.subscribe(to: [.init("d/u/p/1234567"),.init("d/u/p/1231233")]).wait()
        XCTAssert(ack.codes.reduce(true, { prev, next in
            prev && (next.rawValue < 0x80)
        }))
        var puback = try await mqtt.publish(to: "d/u/p/1234567", payload: "Hello World",qos: .atMostOnce).wait()
        XCTAssert(puback == nil)
        puback = try await mqtt.publish(to: "d/u/p/1231233", payload: "Hello World",qos: .atLeastOnce).wait()
        XCTAssert(puback!.code.rawValue < 0x80)
        puback = try await mqtt.publish(to: "d/u/p/1231dfffd", payload: "Hello World",qos: .exactlyOnce).wait()
        XCTAssert(puback!.code.rawValue < 0x80)
    }
    func create(_ endpoint:Endpoint)->MQTTClient.V5 {
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
    func testSafely(){
        let group = DispatchGroup()
        for _ in 0..<100{
            group.enter()
            DispatchQueue.global().async {
                group.leave()
                self.$t.write { t in
                    t.a += 1
                }
            }
        }
        group.wait()
        XCTAssert(self.t.a == 100)
    }
}
