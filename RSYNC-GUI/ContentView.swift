//
//  ContentView.swift
//  RSYNC-GUI
//
//  Created by FreQRiDeR on 9/15/25.
//

import SwiftUI
import AppKit
import Foundation
import Darwin

struct ContentView: View {
    // Local source/target
    @State private var localSource: String = ""
    @State private var localTarget: String = ""

    // Remote source/target (ssh user@host:path)
    @State private var remoteSource: String = ""
    @State private var remoteTarget: String = ""
    // Remote browser presentation
    @State private var showingRemoteBrowserForSource = false
    @State private var showingRemoteBrowserForTarget = false
    // Remote passwords
    @State private var sourceUsePassword = false
    @State private var sourcePassword: String = ""
    @State private var targetUsePassword = false
    @State private var targetPassword: String = ""
    
    // SSH key options
    @State private var sourceUseSSHKey = false
    @State private var sourceSSHKeyPath: String = ""
    @State private var targetUseSSHKey = false
    @State private var targetSSHKeyPath: String = ""

    // Flags for whether source/target are remote
    @State private var sourceIsRemote = false
    @State private var targetIsRemote = false

    // rsync options
    @State private var optArchive = true
    @State private var optVerbose = false
    @State private var optHumanReadable = true
    @State private var optProgress = true
    @State private var optDelete = false
    @State private var optDryRun = false

    // Copy folder contents vs folder itself
    @State private var copyContents = false

    // Rsync manager
    @StateObject private var rsyncManager = RsyncManager()

