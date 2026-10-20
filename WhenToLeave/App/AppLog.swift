import Foundation
import os

/// Mirrors app-level log lines to a small rolling text file so behaviour can be inspected without Console.app.
/// File: ~/Library/Application Support/WhenToLeave/app.log
enum AppLog {
    private static let logger = Logger(subsystem: "org.transportplannernz.WhenToLeave", category: "app")
    static let fileURL = URL(fileURLWithPath: AppModel.dbPath).deletingLastPathComponent().appendingPathComponent("app.log")
    private static let maxBytes = 512 * 1024
    private static let queue = DispatchQueue(label: "org.transportplannernz.WhenToLeave.log")

    static func note(_ message: String) { logger.notice("\(message, privacy: .public)"); append("NOTE", message) }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)"); append("ERR ", message) }

    private static func append(_ level: String, _ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(level) \(message)\n"
        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > maxBytes {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}
