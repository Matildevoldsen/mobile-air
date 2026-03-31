import Foundation

class DebugLogger {
    static let shared = DebugLogger()

    private let logFile: URL
    private let queue = DispatchQueue(label: "com.nativephp.debug-logger")
    private var recentEntries: [String] = []
    private let maxRecentEntries = 120

    private init() {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        logFile = appSupportPath.appendingPathComponent("nativephp_debug.log")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)

        // Create initial log entry
        log("=== NEW APP SESSION ===")
    }

    func log(_ message: String) {
        let timestamp = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        }.string(from: Date())

        let logEntry = "[\(timestamp)] \(message)\n"

        queue.sync {
            recentEntries.append(logEntry.trimmingCharacters(in: .newlines))

            if recentEntries.count > maxRecentEntries {
                recentEntries.removeFirst(recentEntries.count - maxRecentEntries)
            }

            // Write to file
            if let data = logEntry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    // Append to existing file
                    if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    // Create new file
                    try? data.write(to: logFile)
                }
            }
        }

        // Also print to console
        print("🐛 \(message)")
    }

    func snapshot(lines: Int = 60) -> String {
        queue.sync {
            recentEntries.suffix(lines).joined(separator: "\n")
        }
    }

    func getLogPath() -> String {
        return logFile.path
    }

    func clearLog() {
        queue.sync {
            recentEntries.removeAll()
            try? FileManager.default.removeItem(at: logFile)
        }

        log("=== LOG CLEARED ===")
    }
}

extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}