    // Convenience computed properties
    var sourceProvided: Bool {
        if sourceIsRemote {
            return !remoteSource.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !localSource.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var targetProvided: Bool {
        if targetIsRemote {
            return !remoteTarget.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !localTarget.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var commandPreview: String {
        var parts: [String] = []
        // base rsync binary
        parts.append("rsync")

        // options
        if optArchive { parts.append("-a") }
        if optVerbose { parts.append("-v") }
        if optHumanReadable { parts.append("-h") }
        if optProgress { parts.append("--progress") }
        if optDelete { parts.append("--delete") }
        if optDryRun { parts.append("--dry-run") }

        // remote shell (use ssh) if either endpoint is remote
        if sourceIsRemote || targetIsRemote {
            var sshOptions = [
                "-oStrictHostKeyChecking=no",
                "-oUserKnownHostsFile=/dev/null",
                "-oGlobalKnownHostsFile=/dev/null"
            ]
            
            // Add SSH key options if specified
            if sourceIsRemote && sourceUseSSHKey && !sourceSSHKeyPath.isEmpty {
                sshOptions.append("-i \"\(sourceSSHKeyPath)\"")
            } else if targetIsRemote && targetUseSSHKey && !targetSSHKeyPath.isEmpty {
                sshOptions.append("-i \"\(targetSSHKeyPath)\"")
            }
            
            // Authentication preferences
            if sourceUsePassword || targetUsePassword {
                sshOptions.append("-oPasswordAuthentication=yes")
                sshOptions.append("-oPubkeyAuthentication=no")
            } else {
                sshOptions.append("-oPreferredAuthentications=publickey")
            }
            
            let sshCmd = "ssh " + sshOptions.joined(separator: " ")
            parts.append("-e \"\(sshCmd)\"")
        }

        // source and target strings
        func quoted(_ s: String) -> String { return "\"\(s)\"" }

        var src = sourceIsRemote ? remoteSource : localSource
        var dst = targetIsRemote ? remoteTarget : localTarget

        // Normalize remote spec to user@host:/path so rsync treats it as remote
        func normalizeRemote(_ s: String) -> String {
            // If it already contains a ':', assume it's correct
            guard s.contains("@"), !s.contains(":") else { return s }
            // Insert ':' before first '/' (start of the path), or append ':' if no path provided
            if let slash = s.firstIndex(of: "/") {
                let before = String(s[..<slash])
                let after = String(s[slash...])
                return before + ":" + after
            } else {
                return s + ":"
            }
        }

        if sourceIsRemote { src = normalizeRemote(src) }
        if targetIsRemote { dst = normalizeRemote(dst) }

        if copyContents {
            if !src.isEmpty && !src.hasSuffix("/") { src += "/" }
        }

        parts.append(quoted(src))
        parts.append(quoted(dst))

        return parts.joined(separator: " ")
    }

    // Execution
    @State private var outputLog: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                GroupBox("Source") {
                    HStack {
                        Toggle(isOn: $sourceIsRemote) {
                            Text("Remote")
                        }
                        .toggleStyle(.switch)
                        Spacer()
                    }

                    if sourceIsRemote {
                        HStack {
                            TextField("user@host:/path/to/dir", text: $remoteSource)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { showingRemoteBrowserForSource = true }) {
                                Label("Browse", systemImage: "network")
                            }
                            .help("Open SFTP browser for the remote host (requires key-based auth or agent).")
                        }
                        if sourceUsePassword {
                            SecureField("Remote password", text: $sourcePassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        Toggle("Use password for remote", isOn: $sourceUsePassword)
                            .toggleStyle(.checkbox)
                        
                        Toggle("Use SSH key", isOn: $sourceUseSSHKey)
                            .toggleStyle(.checkbox)
                        
                        if sourceUseSSHKey {
                            HStack {
                                TextField("SSH key path (e.g., ~/.ssh/rsync_app_key)", text: $sourceSSHKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: pickSSHKeyForSource) {
                                    Label("Browse", systemImage: "key")
                                }
                            }
                        }
                    } else {
                        HStack {
                            TextField("/local/path/to/source", text: $localSource)
                                .textFieldStyle(.roundedBorder)
                            Button(action: pickLocalSource) {
                                Label("Browse", systemImage: "folder")
                            }
                        }
                    }
                }

                GroupBox("Target") {
                    HStack {
                        Toggle(isOn: $targetIsRemote) {
                            Text("Remote")
                        }
                        .toggleStyle(.switch)
                        Spacer()
                    }

                    if targetIsRemote {
                        HStack {
                            TextField("user@host:/path/to/dir", text: $remoteTarget)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { showingRemoteBrowserForTarget = true }) {
                                Label("Browse", systemImage: "network")
                            }
                            .help("Open SFTP browser for the remote host (requires key-based auth or agent).")
                        }
                        if targetUsePassword {
                            SecureField("Remote password", text: $targetPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        Toggle("Use password for remote", isOn: $targetUsePassword)
                            .toggleStyle(.checkbox)
                        
                        Toggle("Use SSH key", isOn: $targetUseSSHKey)
                            .toggleStyle(.checkbox)
                        
                        if targetUseSSHKey {
                            HStack {
                                TextField("SSH key path (e.g., ~/.ssh/rsync_app_key)", text: $targetSSHKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: pickSSHKeyForTarget) {
                                    Label("Browse", systemImage: "key")
                                }
                            }
                        }
                    } else {
                        HStack {
                            TextField("/local/path/to/target", text: $localTarget)
                                .textFieldStyle(.roundedBorder)
                            Button(action: pickLocalTarget) {
                                Label("Browse", systemImage: "folder")
                            }
                        }
                    }
                }

                GroupBox("Options") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Archive (-a)", isOn: $optArchive)
                        Text("Preserve permissions, times, symbolic links, etc.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Verbose (-v)", isOn: $optVerbose)
                        Toggle("Human readable (-h)", isOn: $optHumanReadable)
                        Toggle("Show progress (--progress)", isOn: $optProgress)
                        Toggle("Delete existing on target (--delete)", isOn: $optDelete)
                        Toggle("Dry run (--dry-run)", isOn: $optDryRun)

                        Toggle("Copy contents of folder (trailing slash)", isOn: $copyContents)
                            .help("When true, a trailing slash will be added to source to copy contents rather than the folder itself.")
                    }
                }

                GroupBox("Command Preview") {
                    ScrollView(.horizontal) {
                        Text(commandPreview)
                            .font(.system(.body, design: .monospaced))
                            .padding(6)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: runRsync) {
                        Label(rsyncManager.isRunning ? "Running..." : "Run rsync", systemImage: "play.fill")
                    }
                    .disabled(rsyncManager.isRunning || (!sourceProvided) || (!targetProvided))

                    Button(action: stopRsync) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!rsyncManager.isRunning)

                    Spacer()

                    Text(rsyncManager.isRunning ? "Running" : "Ready")
                        .foregroundColor(rsyncManager.isRunning ? .accentColor : .secondary)
                }

                GroupBox("Output") {
                    // Use a selectable TextEditor so the user can select and copy output
                    TextEditor(text: $outputLog)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(minHeight: 120)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("RSYNC GUI")
            .sheet(isPresented: $showingRemoteBrowserForSource) {
                RemoteBrowserView(initialRemote: remoteSource, password: sourceUsePassword ? sourcePassword : nil) { selection in
                    remoteSource = selection
                }
            }
            .sheet(isPresented: $showingRemoteBrowserForTarget) {
                RemoteBrowserView(initialRemote: remoteTarget, password: targetUsePassword ? targetPassword : nil) { selection in
                    remoteTarget = selection
                }
            }
        .frame(minWidth: 800, minHeight: 700)
    }

    // MARK: - Local file pickers
    func pickLocalSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                localSource = url.path
            }
        }
    }

