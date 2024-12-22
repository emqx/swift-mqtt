//===----------------------------------------------------------------------===//
//
// This source file is part of the MQTTNIO project
//
// Copyright (c) 2020-2022 Adam Fowler
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

/// Array of inflight packets. Used to resend packets when reconnecting to server
struct MQTTInflight {
    /// add packet
    mutating func add(packet: MQTTPacket) {
        self.lock.withLock {
            self.packets.append(packet)
        }
    }

    /// remove packert
    mutating func remove(id: UInt16) {
        self.lock.withLock {
            guard let first = packets.firstIndex(where: { $0.packetId == id }) else { return }
            self.packets.remove(at: first)
        }
    }

    /// remove all packets
    mutating func clear() {
        self.lock.withLock {
            self.packets = []
        }
    }

    private let lock: NSLock = NSLock()
    private(set) var packets: Array<MQTTPacket> = []
}
