//
//  Options.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/27.
//

import Network
import Foundation
import Security



extension MQTT{
    private enum Prototype{ case ws,tcp,tls,wss,quic }
    public struct Endpoint{
        private let type:Prototype
        private let host:String
        private let port:UInt16
        private let options:TLS.Options?
        public static func ws(host:String,port:UInt16 = 8083)->Endpoint{
            return .init(type: .ws,host: host, port: port,options: nil)
        }
        public static func tcp(host:String,port:UInt16 = 1883)->Endpoint{
            return .init(type: .tcp,host: host, port: port,options: nil)
        }
        public static func tls(host:String,port:UInt16 = 8883,options:TLS.Options? = nil)->Endpoint{
            return .init(type: .tls,host: host, port: port,options: options)
        }
        public static func wss(host:String,port:UInt16 = 8084,options:TLS.Options? = nil)->Endpoint{
            return .init(type: .wss,host: host, port: port,options: options)
        }
        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        public static func quic(host:String,port:UInt16 = 14567,options:TLS.Options? = nil)->Endpoint{
            return .init(type: .quic,host: host, port: port,options: options)
        }
        func params()->(NWEndpoint,NWParameters){
            switch self.type {
            case .quic:
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                    let params = NWParameters(quic: options?.quic ?? .init())
                    return (endpoint,params)
                } else {
                    fatalError("Never happend")
                }
            case .tcp:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                return (endpoint,.tcp)
            case .tls:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let params = NWParameters(tls: options?.tls ?? .init())
                return (endpoint,params)
            case .wss:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let params = NWParameters(tls: options?.tls ?? .init())
                let wsOptions = NWProtocolWebSocket.Options()
                wsOptions.setSubprotocols(["mqtt"])
                params.defaultProtocolStack.applicationProtocols.append(wsOptions)
                return (endpoint,params)
            case .ws:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let params = NWParameters.tcp
                let wsOptions = NWProtocolWebSocket.Options()
                wsOptions.setSubprotocols(["mqtt"])
                params.defaultProtocolStack.applicationProtocols.append(wsOptions)
                return (endpoint,params)
            }
        }
    }
    public struct WebSocketConfig {
        /// Initialize MQTT.Client WebSocket configuration struct
        /// - Parameters:
        ///   - urlPath: WebSocket URL, defaults to "/mqtt"
        ///   - maxFrameSize: Max frame size WebSocket client will allow
        ///   - initialHeaders: Additional headers to add to initial HTTP request
        public init(
            urlPath: String = "/mqtt",
            maxFrameSize: Int = 1 << 14,
            initialHeaders: [String:String] = [:]
        ) {
            self.urlPath = urlPath
            self.maxFrameSize = maxFrameSize
            self.initialHeaders = initialHeaders
        }
        /// WebSocket URL, defaults to "/mqtt"
        public let urlPath: String
        /// Max frame size WebSocket client will allow
        public let maxFrameSize: Int
        /// Additional headers to add to initial HTTP request
        public let initialHeaders: [String:String]
        public var optionsHadler:(@Sendable (NWProtocolWebSocket.Options)->Void)?
    }
}
public enum TLSError:Error{
    case invalidData
    case quicNotSupport
}
public enum TLS{
    private static let queue:DispatchQueue = {
        .init(label: "swift.mqtt.tls.queue")
    }()
    public enum Version{
        case v1_2
        case v1_3
        var ver_t:tls_protocol_version_t{
            switch self {
            case .v1_2: return .TLSv12
            case .v1_3: return .TLSv13
            }
        }
    }
    public struct Options{
        public var verify:Verify? = nil
        public var credential: Credential? = nil
        public var serverName:String? = nil
        public var minVersion:Version? = nil
        public var maxVersion:Version? = nil
        public var quicOptions:Options.QUIC? = nil
        public init(){ }
        var tls:NWProtocolTLS.Options{
            let options = NWProtocolTLS.Options()
            self.update_sec_options(options.securityProtocolOptions)
            return options
        }
        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        var quic:NWProtocolQUIC.Options{
            let opt = NWProtocolQUIC.Options()
            self.update_sec_options(opt.securityProtocolOptions)
            quicOptions?.update(quic: opt)
            return opt
        }
        private func update_sec_options(_ opt_t:sec_protocol_options_t){
            if let minVersion{
                sec_protocol_options_set_min_tls_protocol_version(opt_t, minVersion.ver_t)
            }
            if let maxVersion{
                sec_protocol_options_set_max_tls_protocol_version(opt_t, maxVersion.ver_t)
            }
            if let serverName{
                sec_protocol_options_set_tls_server_name(opt_t, serverName)
            }
            if let identity = credential?.identity{
                sec_protocol_options_set_local_identity(opt_t, identity)
                sec_protocol_options_set_challenge_block(opt_t, {
                    _, complette in complette(identity)
                }, queue)
            }
            switch self.verify {
            case .trustAll:
                sec_protocol_options_set_verify_block(opt_t, { _, _, complete in complete(true) }, queue)
            case .trustRoots(let trusts):
                sec_protocol_options_set_verify_block(opt_t,
                    { _, sec_trust, complette in
                        let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
                        SecTrustSetAnchorCertificates(trust, trusts as CFArray)
                        SecTrustEvaluateAsyncWithError(trust, queue) { _, result, error in
                            if let error {
                                MQTT.Logger.error("Trust failed: \(error.localizedDescription)")
                            }
                            complette(result)
                        }
                    },
                    queue
                )
            default:
                break
            }
        }
    }
    public enum Verify{
        case trustAll
        case trustRoots([SecCertificate])
        public static func trust(der file:String)throws -> Verify{
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            if let cert = SecCertificateCreateWithData(nil, data as CFData) {
                return .trustRoots([cert])
            }
            throw TLSError.invalidData
        }
    }
    public struct Credential{
        private let id:SecIdentity
        private let certs:[SecCertificate]
        public static func create(from file:String,passwd:String)throws->Self{
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            return try create(from: data, passwd: passwd)
        }
        public static func create(from data:Data,passwd:String)throws ->Self{
            let options = [kSecImportExportPassphrase as String: passwd]
            var rawItems: CFArray?
            let status = SecPKCS12Import(data as CFData,options as CFDictionary,&rawItems)
            guard status == errSecSuccess else {
                throw TLSError.invalidData
            }
            guard let items = rawItems as? [[String:Any]] else{
                throw TLSError.invalidData
            }
            guard let item = items.first,
                  let certs = item[kSecImportItemCertChain as String] as? [SecCertificate] else {
                throw TLSError.invalidData
            }
            let identity = item[kSecImportItemIdentity as String] as! SecIdentity
            return .init(id: identity, certs: certs)
        }
        var identity:sec_identity_t?{
            sec_identity_create_with_certificates(id, certs as CFArray)
        }
    }
}
extension TLS.Options{
    public struct QUIC{
        ///given application protocols
        public var alpn:[String]?
        /// Indicates if this is a datagram flow, not a stream.
        /// Only one QUIC datagram flow can be created per connection.
        /// - Important: only effect in (macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public var isDatagram: Bool?

