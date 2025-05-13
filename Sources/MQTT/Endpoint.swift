//
//  Endpoint.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/27.
//

import Network
import Security
import Foundation

enum Prototype{ case ws,tcp,tls,wss,quic }

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
                params.allowFastOpen = true // allow fast open
                return (endpoint,params)
            } else {
                fatalError("Never happend")
            }
        case .tcp:
            let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
            let tcp = opt as! NWProtocolTCP.Options
            tcp.connectionTimeout = Int(config.connectTimeout)
            return (endpoint,NWParameters(tls: nil, tcp: tcp))
        case .tls:
            let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
            let tcp = opt as! NWProtocolTCP.Options
            tcp.connectionTimeout = Int(config.connectTimeout)
            let tlsOptions = NWProtocolTLS.Options()
            tls?.update_sec_options(tlsOptions.securityProtocolOptions)
            let params = NWParameters(tls: tlsOptions, tcp: tcp)
            params.allowFastOpen = true // allow fast open
            return (endpoint,params)
        case .wss:
            let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
            let tcp = opt as! NWProtocolTCP.Options
            tcp.connectionTimeout = Int(config.connectTimeout)
            let tlsOptions = NWProtocolTLS.Options()
            tls?.update_sec_options(tlsOptions.securityProtocolOptions)
            let params = NWParameters(tls: tlsOptions, tcp: tcp)
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.setSubprotocols(["mqtt"])
            params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
            params.allowFastOpen = true // allow fast open
            return (endpoint,params)
        case .ws:
            let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
            let tcp = opt as! NWProtocolTCP.Options
            tcp.connectionTimeout = Int(config.connectTimeout)
            let params = NWParameters(tls: nil, tcp: tcp)
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.setSubprotocols(["mqtt"])
            params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
            return (endpoint,params)
        }
    }
}

public struct TLSOptions:Sendable{
    private let queue:DispatchQueue = {
        .init(label: "mqtt.tls.queue")
    }()
    /// Use to verify the validity of the server certificate
    public var trust:ServerTrust?
    /// Use to client certificateertificate  challenge
    public var credential: Credential?
    /// the server name if need just like the host in http.
    /// may be use to server trust
    public var serverName:String?
    /// min tls version
    public var minVersion:Version?
    /// max tls version
    public var maxVersion:Version?
    /// session tickets enable
    public var ticketsEnable:Bool?
    /// false start enable
    public var falseStartEnable:Bool?
    /// resumption enable
    public var resumptionEnabled:Bool?
    
    public init(trust: ServerTrust? = nil, credential: Credential? = nil, serverName: String? = nil, minVersion: Version? = nil, maxVersion: Version? = nil, sctEnable: Bool? = nil, ocspEnable: Bool? = nil, ticketsEnable: Bool? = nil, falseStartEnable: Bool? = nil, resumptionEnabled: Bool? = nil, renegotiationEnable: Bool? = nil) {
        self.trust = trust
        self.credential = credential
        self.serverName = serverName
        self.minVersion = minVersion
        self.maxVersion = maxVersion
        self.ticketsEnable = ticketsEnable
        self.falseStartEnable = falseStartEnable
        self.resumptionEnabled = resumptionEnabled
    }
    /// Build trust all certs options conveniently
    /// - Important: This setting is not secure and is usually only used as a test during the development phase
    public static func trustAll()->TLSOptions{
        TLSOptions(trust: .trustAll)
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
        if let ticketsEnable{
            sec_protocol_options_set_tls_tickets_enabled(opt_t, ticketsEnable)
        }
        if let falseStartEnable{
            sec_protocol_options_set_tls_false_start_enabled(opt_t, falseStartEnable)
        }
        if let resumptionEnabled{
            sec_protocol_options_set_tls_resumption_enabled(opt_t, resumptionEnabled)
        }
        if let identity = credential?.identity{
            sec_protocol_options_set_local_identity(opt_t, identity)
            sec_protocol_options_set_challenge_block(opt_t, { _, complette in
                complette(identity)
            }, queue)
        }
        switch self.trust {
        case .trustAll:
            sec_protocol_options_set_peer_authentication_required(opt_t,false)
        case .trustRoots(let trusts):
            sec_protocol_options_set_verify_block(opt_t,{ _, sec_trust, complete in
                let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
                SecTrustSetAnchorCertificates(trust, trusts as CFArray)
                SecTrustEvaluateAsyncWithError(trust, self.queue) { _, result, error in
                    if let error {
                        Logger.error("Trust failed: \(error.localizedDescription)")
                    }
                    complete(result)
                }
            }, queue )
        case .trustBlock(let block):
            sec_protocol_options_set_verify_block(opt_t,{ _, sec_trust, complete in
                let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
                complete(block(trust))
            }, queue )
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
    /// Server Trust
    public enum ServerTrust:@unchecked Sendable{
        /// trust all means not verify
        /// - Important: This setting is not secure and is usually only used as a test during the development phase
        case trustAll
        /// verify the self-signed root certificate
        case trustRoots([SecCertificate])
        /// custom verify logic
        case trustBlock(@Sendable (SecTrust)->Bool)
        /// load certificate from file
        public static func trust(der filePath:String)throws -> Self{
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            if let cert = SecCertificateCreateWithData(nil, data as CFData) {
                return .trustRoots([cert])
            }
            throw MQTTError.invalidCertData
        }
    }
    public struct Credential:@unchecked Sendable{
        public let id:SecIdentity
        public let certs:[SecCertificate]
        /// create from p12 filePath
        public static func create(from filePath:String,passwd:String)throws->Self{
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            return try create(from: data, passwd: passwd)
        }
        /// create from p12 data
        public static func create(from data:Data,passwd:String)throws ->Self{
            let options = [kSecImportExportPassphrase as String: passwd]
            var rawItems: CFArray?
            let status = SecPKCS12Import(data as CFData,options as CFDictionary,&rawItems)
            guard status == errSecSuccess else {
                throw MQTTError.invalidCertData
            }
            guard let items = rawItems as? [[String:Any]] else{
                throw MQTTError.invalidCertData
            }
            guard let item = items.first,
                  let certs = item[kSecImportItemCertChain as String] as? [SecCertificate] else {
                throw MQTTError.invalidCertData
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

