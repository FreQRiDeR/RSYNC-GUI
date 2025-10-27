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

// MARK: - Sync bookmark model
struct SyncBookmark: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String

    // Source
    var sourceIsRemote: Bool
    var sourcePath: String
    var sourceUser: String
    var sourceHost: String
    var sourceUseSSHKey: Bool
    var sourceSSHKeyPath: String

    // Target
    var targetIsRemote: Bool
    var targetPath: String
    var targetUser: String
    var targetHost: String
    var targetUseSSHKey: Bool
    var targetSSHKeyPath: String

    // Options snapshot
    var optArchive: Bool
    var optVerbose: Bool
    var optHumanReadable: Bool
    var optProgress: Bool
    var optDelete: Bool
    var optDryRun: Bool
    var copyContents: Bool

    // Frozen command for quick run
    var command: String

    var lastUsed: Date

    init(
        id: UUID = UUID(),
        name: String,
        sourceIsRemote: Bool,
        sourcePath: String,
        sourceUser: String = "",
        sourceHost: String = "",
        sourceUseSSHKey: Bool = false,
        sourceSSHKeyPath: String = "",
        targetIsRemote: Bool,
        targetPath: String,
        targetUser: String = "",
        targetHost: String = "",
        targetUseSSHKey: Bool = false,
        targetSSHKeyPath: String = "",
        optArchive: Bool,
        optVerbose: Bool,
        optHumanReadable: Bool,
        optProgress: Bool,
        optDelete: Bool,
        optDryRun: Bool,
        copyContents: Bool,
        command: String,
        lastUsed: Date = Date()
    ) {
        self.id = id
        self.name = name

        self.sourceIsRemote = sourceIsRemote
        self.sourcePath = sourcePath
        self.sourceUser = sourceUser
        self.sourceHost = sourceHost
        self.sourceUseSSHKey = sourceUseSSHKey
        self.sourceSSHKeyPath = sourceSSHKeyPath

        self.targetIsRemote = targetIsRemote
        self.targetPath = targetPath
        self.targetUser = targetUser
        self.targetHost = targetHost
        self.targetUseSSHKey = targetUseSSHKey
        self.targetSSHKeyPath = targetSSHKeyPath

        self.optArchive = optArchive
        self.optVerbose = optVerbose
        self.optHumanReadable = optHumanReadable
        self.optProgress = optProgress
        self.optDelete = optDelete
        self.optDryRun = optDryRun
        self.copyContents = copyContents

        self.command = command
        self.lastUsed = lastUsed
    }

    static func == (lhs: SyncBookmark, rhs: SyncBookmark) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Bookmark manager (jobs)
class BookmarkManager: ObservableObject {
    @Published var bookmarks: [SyncBookmark] = []

    private let savePath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("RSYNC-GUI")
            .appendingPathComponent("bookmarks_v2.json")
    }()

    init() {
        loadBookmarks()
    }

    func addOrReplace(_ bookmark: SyncBookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        saveBookmarks()
    }

    func addNew(_ bookmark: SyncBookmark) {
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func deleteBookmark(_ bookmark: SyncBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func updateLastUsed(_ bookmark: SyncBookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i].lastUsed = Date()
            saveBookmarks()
        }
    }

    func getRecentBookmarks(limit: Int = 8) -> [SyncBookmark] {
        Array(bookmarks.sorted { $0.lastUsed > $1.lastUsed }.prefix(limit))
    }

    private func saveBookmarks() {
        do {
            let dir = savePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: savePath)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }

    private func loadBookmarks() {
        do {
            let data = try Data(contentsOf: savePath)
            bookmarks = try JSONDecoder().decode([SyncBookmark].self, from: data)
        } catch {
            print("Failed to load bookmarks: \(error)")
            bookmarks = []
        }
    }
}

struct ContentView: View {
    // Source (local or remote)
    @State private var localSource: String = ""
    @State private var sourceRemoteUser: String = ""
    @State private var sourceRemoteHost: String = ""
    @State private var sourceRemotePath: String = ""
    @State private var sourceUsePassword = false
    @State private var sourcePassword: String = ""
    @State private var sourceUseSSHKey = false
    @State private var sourceSSHKeyPath: String = ""
    @State private var sourceSSHKeyPassphrase: String = ""
    @State private var sourceIsRemote = false