        /// An idle timeout for the QUIC connection, in milliseconds.
        public var idleTimeout: Int?

        /// Define the maximum length of a QUIC packet (UDP payload)
        /// that the client is willing to receive on a connection, in bytes.
        public var maxUDPPayloadSize: Int?

        /// Set the `initial_max_data` transport parameter on a QUIC connection.
        public var initialMaxData: Int?

        /// Set the `initial_max_stream_data_bidi_remote` transport parameter on a QUIC connection.
        public var initialMaxStreamDataBidirectionalRemote: Int?

        /// Set the `initial_max_stream_data_bidi_local` transport parameter on a QUIC connection.
        public var initialMaxStreamDataBidirectionalLocal: Int?

        /// Set the `initial_max_stream_data_uni` transport parameter on a QUIC connection.
        public var initialMaxStreamDataUnidirectional: Int?

        /// Set the `initial_max_streams_bidi` transport parameter on a QUIC connection.
        public var initialMaxStreamsBidirectional: Int?

        /// Set the `initial_max_streams_uni` transport parameter on a QUIC connection.
        public var initialMaxStreamsUnidirectional: Int?

        /// Set the `max_datagram_frame_size` transport parameter on a QUIC connection.
        /// - Important: only effect in (macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public var maxDatagramFrameSize: Int?
        public init(){ }
        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        func update(quic options:NWProtocolQUIC.Options){
            if let alpn{
                options.alpn = alpn
            }
            if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                if let isDatagram{
                    options.isDatagram = isDatagram
                }
                if let maxDatagramFrameSize{
                    options.maxDatagramFrameSize = maxDatagramFrameSize
                }
            }
            if let idleTimeout{
                options.idleTimeout = idleTimeout
            }
            if let maxUDPPayloadSize{
                options.maxUDPPayloadSize = maxUDPPayloadSize
            }
            if let initialMaxData{
                options.initialMaxData = initialMaxData
            }
            if let initialMaxStreamDataBidirectionalRemote{
                options.initialMaxStreamDataBidirectionalRemote = initialMaxStreamDataBidirectionalRemote
            }
            if let initialMaxStreamDataBidirectionalLocal{
                options.initialMaxStreamDataBidirectionalLocal = initialMaxStreamDataBidirectionalLocal
            }
            if let initialMaxStreamDataUnidirectional{
                options.initialMaxStreamDataUnidirectional = initialMaxStreamDataUnidirectional
            }
            if let initialMaxStreamsBidirectional{
                options.initialMaxStreamsBidirectional = initialMaxStreamsBidirectional
            }
            if let initialMaxStreamsUnidirectional{
                options.initialMaxStreamsUnidirectional = initialMaxStreamsUnidirectional
            }
        }
    }
}
