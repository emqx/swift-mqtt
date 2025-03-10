import XCTest
@testable import MQTT
import Network


let mqtt = {
    let endpoint:MQTT.Endpoint
    if #available(iOS 15.0, *) {
        endpoint = .quic(host: "172.16.2.7",tls: .trustAll())
    } else {
        endpoint = .tls(host: "172.16.2.7",tls: .trustAll())
    }
    
    let m = MQTT.Client.V5("swift-mqtt", endpoint: endpoint)
    m.config.username = "test"
    m.config.password = "test"
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
}()
final class mqttTests: XCTestCase {
    func testExample() async throws {
        try await mqtt.open().wait()
        try await mqtt.subscribe(to: "topic").wait()
        let ack = try await mqtt.publish(to: "topic", payload: "Hello MQTT").wait()
        XCTAssert(ack?.code == .success)
        // XCTest Documenation
        // https://developer.apple.com/documentation/xctest
        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }
}