    func pickLocalTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                localTarget = url.path
            }
        }
    }
    
    func pickSSHKeyForSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                sourceSSHKeyPath = url.path
            }
        }
    }
    
    func pickSSHKeyForTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                targetSSHKeyPath = url.path
            }
        }
    }

    // MARK: - Running rsync with AppleScript implementation
    func runRsync() {
        outputLog = ""
        
        // Build configuration
        var options: [String] = []
        if optArchive { options.append("-a") }
        if optVerbose { options.append("-v") }
        if optHumanReadable { options.append("-h") }
        if optProgress { options.append("--progress") }
        if optDelete { options.append("--delete") }
        if optDryRun { options.append("--dry-run") }
        
        // Determine source and destination
        var source = sourceIsRemote ? remoteSource : localSource
        var destination = targetIsRemote ? remoteTarget : localTarget
        
        // Handle copy contents option
        if copyContents && !source.isEmpty && !source.hasSuffix("/") {
            source += "/"
        }
        
        // Normalize remote paths
        if sourceIsRemote {
            source = normalizeRemotePath(source)
        }
        if targetIsRemote {
            destination = normalizeRemotePath(destination)
        }
        
        // Determine password usage and SSH key
        let usePassword: Bool
        let password: String?
        let keyPath: String?
        
        if sourceIsRemote && sourceUsePassword {
            usePassword = true
            password = sourcePassword.isEmpty ? nil : sourcePassword
            keyPath = sourceUseSSHKey ? sourceSSHKeyPath : nil
        } else if targetIsRemote && targetUsePassword {
            usePassword = true
            password = targetPassword.isEmpty ? nil : targetPassword
            keyPath = targetUseSSHKey ? targetSSHKeyPath : nil
        } else {
            usePassword = false
            password = nil
            keyPath = (sourceIsRemote && sourceUseSSHKey) ? sourceSSHKeyPath :
                     (targetIsRemote && targetUseSSHKey) ? targetSSHKeyPath : nil
        }
        
        let config = RsyncManager.RsyncConfig(
            source: source,
            destination: destination,
            options: options,
            usePassword: usePassword,
            password: password,
            sshKeyPath: keyPath,
            sshKeyPassphrase: nil
        )
        
        // FIXED: Removed [weak self] and DispatchQueue wrapper
        rsyncManager.executeRsync(config: config) { output in
            appendOutput(output)
        }
    }

    func stopRsync() {
        rsyncManager.stopRsync()
        appendOutput("\nUser terminated process\n")
    }

    func appendOutput(_ s: String) {
        outputLog += s
    }
    
    private func normalizeRemotePath(_ path: String) -> String {
        guard path.contains("@"), !path.contains(":") else { return path }
        
        if let slashIndex = path.firstIndex(of: "/") {
            let hostPart = String(path[..<slashIndex])
            let pathPart = String(path[slashIndex...])
            return hostPart + ":" + pathPart
        } else {
            return path + ":"
        }
    }
}

// MARK: - Remote browser view

struct RemoteEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}