    // Target (local or remote)
    @State private var localTarget: String = ""
    @State private var targetRemoteUser: String = ""
    @State private var targetRemoteHost: String = ""
    @State private var targetRemotePath: String = ""
    @State private var targetUsePassword = false
    @State private var targetPassword: String = ""
    @State private var targetUseSSHKey = false
    @State private var targetSSHKeyPath: String = ""
    @State private var targetSSHKeyPassphrase: String = ""
    @State private var targetIsRemote = false

    // Options
    @State private var optArchive = true
    @State private var optVerbose = false
    @State private var optHumanReadable = true
    @State private var optProgress = true
    @State private var optDelete = false
    @State private var optDryRun = false
    @State private var copyContents = false

    @StateObject private var rsyncManager = RsyncManager()
    @StateObject private var bookmarkManager = BookmarkManager()

    // Sheets
    @State private var showingRemoteBrowserForSource = false
    @State private var showingRemoteBrowserForTarget = false
    @State private var showingBookmarkSheet = false
    @State private var editingBookmark: SyncBookmark?

    @State private var outputLog: String = ""
    @State private var newBookmarkName: String = ""

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
        sourceRemotePath.isEmpty
        ? "\(sourceRemoteUser)@\(sourceRemoteHost):"
        : "\(sourceRemoteUser)@\(sourceRemoteHost):\(sourceRemotePath)"
    }

    var computedRemoteTarget: String {
        targetRemotePath.isEmpty
        ? "\(targetRemoteUser)@\(targetRemoteHost):"
        : "\(targetRemoteUser)@\(targetRemoteHost):\(targetRemotePath)"
    }

    var commandPreview: String {
        var parts: [String] = []
        parts.append("rsync")

        if optArchive { parts.append("-a") }
        if optVerbose { parts.append("-v") }
        if optHumanReadable { parts.append("-h") }
        if optProgress { parts.append("--progress") }
        if optDelete { parts.append("--delete") }
        if optDryRun { parts.append("--dry-run") }

        if sourceIsRemote || targetIsRemote {
            var sshOptions: [String] = []

            if let key = (sourceIsRemote && sourceUseSSHKey && !sourceSSHKeyPath.isEmpty) ? sourceSSHKeyPath : (targetIsRemote && targetUseSSHKey && !targetSSHKeyPath.isEmpty) ? targetSSHKeyPath : nil {
                sshOptions.append("-i")
                sshOptions.append(key)
            }

            if !sshOptions.isEmpty {
                let sshParts = sshOptions.map { token in
                    token.contains(" ") ? "\"\(token)\"" : token
                }
                let sshCmd = "ssh " + sshParts.joined(separator: " ")
                parts.append("-e '\(sshCmd)'")
            }
        }

        func quoted(_ s: String) -> String { "\"\(s)\"" }
        var src = sourceIsRemote ? computedRemoteSource : localSource
        var dst = targetIsRemote ? computedRemoteTarget : localTarget

        func normalizeRemote(_ s: String) -> String {
            guard s.contains("@"), !s.contains(":") else { return s }
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "apple.terminal.on.rectangle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("RSYNC-GUI")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("GUI for rsync in $PATH")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            // Global bookmarks bar
            HStack(spacing: 8) {
                Menu {
                    // Recent jobs first
                    ForEach(bookmarkManager.getRecentBookmarks()) { b in
                        Button {
                            loadSyncBookmark(b)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(.headline)
                                Text(shortSummary(for: b))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if !bookmarkManager.bookmarks.isEmpty {
                        Divider()
                        Button("Manage Bookmarks…") { showingBookmarkSheet = true }
                    }
                } label: {
                    Label("Bookmarks", systemImage: "bookmark.fill")
                }
                .fixedSize()
                
                Spacer()

                Button {
                    saveCurrentJob()
                } label: {
                    Label(newBookmarkName.isEmpty ? "Save Job" : "Save “\(newBookmarkName)”", systemImage: "bookmark")
                }
                .help("Snapshot source, target, options, and command as a bookmark")

            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Main content
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Source") {
                    HStack {
                        Toggle(isOn: $sourceIsRemote) { Text("Remote") }
                            .toggleStyle(.switch)
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
                                Button(action: { showingRemoteBrowserForSource = true }) {
                                    Label("Browse", systemImage: "network")
                                }
                                .help("Browse remote filesystem")
                            }

                            HStack {
                                Toggle("Use password", isOn: $sourceUsePassword)
                                    .toggleStyle(.checkbox)
                                Toggle("Use SSH key", isOn: $sourceUseSSHKey)
                                    .toggleStyle(.checkbox)
                            }

                            if sourceUseSSHKey {
                                HStack {
                                    TextField("SSH key path (e.g., ~/.ssh/id_rsa)", text: $sourceSSHKeyPath)
                                        .textFieldStyle(.roundedBorder)
                                    Button(action: pickSSHKeyForSource) {
                                        Label("Browse", systemImage: "key")
                                    }
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
                        Toggle(isOn: $targetIsRemote) { Text("Remote") }
                            .toggleStyle(.switch)
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
                                Button(action: { showingRemoteBrowserForTarget = true }) {
                                    Label("Browse", systemImage: "network")
                                }
                                .help("Browse remote filesystem")
                            }

                            HStack {
                                Toggle("Use password", isOn: $targetUsePassword)
                                    .toggleStyle(.checkbox)
                                Toggle("Use SSH key", isOn: $targetUseSSHKey)
                                    .toggleStyle(.checkbox)
                            }

                            if targetUseSSHKey {
                                HStack {
                                    TextField("SSH key path (e.g., ~/.ssh/id_rsa)", text: $targetSSHKeyPath)
                                        .textFieldStyle(.roundedBorder)
                                    Button(action: pickSSHKeyForTarget) {
                                        Label("Browse", systemImage: "key")
                                    }
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
                    let columns = [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ]

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        Toggle("Archive (-a)", isOn: $optArchive)
                        Toggle("Verbose (-v)", isOn: $optVerbose)

                        Text("Preserve permissions, times, symbolic links, etc.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Human readable (-h)", isOn: $optHumanReadable)
                        Toggle("Show progress (--progress)", isOn: $optProgress)
                        Toggle("Delete existing on target (--delete)", isOn: $optDelete)
                        Toggle("Dry run (--dry-run)", isOn: $optDryRun)
                        Toggle("Copy contents of folder (trailing slash)", isOn: $copyContents)
                            .help("Add trailing slash to copy contents rather than the folder itself.")
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
                    TextEditor(text: $outputLog)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(minHeight: 120)
                }

                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
        .navigationTitle("RSYNC GUI")
        .sheet(isPresented: $showingRemoteBrowserForSource) {
            RemoteBrowserView(
                initialUser: sourceRemoteUser,
                initialHost: sourceRemoteHost,
                initialPath: sourceRemotePath,
                password: sourceUsePassword ? sourcePassword : nil,
                useSSHKey: sourceUseSSHKey,
                sshKeyPath: sourceSSHKeyPath,
                sshKeyPassphrase: sourceSSHKeyPassphrase
            ) { user, host, path in
                sourceRemoteUser = user
                sourceRemoteHost = host
                sourceRemotePath = path
            }
        }
        .sheet(isPresented: $showingRemoteBrowserForTarget) {
            RemoteBrowserView(
                initialUser: targetRemoteUser,
                initialHost: targetRemoteHost,
                initialPath: targetRemotePath,
                password: targetUsePassword ? targetPassword : nil,
                useSSHKey: targetUseSSHKey,
                sshKeyPath: targetSSHKeyPath,
                sshKeyPassphrase: targetSSHKeyPassphrase
            ) { user, host, path in
                targetRemoteUser = user
                targetRemoteHost = host
                targetRemotePath = path
            }
        }
        .sheet(isPresented: $showingBookmarkSheet) {
            BookmarkManagerView(bookmarkManager: bookmarkManager) { b in
                loadSyncBookmark(b)
            }
        }
        .sheet(item: $editingBookmark) { b in
            EditBookmarkView(bookmark: b) { edited in
                bookmarkManager.addOrReplace(edited)
                editingBookmark = nil
            }
        }
        .frame(minWidth: 668, minHeight: 850)
    }

    // MARK: - Bookmark helpers
    func shortSummary(for b: SyncBookmark) -> String {
        let s = b.sourceIsRemote ? "\(b.sourceUser)@\(b.sourceHost):\(b.sourcePath)" : b.sourcePath
        let t = b.targetIsRemote ? "\(b.targetUser)@\(b.targetHost):\(b.targetPath)" : b.targetPath
        return "\(s) → \(t)"
    }

    func makeCurrentJobBookmark(defaultName: String?) -> SyncBookmark? {
        guard sourceProvided, targetProvided else { return nil }
        let name = (defaultName?.isEmpty == false) ? defaultName! : suggestedBookmarkName()

        let bookmark = SyncBookmark(
            name: name,
            sourceIsRemote: sourceIsRemote,
            sourcePath: sourceIsRemote ? sourceRemotePath : localSource,
            sourceUser: sourceRemoteUser,
            sourceHost: sourceRemoteHost,
            sourceUseSSHKey: sourceUseSSHKey,
            sourceSSHKeyPath: sourceSSHKeyPath,
            targetIsRemote: targetIsRemote,
            targetPath: targetIsRemote ? targetRemotePath : localTarget,
            targetUser: targetRemoteUser,
            targetHost: targetRemoteHost,
            targetUseSSHKey: targetUseSSHKey,
            targetSSHKeyPath: targetSSHKeyPath,
            optArchive: optArchive,
            optVerbose: optVerbose,
            optHumanReadable: optHumanReadable,
            optProgress: optProgress,
            optDelete: optDelete,
            optDryRun: optDryRun,
            copyContents: copyContents,
            command: commandPreview
        )
        return bookmark
    }

    func suggestedBookmarkName() -> String {
        let src = sourceIsRemote ? "\(sourceRemoteUser)@\(sourceRemoteHost)" : (localSource as String)
        let dst = targetIsRemote ? "\(targetRemoteUser)@\(targetRemoteHost)" : (localTarget as String)
        let sShort = src.isEmpty ? "source" : src.split(separator: "/").last.map(String.init) ?? src
        let dShort = dst.isEmpty ? "target" : dst.split(separator: "/").last.map(String.init) ?? dst
        return "\(sShort) → \(dShort)"
    }

    func saveCurrentJob() {
        guard let job = makeCurrentJobBookmark(defaultName: newBookmarkName) else { return }
        bookmarkManager.addNew(job)
        newBookmarkName = ""
    }

    func loadSyncBookmark(_ b: SyncBookmark) {
        // Source
        sourceIsRemote = b.sourceIsRemote
        if b.sourceIsRemote {
            sourceRemoteUser = b.sourceUser
            sourceRemoteHost = b.sourceHost
            sourceRemotePath = b.sourcePath
            sourceUseSSHKey = b.sourceUseSSHKey
            sourceSSHKeyPath = b.sourceSSHKeyPath
            if b.sourceUseSSHKey && !b.sourceSSHKeyPath.isEmpty {
                sourceUsePassword = false
            }
        } else {
            localSource = b.sourcePath
        }

        // Target
        targetIsRemote = b.targetIsRemote
        if b.targetIsRemote {
            targetRemoteUser = b.targetUser
            targetRemoteHost = b.targetHost
            targetRemotePath = b.targetPath
            targetUseSSHKey = b.targetUseSSHKey
            targetSSHKeyPath = b.targetSSHKeyPath
            if b.targetUseSSHKey && !b.targetSSHKeyPath.isEmpty {
                targetUsePassword = false
            }
        } else {
            localTarget = b.targetPath
        }

        // Options
        optArchive = b.optArchive
        optVerbose = b.optVerbose
        optHumanReadable = b.optHumanReadable
        optProgress = b.optProgress
        optDelete = b.optDelete
        optDryRun = b.optDryRun
        copyContents = b.copyContents

        bookmarkManager.updateLastUsed(b)
    }

    // MARK: - Pickers
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
        panel.message = "Select SSH private key file"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                sourceSSHKeyPath = url.path
                appendOutput("📌 Using SSH key: \(url.path)\n")
            }
        }
    }

    func pickSSHKeyForTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.message = "Select SSH private key file"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                targetSSHKeyPath = url.path
                appendOutput("📌 Using SSH key: \(url.path)\n")
            }
        }
    }

    // MARK: - Execute rsync
    func runRsync() {
        outputLog = ""

        var options: [String] = []
        if optArchive { options.append("-a") }
        if optVerbose { options.append("-v") }
        if optHumanReadable { options.append("-h") }
        if optProgress { options.append("--progress") }
        if optDelete { options.append("--delete") }
        if optDryRun { options.append("--dry-run") }

        var source = sourceIsRemote ? computedRemoteSource : localSource
        var destination = targetIsRemote ? computedRemoteTarget : localTarget

        if copyContents && !source.isEmpty && !source.hasSuffix("/") {
            source += "/"
        }

        if sourceIsRemote {
            source = normalizeRemotePath(source)
        }
        if targetIsRemote {
            destination = normalizeRemotePath(destination)
        }

        let usePassword: Bool
        let password: String?
        let keyPath: String?

        if sourceIsRemote {
            usePassword = sourceUsePassword
            password = sourceUsePassword && !sourcePassword.isEmpty ? sourcePassword : nil
            keyPath = sourceUseSSHKey && !sourceSSHKeyPath.isEmpty ? sourceSSHKeyPath : nil
        } else if targetIsRemote {
            usePassword = targetUsePassword
            password = targetUsePassword && !targetPassword.isEmpty ? targetPassword : nil
            keyPath = targetUseSSHKey && !targetSSHKeyPath.isEmpty ? targetSSHKeyPath : nil
        } else {
            usePassword = false
            password = nil
            keyPath = nil
        }

        let config = RsyncManager.RsyncConfig(
            source: source,
            destination: destination,
            options: options,
            usePassword: usePassword,
            password: password,
            sshKeyPath: keyPath,
            sshKeyPassphrase: (sourceIsRemote ? sourceSSHKeyPassphrase : targetSSHKeyPassphrase)
        )

        rsyncManager.executeRsync(config: config) { output in
            appendOutput(output)
        }
    }

    func stopRsync() {
        rsyncManager.stopRsync()
        appendOutput("\nUser terminated process\n")
    }

    func appendOutput(_ s: String) {
        DispatchQueue.main.async {
            self.outputLog += s
        }
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

// MARK: - Bookmark manager view (jobs)
struct BookmarkManagerView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var bookmarkManager: BookmarkManager
    let onSelect: (SyncBookmark) -> Void

    @State private var editingBookmark: SyncBookmark?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Manage Bookmarks")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()

            if bookmarkManager.bookmarks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No bookmarks yet")
                        .foregroundColor(.secondary)
                    Text("Save a job using the 'Save current job' button")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(bookmarkManager.bookmarks.sorted { $0.lastUsed > $1.lastUsed }) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.name).font(.headline)
                                Text(jobSummary(b))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: { editingBookmark = b }) {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                onSelect(b)
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)

                            Button(action: { bookmarkManager.deleteBookmark(b) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .sheet(item: $editingBookmark) { b in
            EditBookmarkView(bookmark: b) { edited in
                bookmarkManager.addOrReplace(edited)
                editingBookmark = nil
            }
        }
    }

    func jobSummary(_ b: SyncBookmark) -> String {
        let s = b.sourceIsRemote ? "\(b.sourceUser)@\(b.sourceHost):\(b.sourcePath)" : b.sourcePath
        let t = b.targetIsRemote ? "\(b.targetUser)@\(b.targetHost):\(b.targetPath)" : b.targetPath
        return "\(s) → \(t)"
    }
}

