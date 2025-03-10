//
//  Status.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/11.
//

import Foundation
import Network

extension MQTT{
    /// state machine
    public enum Status:Sendable,Hashable,CustomStringConvertible{
        public static func == (lhs: MQTT.Status, rhs: MQTT.Status) -> Bool {
            lhs.hashValue == rhs.hashValue
        }
        case opened
        case opening
        case closing
        case closed(CloseReason? = nil)
        public var description: String{
            switch self{
            case .opening: return "opening"
            case .closing: return "closing"
            case .opened:  return "opened"
            case .closed: return "closed"
            }
        }
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .opened:
                0.hash(into: &hasher)
            case .opening:
                1.hash(into: &hasher)
            case .closing:
                2.hash(into: &hasher)
            case .closed:
                3.hash(into: &hasher)
            }
        }
    }
    ///  close reason
    public enum CloseReason:Sendable,CustomStringConvertible{
        /// close when ping timeout
        case pingTimeout
        /// auto close by network monitor when network unsatisfied
        case unsatisfied
        /// the server close the connection
        case serverClose(ResultCode.Disconnect)
        /// the client close the connection
        case clientClose(ResultCode.Disconnect)
        /// Closed due to `MQTTError`. But exclude `MQTTError.serverClose` `MQTTError.clientClose`
        case mqttError(MQTTError)
        /// Other unclassified errors
        case otherError(Error)
        /// Closed due to `NWError`
        case networkError(NWError)
        public var description: String{
            switch self{
            case .unsatisfied: return "Unsatisfied"
            case .pingTimeout: return "PingTimeout"
            case .serverClose(let code): return "ServerClose(\(code))"
            case .clientClose(let code): return "ClientClose(\(code))"
            case .mqttError(let error): return "MQTTError(\(error))"
            case .otherError(let error): return "OtherError(\(error))"
            case .networkError(let error): return "NetworkError(\(error))"
            }
        }
        init(error:Error){
            switch error{
            case let err as NWError:
                self = .networkError(err)
            case let err as MQTTError:
                self = .mqttError(err)
            default:
                self = .otherError(error)
            }
        }
    }
}

///
/// All explain for`NWError.tls(OSStatus)`
///

