import XCTest
@testable import MQTT
import Network


let mqtt = {
    let m = MQTT.ClientV5("swift-mqtt", endpoint: .quic(host: "docs.lerjin.com"))
    m.config.username = "jagat-mqtt-pwd-im"
    m.config.password = "jagat-mqtt-pwd-im"
    m.usingMonitor()
    m.usingRetrier()
    MQTT.Logger.level = .debug
    return m
}()
final class mqttTests: XCTestCase {
    func testExample() throws {
        mqtt.open()
        sleep(20)
        // XCTest Documenation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }
}
