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

struct RemoteEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}

struct ContentView: View {
    // Local source/target
    @State private var localSource: String = ""
    @State private var localTarget: String = ""

    // Remote source/target components
    @State private var sourceRemoteUser: String = ""
    @State private var sourceRemoteHost: String = ""
    @State private var sourceRemotePath: String = ""
    @State private var targetRemoteUser: String = ""
    @State private var targetRemoteHost: String = ""
    @State private var targetRemotePath: String = ""

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

    // Output log
    @State private var outputLog: String = ""

    var sourceProvided: Bool {
        if sourceIsRemote {
            return !sourceRemoteUser.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !sourceRemoteHost.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !localSource.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var targetProvided: Bool {
        if targetIsRemote {
            return !targetRemoteUser.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !targetRemoteHost.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !localTarget.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var computedRemoteSource: String {
        if sourceRemotePath.isEmpty {
            return "\(sourceRemoteUser)@\(sourceRemoteHost):"
        } else {
            return "\(sourceRemoteUser)@\(sourceRemoteHost):\(sourceRemotePath)"
        }
    }

    var computedRemoteTarget: String {
        if targetRemotePath.isEmpty {
            return "\(targetRemoteUser)@\(targetRemoteHost):"
        } else {
            return "\(targetRemoteUser)@\(targetRemoteHost):\(targetRemotePath)"
        }
    }

    var commandPreview: String {
        var parts: [String] = ["rsync"]
        if optArchive { parts.append("-a") }
        if optVerbose { parts.append("-v") }
        if optHumanReadable { parts.append("-h") }
        if optProgress { parts.append("--progress") }
        if optDelete { parts.append("--delete") }
        if optDryRun { parts.append("--dry-run") }
        if sourceIsRemote || targetIsRemote {
            var sshOptions = [
                "-oStrictHostKeyChecking=no",
                "-oUserKnownHostsFile=/dev/null",
                "-oGlobalKnownHostsFile=/dev/null"
            ]
            if sourceIsRemote && sourceUseSSHKey && !sourceSSHKeyPath.isEmpty {
                sshOptions.append("-i \"\(sourceSSHKeyPath)\"")
            } else if targetIsRemote && targetUseSSHKey && !targetSSHKeyPath.isEmpty {
                sshOptions.append("-i \"\(targetSSHKeyPath)\"")
            }
            if sourceUsePassword || targetUsePassword {
                sshOptions.append("-oPasswordAuthentication=yes")
                sshOptions.append("-oPubkeyAuthentication=no")
            } else {
                sshOptions.append("-oPreferredAuthentications=publickey")
            }
            let sshCmd = "ssh " + sshOptions.joined(separator: " ")
            parts.append("-e \"\(sshCmd)\"")
        }
        let src = sourceIsRemote ? computedRemoteSource : localSource
        let dst = targetIsRemote ? computedRemoteTarget : localTarget
        parts.append("\"\(src)\"")
        parts.append("\"\(dst)\"")
        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(label: Text("Source")) {
                HStack {
                    Toggle(isOn: $sourceIsRemote) {
                        Text("Remote")
                    }.toggleStyle(.switch)
                    Spacer()
                }
                if sourceIsRemote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Username", text: $sourceRemoteUser)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            TextField("Host/IP", text: $sourceRemoteHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            TextField("Remote path", text: $sourceRemotePath)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                showingRemoteBrowserForSource = true
                            } label: {
                                Label("Browse", systemImage: "network")
                            }
                            .help("Browse remote filesystem")
                        }
                        if sourceUsePassword {
                            SecureField("Remote password", text: $sourcePassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Toggle("Use password", isOn: $sourceUsePassword)
                                .toggleStyle(.checkbox)
                            Toggle("Use SSH key", isOn: $sourceUseSSHKey)
                                .toggleStyle(.checkbox)
                        }
                        if sourceUseSSHKey {
                            HStack {
                                TextField("SSH key path (e.g., ~/.ssh/rsync_app_key)", text: $sourceSSHKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    pickSSHKeyForSource()
                                } label: {
                                    Label("Browse", systemImage: "key")
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        TextField("local path to source", text: $localSource)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            pickLocalSource()
                        } label: {
                            Label("Browse", systemImage: "folder")
                        }
                    }
                }
            }

            GroupBox(label: Text("Target")) {
                HStack {
                    Toggle(isOn: $targetIsRemote) {
                        Text("Remote")
                    }.toggleStyle(.switch)
                    Spacer()
                }
                if targetIsRemote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Username", text: $targetRemoteUser)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            TextField("Host/IP", text: $targetRemoteHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            TextField("Remote path", text: $targetRemotePath)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                showingRemoteBrowserForTarget = true
                            } label: {
                                Label("Browse", systemImage: "network")
                            }
                            .help("Browse remote filesystem")
                        }
                        if targetUsePassword {
                            SecureField("Remote password", text: $targetPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Toggle("Use password", isOn: $targetUsePassword)
                                .toggleStyle(.checkbox)
                            Toggle("Use SSH key", isOn: $targetUseSSHKey)
                                .toggleStyle(.checkbox)
                        }
                        if targetUseSSHKey {
                            HStack {
                                TextField("SSH key path (e.g., ~/.ssh/rsync_app_key)", text: $targetSSHKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    pickSSHKeyForTarget()
                                } label: {
                                    Label("Browse", systemImage: "key")
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        TextField("local path to target", text: $localTarget)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            pickLocalTarget()
                        } label: {
                            Label("Browse", systemImage: "folder")
                        }
                    }
                }
            }

            GroupBox(label: Text("Options")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Archive (-a)", isOn: $optArchive)
                    Toggle("Verbose (-v)", isOn: $optVerbose)
                    Toggle("Human readable (-h)", isOn: $optHumanReadable)
                    Toggle("Show progress (--progress)", isOn: $optProgress)
                    Toggle("Delete existing on target (--delete)", isOn: $optDelete)
                    Toggle("Dry run (--dry-run)", isOn: $optDryRun)
                    Toggle("Copy contents of folder (trailing slash)", isOn: $copyContents)
                        .help("When true, a trailing slash will be added to source to copy contents rather than the folder itself.")
                }
            }

            GroupBox(label: Text("Command Preview")) {
                ScrollView(.horizontal) {
                    Text(commandPreview)
                        .font(.system(.body, design: .monospaced))
                        .padding(6)
                        .textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    Button {
                        runRsync()
                    } label: {
                        Label(rsyncManager.isRunning ? "Running..." : "Run rsync", systemImage: "play.fill")
                    }
                    .disabled(rsyncManager.isRunning || !sourceProvided || !targetProvided)
                    Button {
                        stopRsync()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!rsyncManager.isRunning)
                    Spacer()
                }
                Text(rsyncManager.isRunning ? "Running" : "Ready")
                    .foregroundColor(rsyncManager.isRunning ? .accentColor : .secondary)
            }

            GroupBox(label: Text("Output")) {
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
            RemoteBrowserView(
                initialUser: sourceRemoteUser,
                initialHost: sourceRemoteHost,
                initialPath: sourceRemotePath,
                password: sourceUsePassword ? sourcePassword : nil,
                useSSHKey: sourceUseSSHKey,
                sshKeyPath: sourceSSHKeyPath
            ) { u, h, p in
                sourceRemoteUser = u
                sourceRemoteHost = h
                sourceRemotePath = p
            }
        }
        .sheet(isPresented: $showingRemoteBrowserForTarget) {
            RemoteBrowserView(
                initialUser: targetRemoteUser,
                initialHost: targetRemoteHost,
                initialPath: targetRemotePath,
                password: targetUsePassword ? targetPassword : nil,
                useSSHKey: targetUseSSHKey,
                sshKeyPath: targetSSHKeyPath
            ) { u, h, p in
                targetRemoteUser = u
                targetRemoteHost = h
                targetRemotePath = p
            }
        }
        .frame(minWidth: 800, minHeight: 700)
    }

    // Pickers and rsync functions

    private func pickSSHKeyForSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                sourceSSHKeyPath = url.path
            }
        }
    }

    private func pickLocalSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                localSource = url.path
            }
        }
    }

    private func pickSSHKeyForTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                targetSSHKeyPath = url.path
            }
        }
    }

    private func pickLocalTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                localTarget = url.path
            }
        }
    }

    private func runRsync() {
        guard !rsyncManager.isRunning else { return }
        var options = ""
        if optArchive { options += "-a " }
        if optVerbose { options += "-v " }
        if optHumanReadable { options += "-h " }
        if optProgress { options += "--progress " }
        if optDelete { options += "--delete " }
        if optDryRun { options += "--dry-run " }
        
        let optionsArray = options.trimmingCharacters(in: .whitespaces).split(separator: " ").map { String($0) }

        var source = sourceIsRemote ? computedRemoteSource : localSource
        var destination = targetIsRemote ? computedRemoteTarget : localTarget
        if copyContents && !source.isEmpty && !source.hasSuffix("/") {
            source += "/"
        }

        let config = RsyncManager.RsyncConfig(
            source: source,
            destination: destination,
            options: optionsArray,
            usePassword: sourceUsePassword || targetUsePassword,
            password: sourceUsePassword ? sourcePassword : (targetUsePassword ? targetPassword : nil),
            sshKeyPath: sourceUseSSHKey ? sourceSSHKeyPath : (targetUseSSHKey ? targetSSHKeyPath : nil),
            sshKeyPassphrase: nil
        )
        rsyncManager.executeRsync(config: config) { output in
            DispatchQueue.main.async {
                outputLog += output
            }
        }
    }

    private func stopRsync() {
        rsyncManager.stopRsync()
    }
}

