import Foundation

struct CodexInstallation {
    let executable: URL
    let environment: [String: String]
}

/// Discover installations without executing a login shell, startup files, or a CLI probe.
/// Finder/Launch Services does not inherit a Terminal session's PATH or nvm setup.
struct CodexDiscovery {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var standardDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    var appExecutables = [URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")]

    private func absoluteDirectories(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { $0.hasPrefix("/") && !$0.contains("\n") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { seen.insert($0).inserted }
    }

    private func executableFile(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func nvmDirectories() -> [String] {
        let roots = absoluteDirectories([
            environment["NVM_DIR"] ?? "",
            home.appendingPathComponent(".nvm").path,
            (environment["XDG_CONFIG_HOME"].map { $0 + "/nvm" }) ?? home.appendingPathComponent(".config/nvm").path
        ])
        return roots.flatMap { root -> [String] in
            let versions = URL(fileURLWithPath: root).appendingPathComponent("versions/node")
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
            // Use the newest installed Codex when no PATH entry selects a version.
            // Only version directory names are accepted, never shell aliases or commands.
            return entries.filter { $0.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil }
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { versions.appendingPathComponent($0).appendingPathComponent("bin").path }
        }
    }

    private func requiresNode(_ executable: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: executable) else { return false }
        defer { try? file.close() }
        let header = (try? file.read(upToCount: 256)) ?? Data()
        let line = String(decoding: header, as: UTF8.self).split(separator: "\n", maxSplits: 1).first ?? ""
        guard line.hasPrefix("#!") else { return false }
        let words = line.dropFirst(2).split(whereSeparator: { $0.isWhitespace })
        guard words.first == "/usr/bin/env" else { return false }
        return words.dropFirst().first == "node" || Array(words.dropFirst().prefix(2)) == ["-S", "node"]
    }

    func resolve(executable override: URL? = nil) throws -> CodexInstallation {
        let inherited = (environment["PATH"] ?? "").components(separatedBy: ":")
        let directories = absoluteDirectories(inherited + [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".npm/bin").path
        ] + standardDirectories + nvmDirectories())
        let candidates = override.map { [$0] } ?? (directories.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") } + appExecutables)
        var missingNode = false
        for candidate in candidates where candidate.path.hasPrefix("/") && executableFile(candidate) {
            let resolved = candidate.resolvingSymlinksInPath()
            var runtimeDirectories = [candidate.deletingLastPathComponent().path, resolved.deletingLastPathComponent().path]
            // npm's bin symlink may itself be linked from ~/.local/bin. Recover the
            // installation prefix so env node uses the Node paired with that npm install.
            if let range = resolved.path.range(of: "/lib/node_modules/") {
                runtimeDirectories.insert(String(resolved.path[..<range.lowerBound]) + "/bin", at: 0)
            }
            let launchDirectories = absoluteDirectories(runtimeDirectories + directories)
            if requiresNode(candidate) && !launchDirectories.contains(where: { executableFile(URL(fileURLWithPath: $0).appendingPathComponent("node")) }) {
                missingNode = true
                continue
            }
            var childEnvironment = environment
            childEnvironment["PATH"] = launchDirectories.joined(separator: ":")
            for key in ["CODEX_THREAD_ID", "CODEX_INTERNAL_ORIGINATOR_OVERRIDE", "CODEX_MANAGED_BY_NPM", "CODEX_MANAGED_BY_BUN"] {
                childEnvironment.removeValue(forKey: key)
            }
            return CodexInstallation(executable: candidate, environment: childEnvironment)
        }
        if missingNode {
            throw AppError.message("Codex CLI was found, but its Node.js runtime wasn't found. Repair the Node.js installation used by npm, then try again.")
        }
        throw AppError.message("Codex CLI wasn't found. Install Codex CLI and run ‘codex login’ once in Terminal, then try again.")
    }
}
