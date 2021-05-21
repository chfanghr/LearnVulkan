//
//  Utilities.swift
//
//
//  Created by 方泓睿 on 2021/5/20.
//

import Foundation

public func toString<T>(_ value: T) -> String {
    withUnsafePointer(to: value) { ptr in
        ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: value)) {
            String(cString: $0)
        }
    }
}

public func vkMakeApiVersion(_ variant: UInt32, _ major: UInt32, _ minor: UInt32, _ patch: UInt32) -> UInt32 {
    variant << 29 | (major << 22 | (minor << 12 | patch))
}

public let vkApiVersion10 = vkMakeApiVersion(0, 1, 0, 0)

public func swiftStringsToCConstStringArray(_ strings: [String]) -> [UnsafePointer<CChar>?] {
    strings.map { UnsafePointer<CChar>?(strdup($0)) }
}

public func freeCConstStringArray(_ arr: [UnsafePointer<CChar>?]) {
    arr.forEach { free(.init(mutating: $0)) }
}

public func swiftStringToCConstString(_ string: String) -> UnsafePointer<CChar>? {
    .init(strdup(string))
}

public func freeCConstString(_ ptr: UnsafePointer<CChar>?) {
    free(.init(mutating: ptr))
}

public func cConstStringArrayToSwiftStrings(_ pp: UnsafeMutablePointer<UnsafePointer<CChar>?>?, count: UInt32) -> [String] {
    (0 ..< count).map {
        cConstStringToSwiftString(pp![Int($0)])
    }
}

public func cConstStringToSwiftString(_ p: UnsafePointer<CChar>!) -> String {
    String(cString: p)
}

public func clamp<T>(_ value: T, in rng: ClosedRange<T>) -> T where T: Comparable {
    if value < rng.lowerBound {
        return rng.lowerBound
    }

    if value > rng.upperBound {
        return rng.upperBound
    }

    return value
}

public class SharedWrapper<T> {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }
}
