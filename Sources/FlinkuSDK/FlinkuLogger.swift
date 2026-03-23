import Foundation

struct FlinkuLogger {
    static var debugMode: Bool = false

    static func log(_ message: String) {
        guard debugMode else { return }
        print("[FlinkuSDK] \(message)")
    }

    static func error(_ message: String) {
        print("[FlinkuSDK][ERROR] \(message)")
    }
}