//CF_ENUM(OSStatus) {
//    errSSLProtocol              = -9800,    /* SSL protocol error */
//    errSSLNegotiation           = -9801,    /* Cipher Suite negotiation failure */
//    errSSLFatalAlert            = -9802,    /* Fatal alert */
//    errSSLWouldBlock            = -9803,    /* I/O would block (not fatal) */
//    errSSLSessionNotFound       = -9804,    /* attempt to restore an unknown session */
//    errSSLClosedGraceful        = -9805,    /* connection closed gracefully */
//    errSSLClosedAbort           = -9806,    /* connection closed via error */
//    errSSLXCertChainInvalid     = -9807,    /* invalid certificate chain */
//    errSSLBadCert               = -9808,    /* bad certificate format */
//    errSSLCrypto                = -9809,    /* underlying cryptographic error */
//    errSSLInternal              = -9810,    /* Internal error */
//    errSSLModuleAttach          = -9811,    /* module attach failure */
//    errSSLUnknownRootCert       = -9812,    /* valid cert chain, untrusted root */
//    errSSLNoRootCert            = -9813,    /* cert chain not verified by root */
//    errSSLCertExpired           = -9814,    /* chain had an expired cert */
//    errSSLCertNotYetValid       = -9815,    /* chain had a cert not yet valid */
//    errSSLClosedNoNotify        = -9816,    /* server closed session with no notification */
//    errSSLBufferOverflow        = -9817,    /* insufficient buffer provided */
//    errSSLBadCipherSuite        = -9818,    /* bad SSLCipherSuite */
//
//    /* fatal errors detected by peer */
//    errSSLPeerUnexpectedMsg     = -9819,    /* unexpected message received */
//    errSSLPeerBadRecordMac      = -9820,    /* bad MAC */
//    errSSLPeerDecryptionFail    = -9821,    /* decryption failed */
//    errSSLPeerRecordOverflow    = -9822,    /* record overflow */
//    errSSLPeerDecompressFail    = -9823,    /* decompression failure */
//    errSSLPeerHandshakeFail     = -9824,    /* handshake failure */
//    errSSLPeerBadCert           = -9825,    /* misc. bad certificate */
//    errSSLPeerUnsupportedCert   = -9826,    /* bad unsupported cert format */
//    errSSLPeerCertRevoked       = -9827,    /* certificate revoked */
//    errSSLPeerCertExpired       = -9828,    /* certificate expired */
//    errSSLPeerCertUnknown       = -9829,    /* unknown certificate */
//    errSSLIllegalParam          = -9830,    /* illegal parameter */
//    errSSLPeerUnknownCA         = -9831,    /* unknown Cert Authority */
//    errSSLPeerAccessDenied      = -9832,    /* access denied */
//    errSSLPeerDecodeError       = -9833,    /* decoding error */
//    errSSLPeerDecryptError      = -9834,    /* decryption error */
//    errSSLPeerExportRestriction = -9835,    /* export restriction */
//    errSSLPeerProtocolVersion   = -9836,    /* bad protocol version */
//    errSSLPeerInsufficientSecurity = -9837, /* insufficient security */
//    errSSLPeerInternalError     = -9838,    /* internal error */
//    errSSLPeerUserCancelled     = -9839,    /* user canceled */
//    errSSLPeerNoRenegotiation   = -9840,    /* no renegotiation allowed */
//
//    /* non-fatal result codes */
//    errSSLPeerAuthCompleted     = -9841,    /* peer cert is valid, or was ignored if verification disabled */
//    errSSLClientCertRequested   = -9842,    /* server has requested a client cert */
//
//    /* more errors detected by us */
//    errSSLHostNameMismatch      = -9843,    /* peer host name mismatch */
//    errSSLConnectionRefused     = -9844,    /* peer dropped connection before responding */
//    errSSLDecryptionFail        = -9845,    /* decryption failure */
//    errSSLBadRecordMac          = -9846,    /* bad MAC */
//    errSSLRecordOverflow        = -9847,    /* record overflow */
//    errSSLBadConfiguration      = -9848,    /* configuration error */
//    errSSLUnexpectedRecord      = -9849,    /* unexpected (skipped) record in DTLS */
//    errSSLWeakPeerEphemeralDHKey = -9850,   /* weak ephemeral dh key  */
//
//    /* non-fatal result codes */
//    errSSLClientHelloReceived   = -9851,    /* SNI */
//};

//CF_ENUM(OSStatus)
//{
//    errSecSuccess                               = 0,       /* No error. */
//    errSecUnimplemented                         = -4,      /* Function or operation not implemented. */
//    errSecIO                                    = -36,     /*I/O error (bummers)*/
//    errSecOpWr                                  = -49,     /*file already open with with write permission*/
//    errSecParam                                 = -50,     /* One or more parameters passed to a function where not valid. */
//    errSecAllocate                              = -108,    /* Failed to allocate memory. */
//    errSecUserCanceled                          = -128,    /* User canceled the operation. */
//    errSecBadReq                                = -909,    /* Bad parameter or invalid state for operation. */
//    errSecInternalComponent                     = -2070,
//    errSecNotAvailable                          = -25291,  /* No keychain is available. You may need to restart your computer. */
//    errSecDuplicateItem                         = -25299,  /* The specified item already exists in the keychain. */
//    errSecItemNotFound                          = -25300,  /* The specified item could not be found in the keychain. */
//    errSecInteractionNotAllowed                 = -25308,  /* User interaction is not allowed. */
//    errSecDecode                                = -26275,  /* Unable to decode the provided data. */
//    errSecAuthFailed                            = -25293,  /* The user name or passphrase you entered is not correct. */
//};


