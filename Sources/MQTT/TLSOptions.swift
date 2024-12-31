//
//  TLSOptions.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/27.
//

import Network
import Foundation
import Security

public enum TLSError:Error{
    case invalidData
}
public struct TLSOptions:Sendable{
    private let queue:DispatchQueue = {
        .init(label: "swift.mqtt.tls.queue")
    }()
    /// use for self sign cert
    public let verify:Verify?
    /// use for mtls
    public let credential: Credential?
    /// the server name if need
    public let serverName:String?
    /// min tls version
    public let minVersion:Version?
    /// max tls version
    public let maxVersion:Version?
    public init(
        verify: Verify? = nil,
        credential: Credential? = nil,
        serverName: String? = nil,
        minVersion: Version? = nil,
        maxVersion: Version? = nil)
    {
        self.verify = verify
        self.credential = credential
        self.serverName = serverName
        self.minVersion = minVersion
        self.maxVersion = maxVersion
    }
    /// Build trust all certs options conveniently
    /// - Important: This setting is not secure and is usually only used as a test during the development phase
    public static func trustAll()->TLSOptions{
        TLSOptions(verify: .trustAll)
    }
    func update_sec_options(_ opt_t:sec_protocol_options_t){
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
                    SecTrustEvaluateAsyncWithError(trust, self.queue) { _, result, error in
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

extension TLSOptions{
    
    public enum Version:Sendable{
        case v1_2
        case v1_3
        var ver_t:tls_protocol_version_t{
            switch self {
            case .v1_2: return .TLSv12
            case .v1_3: return .TLSv13
            }
        }
    }
    public enum Verify:@unchecked Sendable{
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
    public struct Credential:@unchecked Sendable{
        public let id:SecIdentity
        public let certs:[SecCertificate]
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

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension NWProtocolQUIC.Options{
    public class var mqtt:NWProtocolQUIC.Options{
        .init(alpn:["mqtt"])
    }
}

extension MQTT{
    internal enum Prototype{ case ws,tcp,tls,wss,quic }
    public struct Endpoint:Sendable{
        let type:Prototype
        public let host:String
        public let port:UInt16
        public let opt:NWProtocolOptions
        public let tls:TLSOptions?
        
        /// Create a `TCP`protocol endpoint
        /// - Parameters:
        ///    - host: The host ip or domain
        ///    - port: The server listen port
        ///    - opt: The tcp protocol options
        ///
        public static func tcp(host:String,port:UInt16 = 1883,opt:NWProtocolTCP.Options = .init())->Endpoint{
            return .init(type: .tcp,host: host, port: port,opt: opt,tls: nil)
        }
        /// Create a `TCP`protocol endpoint using `TLS`
        /// - Parameters:
        ///    - host: The host ip or domain
        ///    - port: The server listen port
        ///    - opt: The tcp protocol options
        ///    - tls: The tls handshake options
        ///
        public static func tls(host:String,port:UInt16 = 8883,opt:NWProtocolTCP.Options = .init(),tls:TLSOptions? = nil)->Endpoint{
            return .init(type: .tls,host: host, port: port,opt: opt,tls: tls)
        }
        /// Create a `QUIC`protocol endpoint
        /// - Parameters:
        ///    - host: The host ip or domain
        ///    - port: The server listen port
        ///    - opt: The quic protocol options
        ///    - tls: The tls handshake options
        /// - Important: The property `opt.idleTimout` wil bel overwrited by `config.keepAlive` when `config.pingEnable` is true.
        ///
        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        public static func quic(host:String,port:UInt16 = 14567,opt:NWProtocolQUIC.Options = .mqtt,tls:TLSOptions? = nil)->Endpoint{
            return .init(type: .quic,host: host, port: port,opt: opt,tls: tls)
        }
        func params(config:Config)->(NWEndpoint,NWParameters){
            switch self.type {
            case .quic:
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                    let quic = opt as! NWProtocolQUIC.Options
                    if config.pingEnabled{
                        quic.idleTimeout = Int(config.keepAlive) * 1500 // 1.5x keepAlive time
                    }
                    tls?.update_sec_options(quic.securityProtocolOptions)
                    let params = NWParameters(quic: quic)
                    return (endpoint,params)
                } else {
                    fatalError("Never happend")
                }
            case .tcp:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let tcp = opt as! NWProtocolTCP.Options
                let params = NWParameters(tls: nil, tcp: tcp)
                return (endpoint,params)
            case .tls:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let tcp = opt as! NWProtocolTCP.Options
                let tlsOptions = NWProtocolTLS.Options()
                tls?.update_sec_options(tlsOptions.securityProtocolOptions)
                let params = NWParameters(tls: tlsOptions, tcp: tcp)
                return (endpoint,params)
            case .wss:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let tcp = opt as! NWProtocolTCP.Options
                let tlsOptions = NWProtocolTLS.Options()
                tls?.update_sec_options(tlsOptions.securityProtocolOptions)
                let params = NWParameters(tls: tlsOptions, tcp: tcp)
                let wsOptions = NWProtocolWebSocket.Options()
                wsOptions.setSubprotocols(["mqtt"])
                params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
                return (endpoint,params)
            case .ws:
                let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
                let tcp = opt as! NWProtocolTCP.Options
                let params = NWParameters(tls: nil, tcp: tcp)
                let wsOptions = NWProtocolWebSocket.Options()
                wsOptions.setSubprotocols(["mqtt"])
                params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
                return (endpoint,params)
            }
        }
    }
}
