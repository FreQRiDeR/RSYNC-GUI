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

// MARK: - Bookmark Model
struct RemoteBookmark: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var user: String
    var host: String
    var path: String
    var useSSHKey: Bool
    var sshKeyPath: String
    var lastUsed: Date
    
    init(id: UUID = UUID(), name: String, user: String, host: String, path: String = "", useSSHKey: Bool = false, sshKeyPath: String = "", lastUsed: Date = Date()) {
        self.id = id
        self.name = name
        self.user = user
        self.host = host
        self.path = path
        self.useSSHKey = useSSHKey
        self.sshKeyPath = sshKeyPath
        self.lastUsed = lastUsed
    }
    
    static func == (lhs: RemoteBookmark, rhs: RemoteBookmark) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Bookmark Manager
class BookmarkManager: ObservableObject {
    @Published var bookmarks: [RemoteBookmark] = []
    
    private let savePath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("RSYNC-GUI")
            .appendingPathComponent("bookmarks.json")
    }()
    
    init() {
        loadBookmarks()
    }
    
    func addBookmark(_ bookmark: RemoteBookmark) {
        if let index = bookmarks.firstIndex(where: { $0.user == bookmark.user && $0.host == bookmark.host }) {
            bookmarks[index] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        saveBookmarks()
    }
    
    func deleteBookmark(_ bookmark: RemoteBookmark) {
        // Don't delete user's SSH keys - they own them
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }
    
    func updateLastUsed(_ bookmark: RemoteBookmark) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index].lastUsed = Date()
            saveBookmarks()
        }
    }
    
    func getRecentBookmarks(limit: Int = 5) -> [RemoteBookmark] {
        return bookmarks.sorted { $0.lastUsed > $1.lastUsed }.prefix(limit).map { $0 }
    }
    
    private func saveBookmarks() {
        do {
            let directory = savePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: savePath)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }
    
    private func loadBookmarks() {
        do {
            let data = try Data(contentsOf: savePath)
            bookmarks = try JSONDecoder().decode([RemoteBookmark].self, from: data)
        } catch {
            print("Failed to load bookmarks: \(error)")
            bookmarks = []
        }
    }
}

struct ContentView: View {
    @State private var localSource: String = ""
    @State private var localTarget: String = ""
    @State private var sourceRemoteUser: String = ""
    @State private var sourceRemoteHost: String = ""
    @State private var sourceRemotePath: String = ""
    @State private var targetRemoteUser: String = ""
    @State private var targetRemoteHost: String = ""
    @State private var targetRemotePath: String = ""
    @State private var showingRemoteBrowserForSource = false
    @State private var showingRemoteBrowserForTarget = false
    @State private var sourceUsePassword = false
    @State private var sourcePassword: String = ""
    @State private var targetUsePassword = false
    @State private var targetPassword: String = ""
    @State private var sourceUseSSHKey = false
    @State private var sourceSSHKeyPath: String = ""
    @State private var sourceSSHKeyPassphrase: String = ""
    @State private var targetUseSSHKey = false
    @State private var targetSSHKeyPath: String = ""
    @State private var targetSSHKeyPassphrase: String = ""
    @State private var sourceIsRemote = false
    @State private var targetIsRemote = false
    @State private var optArchive = true
    @State private var optVerbose = false
    @State private var optHumanReadable = true
    @State private var optProgress = true
    @State private var optDelete = false
    @State private var optDryRun = false
    @State private var copyContents = false
    @StateObject private var rsyncManager = RsyncManager()
    @StateObject private var bookmarkManager = BookmarkManager()
    @State private var showingBookmarkSheet = false
    @State private var bookmarkTarget: BookmarkTarget = .source
    @State private var newBookmarkName: String = ""
    
    enum BookmarkTarget {
        case source
        case target
    }
    
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
        var parts: [String] = []
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
            var sshOptions: [String] = []
            
            // Only add SSH key if specified
            if let key = (sourceIsRemote && sourceUseSSHKey && !sourceSSHKeyPath.isEmpty) ? sourceSSHKeyPath : (targetIsRemote && targetUseSSHKey && !targetSSHKeyPath.isEmpty) ? targetSSHKeyPath : nil {
                sshOptions.append("-i")
                sshOptions.append(key)
            }
            
