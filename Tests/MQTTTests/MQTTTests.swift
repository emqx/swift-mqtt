import XCTest
@testable import MQTT
import Network


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
final class mqttTests: XCTestCase {
    func testExample() async throws {
        mqtt.open()
        sleep(20)
        // XCTest Documenation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }
}
