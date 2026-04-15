import Foundation
import OSLog

public enum LoggerLevel {
    case trace, debug, info, warning, error, fault
}

public final class AppLogger {
    public static let shared = AppLogger()
    
    public let system = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.zetssh", category: "System")
    public let network = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.zetssh", category: "Network")
    public let database = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.zetssh", category: "Database")
    public let security = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.zetssh", category: "Security")
    
    private init() {}
    
    public func log(_ message: String, category: Category = .system, level: LoggerLevel = .info) {
        let targetLogger: Logger
        switch category {
        case .system: targetLogger = system
        case .network: targetLogger = network
        case .database: targetLogger = database
        case .security: targetLogger = security
        }
        
        switch level {
        case .trace, .debug:
            targetLogger.debug("\(message, privacy: .public)")
        case .info:
            targetLogger.info("\(message, privacy: .public)")
        case .warning:
            targetLogger.warning("\(message, privacy: .public)")
        case .error:
            targetLogger.error("\(message, privacy: .public)")
        case .fault:
            targetLogger.fault("\(message, privacy: .public)")
        }
    }
    
    public enum Category {
        case system, network, database, security
    }
}
