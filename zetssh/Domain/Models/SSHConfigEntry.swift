import Foundation

/// Represents one parsed `Host` block from an SSH config file.
/// Wildcards (`Host *`) are excluded by the parser before this type is produced.
struct SSHConfigEntry: Identifiable, Hashable {
    /// The alias declared on the `Host` line (e.g. "myserver").
    var alias: String
    /// Resolved hostname — `HostName` value, or falls back to `alias` when absent.
    var hostname: String
    /// SSH username — `User` value, or `NSUserName()` when absent.
    var user: String
    /// TCP port — `Port` value, or 22 when absent.
    var port: Int
    /// Absolute path to the identity file after `~` expansion, or `nil` when absent.
    var identityFile: String?

    /// Stable identity for SwiftUI list diffing.
    var id: String { alias }
}