// MARK: - Edit bookmark view
struct EditBookmarkView: View {
    @Environment(\.dismiss) private var dismiss
    let bookmark: SyncBookmark
    let onSave: (SyncBookmark) -> Void

    @State private var name: String
    @State private var sourceIsRemote: Bool
    @State private var sourcePath: String
    @State private var sourceUser: String
    @State private var sourceHost: String
    @State private var sourceUseSSHKey: Bool
    @State private var sourceSSHKeyPath: String

    @State private var targetIsRemote: Bool
    @State private var targetPath: String
    @State private var targetUser: String
    @State private var targetHost: String
    @State private var targetUseSSHKey: Bool
    @State private var targetSSHKeyPath: String

    @State private var optArchive: Bool
    @State private var optVerbose: Bool
    @State private var optHumanReadable: Bool
    @State private var optProgress: Bool
    @State private var optDelete: Bool
    @State private var optDryRun: Bool
    @State private var copyContents: Bool

    init(bookmark: SyncBookmark, onSave: @escaping (SyncBookmark) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave

        _name = State(initialValue: bookmark.name)

        _sourceIsRemote = State(initialValue: bookmark.sourceIsRemote)
        _sourcePath = State(initialValue: bookmark.sourcePath)
        _sourceUser = State(initialValue: bookmark.sourceUser)
        _sourceHost = State(initialValue: bookmark.sourceHost)
        _sourceUseSSHKey = State(initialValue: bookmark.sourceUseSSHKey)
        _sourceSSHKeyPath = State(initialValue: bookmark.sourceSSHKeyPath)

        _targetIsRemote = State(initialValue: bookmark.targetIsRemote)
        _targetPath = State(initialValue: bookmark.targetPath)
        _targetUser = State(initialValue: bookmark.targetUser)
        _targetHost = State(initialValue: bookmark.targetHost)
        _targetUseSSHKey = State(initialValue: bookmark.targetUseSSHKey)
        _targetSSHKeyPath = State(initialValue: bookmark.targetSSHKeyPath)

        _optArchive = State(initialValue: bookmark.optArchive)
        _optVerbose = State(initialValue: bookmark.optVerbose)
        _optHumanReadable = State(initialValue: bookmark.optHumanReadable)
        _optProgress = State(initialValue: bookmark.optProgress)
        _optDelete = State(initialValue: bookmark.optDelete)
        _optDryRun = State(initialValue: bookmark.optDryRun)
        _copyContents = State(initialValue: bookmark.copyContents)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Bookmark")
                .font(.headline)

            Form {
                Section(header: Text("Name")) {
                    TextField("Bookmark name", text: $name)
                }

                Section(header: Text("Source")) {
                    Toggle("Remote", isOn: $sourceIsRemote)
                    if sourceIsRemote {
                        HStack {
                            TextField("User", text: $sourceUser)
                            TextField("Host", text: $sourceHost)
                        }
                        TextField("Remote path", text: $sourcePath)
                        Toggle("Use SSH Key", isOn: $sourceUseSSHKey)
                        if sourceUseSSHKey {
                            TextField("SSH Key Path", text: $sourceSSHKeyPath)
                        }
                    } else {
                        TextField("Local path", text: $sourcePath)
                    }
                }

                Section(header: Text("Target")) {
                    Toggle("Remote", isOn: $targetIsRemote)
                    if targetIsRemote {
                        HStack {
                            TextField("User", text: $targetUser)
                            TextField("Host", text: $targetHost)
                        }
                        TextField("Remote path", text: $targetPath)
                        Toggle("Use SSH Key", isOn: $targetUseSSHKey)
                        if targetUseSSHKey {
                            TextField("SSH Key Path", text: $targetSSHKeyPath)
                        }
                    } else {
                        TextField("Local path", text: $targetPath)
                    }
                }

                Section(header: Text("Options")) {
                    Toggle("Archive (-a)", isOn: $optArchive)
                    Toggle("Verbose (-v)", isOn: $optVerbose)
                    Toggle("Human readable (-h)", isOn: $optHumanReadable)
                    Toggle("Show progress (--progress)", isOn: $optProgress)
                    Toggle("Delete existing on target (--delete)", isOn: $optDelete)
                    Toggle("Dry run (--dry-run)", isOn: $optDryRun)
                    Toggle("Copy contents (trailing slash)", isOn: $copyContents)
                }
            }
            .padding(.top, 4)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    let edited = SyncBookmark(
                        id: bookmark.id,
                        name: name,
                        sourceIsRemote: sourceIsRemote,
                        sourcePath: sourcePath,
                        sourceUser: sourceUser,
                        sourceHost: sourceHost,
                        sourceUseSSHKey: sourceUseSSHKey,
                        sourceSSHKeyPath: sourceSSHKeyPath,
                        targetIsRemote: targetIsRemote,
                        targetPath: targetPath,
                        targetUser: targetUser,
                        targetHost: targetHost,
                        targetUseSSHKey: targetUseSSHKey,
                        targetSSHKeyPath: targetSSHKeyPath,
                        optArchive: optArchive,
                        optVerbose: optVerbose,
                        optHumanReadable: optHumanReadable,
                        optProgress: optProgress,
                        optDelete: optDelete,
                        optDryRun: optDryRun,
                        copyContents: copyContents,
                        command: buildCommandFromFields()
                    )
                    onSave(edited)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
    }

