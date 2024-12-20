//
//  Lock.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/12.
//

import Foundation

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
/// AtomLock An `os_unfair_lock` wrapper.
class Lock{
    private let unfair: os_unfair_lock_t
    deinit {
        unfair.deinitialize(count: 1)
        unfair.deallocate()
    }
    public init() {
        unfair = .allocate(capacity: 1)
        unfair.initialize(to: os_unfair_lock())
    }
    /// lock
    public func lock(){
        os_unfair_lock_lock(unfair)
    }
    /// unlock
    /// - Important: If `unlock` before `lock`
    public func unlock(){
        os_unfair_lock_unlock(unfair)
    }
}
#endif

#if os(Linux) || os(Windows)
public typealias Lock = NSLock
#endif


/// A thread-safe wrapper around a value.
@dynamicMemberLookup
@propertyWrapper
class Atomic<T> {
    private var value: T
    private let lock: Lock = Lock()
    public var projectedValue: Atomic<T> { self }
    init(wrappedValue: T) {
        self.value = wrappedValue
    }
    var wrappedValue: T {
        get { around { value } }
        set { around { value = newValue } }
    }
    /// around some safer codes
    func around<U>(_ closure: () throws -> U) rethrows -> U {
        lock.lock()
        defer { lock.unlock() }
        return try closure()
    }
    /// Access any suvalue of T
    func read<U>(_ closure: (T) throws -> U) rethrows -> U {
        try around { try closure(self.value) }
    }
    /// Modify Any suvalue of T
    func write<U>(_ closure: (inout T) throws -> U) rethrows -> U {
        try around { try closure(&self.value) }
    }
    /// Access  the protected Dictionary or Array.
    subscript<Property>(dynamicMember keyPath: WritableKeyPath<T, Property>) -> Property {
        get { around { self.value[keyPath: keyPath] } }
        set { around { self.value[keyPath: keyPath] = newValue } }
    }
    /// Access  the protected Dictionary or Array.
    subscript<Property>(dynamicMember keyPath: KeyPath<T, Property>) -> Property {
        get { around { self.value[keyPath: keyPath] } }
    }
}
