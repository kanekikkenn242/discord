import Foundation
import Darwin

func sandbox_extension_consume(_ token: String) -> Int64? {
    typealias Function = @convention(c) (UnsafePointer<CChar>?) -> Int64
    guard let library = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(library) }
    guard let symbol = dlsym(library, "sandbox_extension_consume") else { return nil }
    let function = unsafeBitCast(symbol, to: Function.self)
    return function(token)
}

func sandbox_extension_issue_file(path: String) -> String? {
    typealias Function = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32, Int32) -> UnsafeMutablePointer<CChar>?
    guard let library = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(library) }
    guard let symbol = dlsym(library, "sandbox_extension_issue_file") else { return nil }
    let function = unsafeBitCast(symbol, to: Function.self)
    guard let pointer = function("com.apple.app-sandbox.read-write", path, 0, 0) else { return nil }
    defer { free(pointer) }
    return String(cString: pointer)
}
