import Foundation

enum SSHConfigParser {
    /// Parses the text content of an SSH config file and returns one
    /// `SSHConfigEntry` per non-wildcard `Host` block.
    static func parse(content: String) -> [SSHConfigEntry] {
        var entries: [SSHConfigEntry] = []
        var current: SSHConfigEntry?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.components(separatedBy: .whitespaces)
            guard parts.count >= 2 else { continue }

            let key   = parts[0].lowercased()
            let value = parts[1...].joined(separator: " ")

            switch key {
            case "host":
                if let c = current, c.alias != "*" {
                    entries.append(c)
                }
                current = SSHConfigEntry(
                    alias: value,
                    hostname: value,
                    user: NSUserName(),
                    port: 22,
                    identityFile: nil
                )

            case "hostname":
                current?.hostname = value

            case "user":
                current?.user = value

            case "port":
                current?.port = Int(value) ?? 22

            case "identityfile":
                let expanded = value.replacingOccurrences(of: "~", with: NSHomeDirectory())
                current?.identityFile = expanded

            default:
                break
            }
        }

        if let c = current, c.alias != "*" {
            entries.append(c)
        }

        return entries
    }

    /// Convenience overload: reads a file URL and delegates to `parse(content:)`.
    static func parse(url: URL) -> [SSHConfigEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(content: content)
    }
}