            if !sshOptions.isEmpty {
                let sshParts = sshOptions.map { token -> String in
                    if token.contains(" ") {
                        return "\"\(token)\""
                    }
                    return token
                }
                let sshCmd = "ssh " + sshParts.joined(separator: " ")
                parts.append("-e '\(sshCmd)'")
            }
        }

        func quoted(_ s: String) -> String { return "\"\(s)\"" }
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Menu {
                                ForEach(bookmarkManager.getRecentBookmarks()) { bookmark in
                                    Button(action: { loadBookmark(bookmark, target: .source) }) {
                                        VStack(alignment: .leading) {
                                            Text(bookmark.name)
                                                .font(.headline)
                                            Text("\(bookmark.user)@\(bookmark.host)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                if !bookmarkManager.bookmarks.isEmpty {
                                    Divider()
                                    Button("Manage Bookmarks...") {
                                        bookmarkTarget = .source
                                        showingBookmarkSheet = true
                                    }
                                }
                            } label: {
                                Label("Bookmarks", systemImage: "bookmark.fill")
                            }
                            .fixedSize()
                            
                            Button(action: {
                                bookmarkTarget = .source
                                newBookmarkName = "\(sourceRemoteUser)@\(sourceRemoteHost)"
                                saveCurrentAsBookmark()
                            }) {
                                Label("Save", systemImage: "bookmark")
                            }
                            .disabled(sourceRemoteUser.isEmpty || sourceRemoteHost.isEmpty)
                            .help("Save current connection as bookmark")
                        }
                        
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
                    Toggle(isOn: $targetIsRemote) {
                        Text("Remote")
                    }
                    .toggleStyle(.switch)
                    Spacer()
                }
                
                if targetIsRemote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Menu {
                                ForEach(bookmarkManager.getRecentBookmarks()) { bookmark in
                                    Button(action: { loadBookmark(bookmark, target: .target) }) {
                                        VStack(alignment: .leading) {
                                            Text(bookmark.name)
                                                .font(.headline)
                                            Text("\(bookmark.user)@\(bookmark.host)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                if !bookmarkManager.bookmarks.isEmpty {
                                    Divider()
                                    Button("Manage Bookmarks...") {
                                        bookmarkTarget = .target
                                        showingBookmarkSheet = true
                                    }
                                }
                            } label: {
                                Label("Bookmarks", systemImage: "bookmark.fill")
                            }
                            .fixedSize()
                            
                            Button(action: {
                                bookmarkTarget = .target
                                newBookmarkName = "\(targetRemoteUser)@\(targetRemoteHost)"
                                saveCurrentAsBookmark()
                            }) {
                                Label("Save", systemImage: "bookmark")
                            }
                            .disabled(targetRemoteUser.isEmpty || targetRemoteHost.isEmpty)
                            .help("Save current connection as bookmark")
                        }
                        
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
            BookmarkManagerView(bookmarkManager: bookmarkManager) { bookmark in
                loadBookmark(bookmark, target: bookmarkTarget)
            }
        }
        .frame(minWidth: 600, minHeight: 700)
    }
    
    func saveCurrentAsBookmark() {
        let user: String
        let host: String
        let path: String
        let useKey: Bool
        let keyPath: String
        
        if bookmarkTarget == .source {
            user = sourceRemoteUser
            host = sourceRemoteHost
            path = sourceRemotePath
            useKey = sourceUseSSHKey
            keyPath = sourceSSHKeyPath
        } else {
            user = targetRemoteUser
            host = targetRemoteHost
            path = targetRemotePath
            useKey = targetUseSSHKey
            keyPath = targetSSHKeyPath
        }
        
        guard !user.isEmpty && !host.isEmpty else { return }
        
        let bookmark = RemoteBookmark(
            name: newBookmarkName.isEmpty ? "\(user)@\(host)" : newBookmarkName,
            user: user,
            host: host,
            path: path,
            useSSHKey: useKey,
            sshKeyPath: keyPath
        )
        
        bookmarkManager.addBookmark(bookmark)
    }
    
    func loadBookmark(_ bookmark: RemoteBookmark, target: BookmarkTarget) {
            if target == .source {
                sourceRemoteUser = bookmark.user
                sourceRemoteHost = bookmark.host
                sourceRemotePath = bookmark.path
                sourceUseSSHKey = bookmark.useSSHKey
                sourceSSHKeyPath = bookmark.sshKeyPath
                if bookmark.useSSHKey && !bookmark.sshKeyPath.isEmpty {
                    sourceUsePassword = false
                }
            } else {
                targetRemoteUser = bookmark.user
                targetRemoteHost = bookmark.host
                targetRemotePath = bookmark.path
                targetUseSSHKey = bookmark.useSSHKey
                targetSSHKeyPath = bookmark.sshKeyPath
                if bookmark.useSSHKey && !bookmark.sshKeyPath.isEmpty {
                    targetUsePassword = false
                }
            }
            
            bookmarkManager.updateLastUsed(bookmark)
        }

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

    // MARK: - Bookmark Manager View
    struct BookmarkManagerView: View {
        @Environment(\.presentationMode) var presentationMode
        @ObservedObject var bookmarkManager: BookmarkManager
        let onSelect: (RemoteBookmark) -> Void
        
        @State private var editingBookmark: RemoteBookmark?
        @State private var showingEditSheet = false
        
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
                        Text("Save a connection using the 'Save' button")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(bookmarkManager.bookmarks.sorted { $0.lastUsed > $1.lastUsed }) { bookmark in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.name)
                                        .font(.headline)
                                    Text("\(bookmark.user)@\(bookmark.host)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if !bookmark.path.isEmpty {
                                        Text(bookmark.path)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if bookmark.useSSHKey {
                                        HStack(spacing: 4) {
                                            Image(systemName: "key.fill")
                                                .font(.caption)
                                            Text(bookmark.sshKeyPath)
                                                .font(.caption)
                                        }
                                        .foregroundColor(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    editingBookmark = bookmark
                                    showingEditSheet = true
                                }) {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    onSelect(bookmark)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    bookmarkManager.deleteBookmark(bookmark)
                                }) {
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
            .frame(minWidth: 500, minHeight: 400)
            .sheet(isPresented: $showingEditSheet) {
                if let bookmark = editingBookmark {
                    EditBookmarkView(bookmark: bookmark) { edited in
                        bookmarkManager.addBookmark(edited)
                        showingEditSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Edit Bookmark View
    struct EditBookmarkView: View {
        @Environment(\.presentationMode) var presentationMode
        let bookmark: RemoteBookmark
        let onSave: (RemoteBookmark) -> Void
        
        @State private var name: String
        @State private var user: String
        @State private var host: String
        @State private var path: String
        @State private var useSSHKey: Bool
        @State private var sshKeyPath: String
        
        init(bookmark: RemoteBookmark, onSave: @escaping (RemoteBookmark) -> Void) {
            self.bookmark = bookmark
            self.onSave = onSave
            _name = State(initialValue: bookmark.name)
            _user = State(initialValue: bookmark.user)
            _host = State(initialValue: bookmark.host)
            _path = State(initialValue: bookmark.path)
            _useSSHKey = State(initialValue: bookmark.useSSHKey)
            _sshKeyPath = State(initialValue: bookmark.sshKeyPath)
        }
        
        var body: some View {
            VStack(spacing: 16) {
                Text("Edit Bookmark")
                    .font(.headline)
                
                Form {
                    TextField("Bookmark Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Username", text: $user)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Host/IP", text: $host)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Path (optional)", text: $path)
                        .textFieldStyle(.roundedBorder)
                    
                    Toggle("Use SSH Key", isOn: $useSSHKey)
                        .toggleStyle(.checkbox)
                    
                    if useSSHKey {
                        TextField("SSH Key Path", text: $sshKeyPath)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                
                HStack {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    
                    Spacer()
                    
                    Button("Save") {
                        let edited = RemoteBookmark(
                            id: bookmark.id,
                            name: name,
                            user: user,
                            host: host,
                            path: path,
                            useSSHKey: useSSHKey,
                            sshKeyPath: sshKeyPath,
                            lastUsed: bookmark.lastUsed
                        )
                        onSave(edited)
                    }
                    .disabled(name.isEmpty || user.isEmpty || host.isEmpty)
                }
                .padding()
            }
            .frame(width: 400, height: 350)
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
            print("Executing SSH command: \(command)")
            
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
                        print("SSH Error: \(errorMessage)")
                        
                        if errorMessage.contains("Connection refused") {
                            self.errorMessage = "Connection refused. Check if SSH is enabled on the remote host."
                        } else if errorMessage.contains("Host key verification failed") {
                            self.errorMessage = "Host key verification failed. The remote host's key may have changed."
                        } else if errorMessage.contains("Permission denied") {
                            self.errorMessage = "Permission denied. Check username, password, or SSH key."
                        } else if errorMessage.contains("Name or service not known") {
                            self.errorMessage = "Cannot resolve hostname. Check the host address."
                        } else {
                            self.errorMessage = errorMessage
                        }
                        self.entries = []
                    } else if let output = result?.stringValue {
                        print("SSH output received: \(output.count) characters")
                        print("SSH output content: '\(output)'")
                        
                        if !output.isEmpty {
                            self.parseDirectoryListing(output)
                        } else {
                            self.errorMessage = "Empty response from remote host"
                            self.entries = []
                        }
                    } else {
                        print("No result from AppleScript")
                        self.errorMessage = "No output received from remote host"
                        self.entries = []
                    }
                }
            }
        }
        
        private func parseDirectoryListing(_ output: String) {
            var parsed: [RemoteEntry] = []
            
            var lines: [String] = []
            if output.contains("\r\n") {
                lines = output.components(separatedBy: "\r\n")
            } else if output.contains("\n") {
                lines = output.components(separatedBy: "\n")
            } else if output.contains("\r") {
                lines = output.components(separatedBy: "\r")
            } else {
                lines = [output]
            }
            
            print("Total lines found: \(lines.count)")
            
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                if trimmed.isEmpty || trimmed.hasPrefix("total") {
                    continue
                }
                
                let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                
                if components.count >= 9 {
                    let permissions = String(components[0])
                    let isDirectory = permissions.first == "d" || permissions.first == "l"
                    let filename = components.dropFirst(8).joined(separator: " ")
                    
                    if filename != "." && filename != ".." {
                        parsed.append(RemoteEntry(name: filename, isDirectory: isDirectory))
                        print("Line \(index): Added '\(filename)' (dir: \(isDirectory))")
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
            
            print("Final entries to display: \(parsed.count)")
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
