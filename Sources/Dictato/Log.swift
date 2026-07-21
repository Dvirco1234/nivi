import Foundation
import os
import DictatoCore

enum Log {
    private static let logger = Logger(subsystem: "com.dvir.dictato", category: "app")
    private static let queue = DispatchQueue(label: "com.dvir.dictato.log")
    private static let maxFileSize = 5 * 1024 * 1024

    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Dictato", isDirectory: true)
    }

    private static var fileURL: URL { logDirectory.appendingPathComponent("dictato.log") }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write("INFO  \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        write("ERROR \(message)")
    }

    static func debug(_ message: String) {
        guard Settings().verboseLogging else { return }
        logger.debug("\(message, privacy: .public)")
        write("DEBUG \(message)")
    }

    private static func write(_ line: String) {
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            rotateIfNeeded()
            let stamp = ISO8601DateFormatter().string(from: Date())
            let data = Data("\(stamp) \(line)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int,
              size > maxFileSize else { return }
        let old = logDirectory.appendingPathComponent("dictato.log.old")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: fileURL, to: old)
    }
}