struct RemoteBrowserView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var user: String
    @State private var host: String
    @State private var path: String
    let password: String?
    let useSSHKey: Bool
    let sshKeyPath: String?
    let onSelect: (String, String, String) -> Void

    @State private var entries: [RemoteEntry] = []
    @State private var loading: Bool = false
    @State private var errorMessage: String = ""

    init(
        initialUser: String = "",
        initialHost: String = "",
        initialPath: String = "",
        password: String? = nil,
        useSSHKey: Bool = false,
        sshKeyPath: String? = nil,
        onSelect: @escaping (String, String, String) -> Void
    ) {
        _user = State(initialValue: initialUser)
        _host = State(initialValue: initialHost)
        _path = State(initialValue: initialPath.isEmpty ? "/" : initialPath)
        self.password = password
        self.useSSHKey = useSSHKey
        self.sshKeyPath = sshKeyPath
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Username", text: $user)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField("Host/IP", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                TextField("Path", text: $path)
                    .textFieldStyle(.roundedBorder)
                Button("Connect") {
                    listDirectory()
                }
            }
            .padding()
            if loading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Connecting...")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding([.leading, .trailing])
            }
            if !entries.isEmpty {
                List(entries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                            .foregroundColor(entry.isDirectory ? .blue : .primary)
                        Text(entry.name)
                        Spacer()
                        if entry.isDirectory {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if entry.isDirectory {
                            navigateToDirectory(entry.name)
                        } else {
                            selectFile(entry.name)
                        }
                    }
                }
                .listStyle(.plain)
            } else if !loading && errorMessage.isEmpty {
                Text("No files found")
                    .foregroundColor(.secondary)
                    .padding()
            }
            HStack {
                Button("Up") {
                    navigateUp()
                }
                .disabled(path == "/" || loading)
                Spacer()
                Button("Select Current") {
                    onSelect(user, host, path)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(user.isEmpty || host.isEmpty || loading)
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            if !user.isEmpty && !host.isEmpty && entries.isEmpty && !loading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    listDirectory()
                }
            }
        }
    }

    private func navigateToDirectory(_ dirName: String) {
        if dirName == ".." {
            navigateUp()
        } else if dirName != "." {
            if path == "/" {
                path = "/\(dirName)"
            } else {
                path = path.hasSuffix("/") ? "\(path)\(dirName)" : "\(path)/\(dirName)"
            }
            listDirectory()
        }
    }

    private func navigateUp() {
        if path == "/" { return }
        let components = path.split(separator: "/")
        if components.count > 1 {
            path = "/" + components.dropLast().joined(separator: "/")
        } else {
            path = "/"
        }
        listDirectory()
    }

    private func selectFile(_ fileName: String) {
        let finalPath = path == "/" ? "/\(fileName)" : "\(path)/\(fileName)"
        onSelect(user, host, finalPath)
        presentationMode.wrappedValue.dismiss()
    }

    private func listDirectory() {
        guard !user.isEmpty && !host.isEmpty else {
            errorMessage = "Please enter username and host"
            return
        }
        errorMessage = ""
        loading = true
        let userHost = "\(user)@\(host)"
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        var sshCommand = "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null"
        if useSSHKey, let keyPath = sshKeyPath, !keyPath.isEmpty {
            sshCommand += " -i \"\(keyPath)\" -oPubkeyAuthentication=yes -oPasswordAuthentication=no"
        }
        if let pw = password, !pw.isEmpty {
            let escapedPassword = pw.replacingOccurrences(of: "'", with: "'\\''")
            let expectCommand = """
            expect -c "
            spawn \(sshCommand) \(userHost) ls -la '\(escapedPath)'
            expect {
            -re \".*assword.*:\" { send \"\(escapedPassword)\\r\"; exp_continue }
            -re \".*yes/no.*\" { send \"yes\\r\"; exp_continue }
            eof { exit }
            timeout { exit 1 }
            }
            "
            """
            executeAppleScriptCommand(expectCommand)
        } else {
            let command = "\(sshCommand) \(userHost) ls -la '\(escapedPath)'"
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
                    let errorMessage = (error["NSAppleScriptErrorMessage"] as? String) ?? "Connection failed"
                    self.errorMessage = errorMessage
                    self.entries = []
                } else if let output = result?.stringValue {
                    if !output.isEmpty {
                        self.parseDirectoryListing(output)
                    } else {
                        self.errorMessage = "Empty response from remote host"
                        self.entries = []
                    }
                } else {
                    self.errorMessage = "No output received from remote host"
                    self.entries = []
                }
            }
        }
    }

    private func parseDirectoryListing(_ output: String) {
        var parsed: [RemoteEntry] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total") { continue }
            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if components.count >= 9 {
                let permissions = String(components[0])
                let isDirectory = permissions.first == "d"
                let filename = components.dropFirst(8).joined(separator: " ")
                if filename != "." && filename != ".." {
                    parsed.append(RemoteEntry(name: filename, isDirectory: isDirectory))
                }
            }
        }
        if path != "/" {
            parsed.insert(RemoteEntry(name: "..", isDirectory: true), at: 0)
        }
        parsed.sort { a, b in
            if a.name == ".." { return true }
            if b.name == ".." { return false }
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.lowercased() < b.name.lowercased()
        }
        DispatchQueue.main.async { self.entries = parsed }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

