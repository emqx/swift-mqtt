import XCTest
@testable import MQTT
import Network

let client = MQTTClient()
class MQTTClient{
    let mqtt: MQTT
    init(){
//        let inter = NWInterface()
        let endpoint = NWEndpoint.hostPort(host: "broker.beta.jagat.io", port: 1883)
        self.mqtt = MQTT("swift-mqtt", endpoint: endpoint, params: .tcp)
        self.mqtt.username = "jagat-mqtt-pwd-im"
        self.mqtt.password = "jagat-mqtt-pwd-im"
        self.mqtt.logLevel = .debug
        self.mqtt.delegate = self
    }
    func connect(){
        self.mqtt.open()
    }
}
extension MQTTClient:MQTTDelegate{
    ///
    func mqtt(_ mqtt: MQTT, didUpdate status:MQTT.Status,prev:MQTT.Status){
        MQTT.Logger.info("mqtt didUpdate status \(status)")
    }
    ///
    func mqtt(_ mqtt: MQTT, didConnectAck ack: ConnAckReasonCode, connAckData: DecodeConnAck?){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishMessage message: MQTT.Message, id: UInt16){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishAck id: UInt16, pubAckData: DecodePubAck?){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishRec id: UInt16, pubRecData: DecodePubRec?){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didReceiveMessage message: MQTT.Message, id: UInt16, publishData: DecodePublish?){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: DecodeSubAck?){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didUnsubscribeTopics topics: [String], unsubAckData: DecodeUnsubAck?){
        
    }
    
    ///
    func mqtt(_ mqtt: MQTT, didReceiveDisconnectReasonCode reasonCode: MQTT.CloseCode){
        
    }
    
    ///
    func mqtt(_ mqtt: MQTT, didReceiveAuthReasonCode reasonCode: AuthReasonCode){
        
    }
    
    ///
    /// socket did recevied error.
    /// Most of the time you don't have to care about this, because it's already taken care of internally
    func mqtt(_ mqtt:MQTT, didReceive error:Error){
        
    }

    ///
    func mqtt(_ mqtt: MQTT, didPublishComplete id: UInt16,  pubCompData: DecodePubComp?){
        
    }
    ///
    func mqttDidPing(_ mqtt: MQTT){
        
    }

    ///
    func mqttDidReceivePong(_ mqtt: MQTT){
        
    }
}
final class mqttTests: XCTestCase {
    let client = MQTTClient()
    func testExample() throws {
        client.connect()
        sleep(20)
        // XCTest Documenation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }
}