    private func buildCommandFromFields() -> String {
        func normalizeRemote(_ s: String) -> String {
            guard s.contains("@"), !s.contains(":") else { return s }
            if let slash = s.firstIndex(of: "/") {
                let before = String(s[..<slash])
                let after = String(s[slash...])
                return before + ":" + after
            } else {
                return s + ":"
            }
        }

        var parts: [String] = ["rsync"]
        if optArchive { parts.append("-a") }
        if optVerbose { parts.append("-v") }
        if optHumanReadable { parts.append("-h") }
        if optProgress { parts.append("--progress") }
        if optDelete { parts.append("--delete") }
        if optDryRun { parts.append("--dry-run") }

        if sourceIsRemote || targetIsRemote {
            var sshOptions: [String] = []
            if sourceIsRemote, sourceUseSSHKey, !sourceSSHKeyPath.isEmpty {
                sshOptions.append("-i")
                sshOptions.append(sourceSSHKeyPath)
            } else if targetIsRemote, targetUseSSHKey, !targetSSHKeyPath.isEmpty {
                sshOptions.append("-i")
                sshOptions.append(targetSSHKeyPath)
            }
            if !sshOptions.isEmpty {
                let sshParts = sshOptions.map { $0.contains(" ") ? "\"\($0)\"" : $0 }
                parts.append("-e 'ssh " + sshParts.joined(separator: " ") + "'")
            }
        }

        func quoted(_ s: String) -> String { "\"\(s)\"" }

        var src = sourceIsRemote ? "\(sourceUser)@\(sourceHost):\(sourcePath)" : sourcePath
        var dst = targetIsRemote ? "\(targetUser)@\(targetHost):\(targetPath)" : targetPath

        if sourceIsRemote { src = normalizeRemote(src) }
        if targetIsRemote { dst = normalizeRemote(dst) }

        if copyContents, !src.isEmpty, !src.hasSuffix("/") { src += "/" }

        parts.append(quoted(src))
        parts.append(quoted(dst))
        return parts.joined(separator: " ")
    }
}

