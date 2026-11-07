import Foundation
import os

/// A plain log at ~/Library/Logs/Oatmeal/oatmeal.log (also in Console under com.oatmeal.app), so
/// "why didn't it hear me?" has an answer. Never log what someone said: counts and levels only.
enum DFLog {
    private static let logger = Logger(subsystem: "com.oatmeal.app", category: "app")
    private static let queue = DispatchQueue(label: "com.oatmeal.log")
    private static let maxBytes = 2_000_000

    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Oatmeal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("oatmeal.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ area: String, _ message: String) {
        logger.log("[\(area, privacy: .public)] \(message, privacy: .public)")
        let now = Date()
        queue.async {
            let line = "\(stamp.string(from: now)) [\(area)] \(message)\n"
            let fm = FileManager.default
            // Roll over at 2 MB, keeping one old file.
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = url.deletingPathExtension().appendingPathExtension("old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
