import Foundation
import Combine
import Darwin

enum LogLevel: String, Codable {
    case info = "INFO"
    case success = "OK"
    case warning = "WARN"
    case error = "ERR"
    case trace = "TRACE"

    var symbol: String {
        switch self {
        case .info: return "•"
        case .success: return "✓"
        case .warning: return "!"
        case .error: return "×"
        case .trace: return "›"
        }
    }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let message: String

    var timestamp: String { LogEntry.timeFormatter.string(from: date) }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var revision: Int = 0

    private let limit = 1200
    private let lock = NSLock()

    func append(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(date: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.limit {
                self.entries.removeFirst(self.entries.count - self.limit)
            }
            self.revision &+= 1
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
            self.revision &+= 1
        }
    }

    /// Plain-text copy of every visible line, for the Copy / Share buttons.
    var transcript: String {
        entries
            .map { "\($0.timestamp) \($0.level.rawValue) \($0.message)" }
            .joined(separator: "\n")
    }
}

func log(_ message: String, level: LogLevel = .info) {
    AppLog.shared.append(message, level: level)
}

private var logCapturePipe: Pipe?

/// Redirects stdout/stderr into the in-app log so the C exploit and the Rust
/// transport print their progress without a debugger attached.
func setupLogCapture() {
    guard logCapturePipe == nil else { return }
    let pipe = Pipe()
    logCapturePipe = pipe

    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    let fd = pipe.fileHandleForWriting.fileDescriptor
    guard dup2(fd, STDOUT_FILENO) >= 0, dup2(fd, STDERR_FILENO) >= 0 else {
        log("Log capture could not attach to stdout/stderr", level: .warning)
        logCapturePipe = nil
        return
    }

    pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AppLog.shared.append(trimmed, level: .trace)
    }
}