struct RemoteBrowserView: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var host: String
    @State private var path: String
    let password: String?
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var errorMessage: String = ""

    let onSelect: (String) -> Void

    init(initialRemote: String = "", password: String? = nil, onSelect: @escaping (String) -> Void) {
        // parse initialRemote like user@host:/path
        var parsedHost = ""
        var parsedPath = "."
        if let colonIndex = initialRemote.firstIndex(of: ":") {
            parsedHost = String(initialRemote[..<colonIndex])
            parsedPath = String(initialRemote[initialRemote.index(after: colonIndex)...])
            if parsedPath.isEmpty { parsedPath = "." }
        } else if !initialRemote.isEmpty {
            parsedHost = initialRemote
            parsedPath = "."
        }
        _host = State(initialValue: parsedHost)
        _path = State(initialValue: parsedPath)
        self.onSelect = onSelect
        self.password = password
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("user@host", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("/remote/path", text: $path)
                    .textFieldStyle(.roundedBorder)
                Button("Connect") { listDirectory() }
            }
            .padding()

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding([.leading, .trailing])
            }

            List(entries) { entry in
                HStack {
                    Image(systemName: entry.isDirectory ? "folder" : "doc")
                    Text(entry.name)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if entry.isDirectory {
                        // navigate into directory
                        if path.hasSuffix("/") {
                            path += entry.name
                        } else if path == "." || path == "~" {
                            path = entry.name
                        } else {
                            path += "/\(entry.name)"
                        }
                        listDirectory()
                    } else {
                        // select file
                        let selection = "\(host):\(path.hasSuffix("/") ? path + entry.name : path + "/" + entry.name)"
                        onSelect(selection)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }

            HStack {
                Button("Up") {
                    // go up one directory
                    if path == "." || path == "/" || path == "~" { path = "/" }
                    else if let last = path.lastIndex(of: "/") {
                        let newPath = String(path[..<last])
                        path = newPath.isEmpty ? "/" : newPath
                    }
                    listDirectory()
                }
                Spacer()
                Button("Select Current") {
                    let selection = "\(host):\(path)"
                    onSelect(selection)
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { if !host.isEmpty { listDirectory() } }
    }

    // FIXED: Replaced with AppleScript implementation
    func listDirectory() {
        guard !host.isEmpty else { errorMessage = "Please enter user@host"; return }
        errorMessage = ""
        loading = true
        
        // Use AppleScript for SSH directory listing
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\"'\"'")
        
        if let pw = password, !pw.isEmpty {
            // Use expect for password authentication
            let escapedPassword = pw.replacingOccurrences(of: "'", with: "'\"'\"'")
            let expectCommand = """
            expect -c "
            spawn ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null -oPasswordAuthentication=yes -oPubkeyAuthentication=no \(host) ls -la '\(escapedPath)'
            expect {
                -re \\".*assword.*:\\" { send \\"\(escapedPassword)\\\\r\\"; exp_continue }
                -re \\".*yes/no.*\\" { send \\"yes\\\\r\\"; exp_continue }
                eof { exit }
                timeout { exit 1 }
            }
            "
            """
            executeAppleScriptCommand(expectCommand)
        } else {
            // Use standard SSH for key-based authentication
            let command = "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null \(host) ls -la '\(escapedPath)'"
            executeAppleScriptCommand(command)
        }
    }
    
    private func executeAppleScriptCommand(_ command: String) {
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"")
        
        let appleScript = """
        do shell script "\(escapedCommand)"
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: appleScript)
            var errorDict: NSDictionary?
            let result = script?.executeAndReturnError(&errorDict)
            
            DispatchQueue.main.async {
                self.loading = false
                
                if let error = errorDict {
                    let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                    self.errorMessage = errorMessage
                    self.entries = []
                } else if let output = result?.stringValue {
                    self.parseDirectoryListing(output)
                } else {
                    self.errorMessage = "No output received"
                    self.entries = []
                }
            }
        }
    }
    
    private func parseDirectoryListing(_ output: String) {
        var parsed: [RemoteEntry] = []
        let lines = output.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("total") { continue }
            let comps = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if comps.count < 9 { continue }
            let perm = String(comps[0])
            let name = comps.dropFirst(8).joined(separator: " ")
            let isDir = perm.first == "d"
            parsed.append(RemoteEntry(name: name, isDirectory: isDir))
        }

        parsed.sort { (a, b) in
            if a.isDirectory == b.isDirectory { return a.name.lowercased() < b.name.lowercased() }
            return a.isDirectory && !b.isDirectory
        }

        entries = parsed
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