// MARK: - Remote browser view (unchanged core)
struct RemoteEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}

struct RemoteBrowserView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var user: String
    @State private var host: String
    @State private var path: String
    let password: String?
    let useSSHKey: Bool
    let sshKeyPath: String?
    let sshKeyPassphrase: String?
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var errorMessage: String = ""
    let onSelect: (String, String, String) -> Void

    init(initialUser: String = "", initialHost: String = "", initialPath: String = "", password: String? = nil, useSSHKey: Bool = false, sshKeyPath: String? = nil, sshKeyPassphrase: String? = nil, onSelect: @escaping (String, String, String) -> Void) {
        _user = State(initialValue: initialUser)
        _host = State(initialValue: initialHost)
        _path = State(initialValue: initialPath.isEmpty ? "/" : initialPath)
        self.password = password
        self.useSSHKey = useSSHKey
        self.sshKeyPath = sshKeyPath
        self.sshKeyPassphrase = sshKeyPassphrase
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
                Button("Connect") { listDirectory() }
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
                Button("Up") { navigateUp() }
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
        .frame(minWidth: 400, minHeight: 400)
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

    func listDirectory() {
        guard !user.isEmpty && !host.isEmpty else {
            errorMessage = "Please enter username and host"
            return
        }

        errorMessage = ""
        loading = true

        let userHost = "\(user)@\(host)"
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\"'\"'")

        var sshCommand = "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null"

        if useSSHKey, let keyPath = sshKeyPath, !keyPath.isEmpty {
            if keyPath.contains(" ") {
                let escaped = keyPath.replacingOccurrences(of: "\"", with: "\\\"")
                sshCommand += " -i \"\(escaped)\" -oPubkeyAuthentication=yes -oPasswordAuthentication=no"
            } else {
                sshCommand += " -i \(keyPath) -oPubkeyAuthentication=yes -oPasswordAuthentication=no"
            }
        }

        if let keyPass = sshKeyPassphrase, !keyPass.isEmpty, useSSHKey, let keyPath = sshKeyPath, !keyPath.isEmpty {
            let escapedPass = keyPass.replacingOccurrences(of: "'", with: "'\"'\"'")
            let escapedKey = keyPath.replacingOccurrences(of: "'", with: "'\"'\"'")

            let expectLoad = """
            eval "$(ssh-agent -s)"
            trap 'ssh-agent -k >/dev/null 2>&1 || true' EXIT

            expect << 'LOAD_KEY_EOF'
            spawn ssh-add '\(escapedKey)'
            expect {
                -re "Enter passphrase.*:" { send "\(escapedPass)\\r"; exp_continue }
                -re "Identity added.*" { exit 0 }
                eof { exit 0 }
                timeout { exit 1 }
            }
            LOAD_KEY_EOF
            """

            let full = "\(expectLoad)\n\(sshCommand) \(userHost) ls -la '\(escapedPath)'"
            executeAppleScriptCommand(full)
            return
        }

        if let pw = password, !pw.isEmpty {
            let escapedPassword = pw.replacingOccurrences(of: "'", with: "'\"'\"'")
            let expectCommand = """
            expect -c "
            spawn \(sshCommand) \(userHost) ls -la '\(escapedPath)'
            expect {
                -re \".*assword.*:\" { send \"\(escapedPassword)\\r\"; exp_continue }
                -re \".*yes/no.*\" { send \"yes\\r\"; exp_continue }
                eof { exit }
                timeout { exit 1 }
            }
            """
            executeAppleScriptCommand(expectCommand)
        } else {
            let command = "\(sshCommand) \(userHost) ls -la '\(escapedPath)'"
            executeAppleScriptCommand(command)
        }
    }

    private func executeAppleScriptCommand(_ command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
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
                    let msg = (error["NSAppleScriptErrorMessage"] as? String) ?? "Connection failed"
                    if msg.contains("Connection refused") {
                        self.errorMessage = "Connection refused. Check if SSH is enabled on the remote host."
                    } else if msg.contains("Host key verification failed") {
                        self.errorMessage = "Host key verification failed. The remote host's key may have changed."
                    } else if msg.contains("Permission denied") {
                        self.errorMessage = "Permission denied. Check username, password, or SSH key."
                    } else if msg.contains("Name or service not known") {
                        self.errorMessage = "Cannot resolve hostname. Check the host address."
                    } else {
                        self.errorMessage = msg
                    }
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

        let lines: [String]
        if output.contains("\r\n") {
            lines = output.components(separatedBy: "\r\n")
        } else if output.contains("\n") {
            lines = output.components(separatedBy: "\n")
        } else if output.contains("\r") {
            lines = output.components(separatedBy: "\r")
        } else {
            lines = [output]
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total") { continue }

            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if components.count >= 9 {
                let permissions = String(components[0])
                let isDirectory = permissions.first == "d" || permissions.first == "l"
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

