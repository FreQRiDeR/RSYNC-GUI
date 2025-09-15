import Foundation

enum SSHClientError: Error {
    case connectionFailed(String)
    case commandFailed(String)
}

protocol SSHClientProtocol {
    // list directory at host (user@host) and path. If password is nil, try key-based/agent.
    func listDirectory(userAtHost: String, path: String, password: String?, completion: @escaping (Result<String, SSHClientError>) -> Void)
}

final class SSHClient {
    static let shared: SSHClientProtocol = SSHClient.makeClient()

    private static func makeClient() -> SSHClientProtocol {
#if canImport(NMSSH)
        return NMSSHClient()
#else
        return ShellSSHClient()
#endif
    }
}

// MARK: - Fallback: Shell-based SSH client
final class ShellSSHClient: SSHClientProtocol {
    func listDirectory(userAtHost: String, path: String, password: String?, completion: @escaping (Result<String, SSHClientError>) -> Void) {
        // Build ssh command
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        let cmd = "/usr/bin/ssh -oBatchMode=yes \(userAtHost) ls -la \"\(escapedPath)\""

        // If password is provided, we cannot non-interactively send it without sshpass; return an informative error
        if let pw = password, !pw.isEmpty {
            completion(.failure(.connectionFailed("Password-based non-interactive SSH requires an external helper (sshpass) or native SSH library. Please install sshpass or set up SSH keys.")))
            return
        }

        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-lc", cmd]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            completion(.failure(.connectionFailed(error.localizedDescription)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""

            if !err.isEmpty {
                completion(.failure(.commandFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))))
                return
            }
            completion(.success(out))
        }
    }
}

#if canImport(NMSSH)
import NMSSH

// NMSSH-backed implementation. Compiled only when NMSSH is added via Swift Package Manager / Xcode.
final class NMSSHClient: SSHClientProtocol {
    func listDirectory(userAtHost: String, path: String, password: String?, completion: @escaping (Result<String, SSHClientError>) -> Void) {
        // userAtHost is like user@host — split
        let parts = userAtHost.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            completion(.failure(.connectionFailed("Invalid user@host: \(userAtHost)")))
            return
        }
        let user = parts[0]
        let host = parts[1]

        let session = NMSSHSession.connect(toHost: host, withUsername: user)
        guard session?.isConnected == true else {
            completion(.failure(.connectionFailed("Failed to connect to \(host)")))
            return
        }

        if let pw = password, !pw.isEmpty {
            session?.authenticate(byPassword: pw)
        } else {
            // Try authenticate by public key or agent
            session?.authenticateBy(inMemoryPublicKey: nil, privateKey: nil, andPassword: nil)
        }

        if session?.isAuthorized == false {
            session?.disconnect()
            completion(.failure(.connectionFailed("Authentication failed for \(userAtHost)")))
            return
        }

        // Use SFTP to list
        let sftp = NMSFTP(session: session!)
        guard sftp.connect() else {
            session?.disconnect()
            completion(.failure(.connectionFailed("Failed to start SFTP")))
            return
        }

        let list = sftp.contentsOfDirectory(atPath: path)
        session?.disconnect()

        if let list = list as? [NMSFTPFile] {
            // Convert to ls-like output lines for compatibility with existing parser
            var outLines: [String] = []
            for f in list {
                let perms = f.longName ?? "-rw-r--r-- 1 user group 0 Jan 1 00:00 \(f.filename ?? "")"
                outLines.append(perms)
            }
            completion(.success(outLines.joined(separator: "\n")))
        } else {
            completion(.failure(.commandFailed("Failed to list directory")))
        }
    }
}
#endif
