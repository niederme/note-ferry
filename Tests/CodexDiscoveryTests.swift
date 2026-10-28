import Foundation

extension CoreTests {
    static func codexDiscoveryTests(root: URL) throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("note-ferry-discovery-" + UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        func configuration(_ name: String) throws -> CodexDiscovery {
            let home = temporary.appendingPathComponent(name)
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            return CodexDiscovery(environment: ["HOME": home.path], home: home, standardDirectories: [], appExecutables: [])
        }
        @discardableResult func write(_ url: URL, _ contents: String = "#!/bin/sh\nexit 0\n", executable: Bool = true) throws -> URL {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
            return url
        }
        func expectFailure(_ configuration: CodexDiscovery, containing text: String) {
            do { _ = try configuration.resolve(); fatalError("Invalid installation accepted") }
            catch { check(error.localizedDescription.contains(text), "Wrong discovery error: " + error.localizedDescription) }
        }
        func resolved(_ configuration: CodexDiscovery, equals expected: URL, _ message: String) throws {
            let actual = try configuration.resolve()
            check(actual.executable == expected, message)
        }
        let defaults = CodexDiscovery()
        check(defaults.standardDirectories.contains("/opt/homebrew/bin") && defaults.standardDirectories.contains("/usr/local/bin"), "Homebrew locations lost")
        check(defaults.appExecutables.first?.path == "/Applications/Codex.app/Contents/Resources/codex", "App bundle fallback lost")
        for location in [".local/bin", ".npm-global/bin", ".npm/bin"] {
            let config = try configuration(location.replacingOccurrences(of: "/", with: "-"))
            let codex = try write(config.home.appendingPathComponent(location + "/codex"))
            try resolved(config, equals: codex, "User install not found: " + location)
        }
        var standard = try configuration("standard")
        let standardBin = standard.home.appendingPathComponent("homebrew/bin")
        standard.standardDirectories = [standardBin.path]
        let standardCodex = try write(standardBin.appendingPathComponent("codex"))
        try resolved(standard, equals: standardCodex, "Standard installation not found")
        var app = try configuration("app")
        let bundled = try write(app.home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"))
        app.appExecutables = [bundled]
        try resolved(app, equals: bundled, "Bundled installation not found without Node")

        var path = try configuration("custom path with spaces")
        let customBin = path.home.appendingPathComponent("custom npm prefix/bin")
        let customCodex = try write(customBin.appendingPathComponent("codex"))
        path.environment["PATH"] = ":relative/bin:" + customBin.path + ":" + customBin.path
        let selected = try path.resolve()
        check(selected.executable == customCodex, "Inherited PATH with spaces was ignored")
        let launchPath = selected.environment["PATH"]!.components(separatedBy: ":")
        check(launchPath.allSatisfy { $0.hasPrefix("/") } && Set(launchPath).count == launchPath.count, "Relative/empty/duplicate PATH entries survived")
        _ = try write(path.home.appendingPathComponent(".local/bin/codex"))
        try resolved(path, equals: customCodex, "Inherited PATH did not take precedence")

        let missing = try configuration("missing")
        expectFailure(missing, containing: "CLI wasn't found")
        let invalid = try configuration("invalid")
        _ = try write(invalid.home.appendingPathComponent(".local/bin/codex"), executable: false)
        try fm.createDirectory(at: invalid.home.appendingPathComponent(".npm/bin/codex"), withIntermediateDirectories: true)
        try fm.createDirectory(at: invalid.home.appendingPathComponent(".npm-global/bin"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: invalid.home.appendingPathComponent(".npm-global/bin/codex"), withDestinationURL: invalid.home.appendingPathComponent("absent"))
        expectFailure(invalid, containing: "CLI wasn't found")
        var relative = try configuration("relative")
        relative.environment["PATH"] = ":.:Tests"
        expectFailure(relative, containing: "CLI wasn't found")

        let nodeScript = "#!/usr/bin/env node\nexit 0\n"
        let missingNode = try configuration("missing node")
        _ = try write(missingNode.home.appendingPathComponent(".local/bin/codex"), nodeScript)
        expectFailure(missingNode, containing: "Node.js runtime wasn't found")
        _ = try write(missingNode.home.appendingPathComponent(".local/bin/node"), executable: false)
        expectFailure(missingNode, containing: "Node.js runtime wasn't found")
        // An unusable npm install must not hide a usable native app installation.
        var fallback = missingNode
        fallback.appExecutables = [bundled]
        try resolved(fallback, equals: bundled, "Broken npm install hid a usable native CLI")

        var gui = try configuration("GUI home with spaces")
        gui.environment["PATH"] = "/usr/bin:/bin"
        let nvmBin = gui.home.appendingPathComponent(".nvm/versions/node/v22.12.0/bin")
        let olderBin = gui.home.appendingPathComponent(".nvm/versions/node/v9.9.0/bin")
        let guiCodex = try write(nvmBin.appendingPathComponent("codex"), nodeScript)
        _ = try write(nvmBin.appendingPathComponent("node"))
        _ = try write(olderBin.appendingPathComponent("codex"), nodeScript)
        _ = try write(olderBin.appendingPathComponent("node"))
        // A newer Node with no Codex must not hide the installed Codex.
        _ = try write(gui.home.appendingPathComponent(".nvm/versions/node/v100.0.0/bin/node"))
        try resolved(gui, equals: guiCodex, "GUI launch did not find the newest installed nvm Codex")
        let startupMarker = gui.home.appendingPathComponent("startup-was-run")
        _ = try write(gui.home.appendingPathComponent(".zshrc"), "touch '\(startupMarker.path)'\n", executable: false)
        _ = try gui.resolve()
        check(!fm.fileExists(atPath: startupMarker.path), "Discovery ran shell startup files")
        var chosenVersion = gui
        chosenVersion.environment["PATH"] = olderBin.path
        try resolved(chosenVersion, equals: olderBin.appendingPathComponent("codex"), "Explicit PATH nvm version was ignored")
        for (variable, directory) in [("NVM_DIR", "custom nvm root"), ("XDG_CONFIG_HOME", "custom config")] {
            var config = try configuration(variable)
            let base = config.home.appendingPathComponent(directory)
            config.environment[variable] = base.path
            let nvmRoot = variable == "NVM_DIR" ? base : base.appendingPathComponent("nvm")
            let bin = nvmRoot.appendingPathComponent("versions/node/v24.1.0/bin")
            let codex = try write(bin.appendingPathComponent("codex"), nodeScript)
            _ = try write(bin.appendingPathComponent("node"))
            try resolved(config, equals: codex, "Custom nvm root was ignored: " + variable)
        }
        let xdgDefault = try configuration("xdg default")
        let xdgBin = xdgDefault.home.appendingPathComponent(".config/nvm/versions/node/v24.1.0/bin")
        let xdgCodex = try write(xdgBin.appendingPathComponent("codex"), nodeScript)
        _ = try write(xdgBin.appendingPathComponent("node"))
        try resolved(xdgDefault, equals: xdgCodex, "Default XDG nvm root was ignored")

        // Simulate npm's env-node entry point end to end. No real Node, Codex,
        // account, transcript, or network request is used by this fixture.
        let runtimeResult = gui.home.appendingPathComponent("runtime-used")
        _ = try write(nvmBin.appendingPathComponent("node"), """
        #!/bin/sh
        [ -z "${CODEX_THREAD_ID+x}${CODEX_INTERNAL_ORIGINATOR_OVERRIDE+x}${CODEX_MANAGED_BY_NPM+x}${CODEX_MANAGED_BY_BUN+x}" ] || exit 81
        printf '%s' "$0" > "$NF_TEST_RUNTIME_RESULT"
        exec /bin/sh "$@"
        """ + "\n")
        let fixturePath = root.appendingPathComponent("Tests/fixture.json").path.replacingOccurrences(of: "'", with: "'\\''")
        _ = try write(guiCodex, """
        #!/usr/bin/env node
        DEST=''
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output-last-message) DEST="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        /bin/cat >/dev/null
        /bin/cp '\(fixturePath)' "$DEST"
        """ + "\n")
        gui.environment["NF_TEST_RUNTIME_RESULT"] = runtimeResult.path
        for key in ["CODEX_THREAD_ID", "CODEX_INTERNAL_ORIGINATOR_OVERRIDE", "CODEX_MANAGED_BY_NPM", "CODEX_MANAGED_BY_BUN"] {
            gui.environment[key] = "synthetic-parent-value"
        }
        let generated = try CodexRunner().run(transcript: String(repeating: "Synthetic meeting text. ", count: 10), resources: root.appendingPathComponent("Resources"), discovery: gui)
        check(!generated.title.isEmpty, "Discovered npm launcher did not return a summary")
        let runtimeUsed = try String(contentsOf: runtimeResult, encoding: .utf8)
        check(runtimeUsed == nvmBin.appendingPathComponent("node").path, "GUI npm launcher used the wrong Node runtime")

        // A ~/.local/bin alias to an npm package must recover its npm prefix,
        // even with a different Node earlier in the inherited PATH.
        var symlink = try configuration("symlink")
        let prefix = symlink.home.appendingPathComponent("node prefix with spaces")
        let target = try write(prefix.appendingPathComponent("lib/node_modules/@openai/codex/bin/codex.js"), "#!/usr/bin/env -S node --no-warnings\n")
        let pairedNode = try write(prefix.appendingPathComponent("bin/node"))
        let link = symlink.home.appendingPathComponent(".local/bin/codex")
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let otherBin = symlink.home.appendingPathComponent("other/bin")
        _ = try write(otherBin.appendingPathComponent("node"))
        symlink.environment["PATH"] = otherBin.path
        let linked = try symlink.resolve()
        check(linked.executable == link, "Symlinked npm launcher was rejected")
        check(linked.environment["PATH"]!.components(separatedBy: ":").first == pairedNode.deletingLastPathComponent().path, "Symlinked npm launcher's matching Node was not preferred")
        try fm.removeItem(at: pairedNode)
        try fm.removeItem(at: otherBin.appendingPathComponent("node"))
        expectFailure(symlink, containing: "Node.js runtime wasn't found")
    }
}
