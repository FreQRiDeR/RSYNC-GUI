//
//  RsyncManager.swift
//  RSYNC-GUI
//
//  Native SSH implementation for password authentication
//

import Foundation
import Darwin

// MARK: - SSH Connection Manager
class SSHConnectionManager: ObservableObject {
    
    enum SSHError: Error, LocalizedError {
        case connectionFailed(String)
        case authenticationFailed
        case commandExecutionFailed(String)
        case invalidHost
        
        var errorDescription: String? {
            switch self {
            case .connectionFailed(let message):
                return "Connection failed: \(message)"
            case .authenticationFailed:
                return "Authentication failed. Check your credentials."
            case .commandExecutionFailed(let message):
                return "Command execution failed: \(message)"
            case .invalidHost:
                return "Invalid host format. Use user@hostname"
            }
        }
    }
    
    // Execute rsync with password authentication via expect-like PTY handling
    func executeRsyncWithPassword(
        command: String,
        arguments: [String],
        password: String?,
        outputHandler: @escaping (String) -> Void,
        completionHandler: @escaping (Result<Int, SSHError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Create pseudo-terminal pair
            var masterFD: Int32 = -1
            var slaveFD: Int32 = -1
            
            guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
                DispatchQueue.main.async {
                    completionHandler(.failure(.connectionFailed("Failed to create PTY")))
                }
                return
            }
            
            defer {
                close(masterFD)
                close(slaveFD)
            }
            
            let process = Process()
            process.launchPath = command
            process.arguments = arguments
            
            // Redirect stdin/stdout/stderr to slave PTY
            let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
            process.standardInput = slaveHandle
            process.standardOutput = slaveHandle
            process.standardError = slaveHandle
            
            // Start monitoring master PTY for output and password prompts
            let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)
            var passwordSent = false
            
            // Background queue for reading PTY output
            let readQueue = DispatchQueue(label: "pty-reader", qos: .userInitiated)
            let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: readQueue)
            
            readSource.setEventHandler {
                let data = masterHandle.availableData
                if data.count > 0 {
                    
                    if let output = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            outputHandler(output)
                        }
                        
                        // Check for password prompt
                        if !passwordSent,
                           let password = password,
                           !password.isEmpty,
                           (output.lowercased().contains("password:") ||
                            output.lowercased().contains("password for") ||
                            output.contains("'s password:")) {
                            
                            passwordSent = true
                            // Send password followed by newline
                            let passwordData = "\(password)\n".data(using: .utf8)!
                            masterHandle.write(passwordData)
                        }
                    }
                }
            }
            
            readSource.setCancelHandler {
                close(masterFD)
            }
            
            process.terminationHandler = { process in
                readSource.cancel()
                DispatchQueue.main.async {
                    let exitCode = Int(process.terminationStatus)
                    if exitCode == 0 {
                        completionHandler(.success(exitCode))
                    } else {
                        completionHandler(.failure(.commandExecutionFailed("Process exited with code \(exitCode)")))
                    }
                }
            }
            
            readSource.resume()
            
            do {
                try process.run()
            } catch {
                readSource.cancel()
                DispatchQueue.main.async {
                    completionHandler(.failure(.connectionFailed(error.localizedDescription)))
                }
            }
        }
    }
}

// MARK: - Enhanced Rsync Manager
class RsyncManager: ObservableObject {
    @Published var isRunning = false
    @Published var output = ""
    
    private var currentProcess: Process?
    private let sshManager = SSHConnectionManager()
    
    struct RsyncConfig {
        let source: String
        let destination: String
        let options: [String]
        let usePassword: Bool
        let password: String?
        let sshKeyPath: String?
    }
    
    func executeRsync(config: RsyncConfig, outputHandler: @escaping (String) -> Void) {
        guard !isRunning else { return }
        
        isRunning = true
        output = ""
        
        let arguments = self.buildRsyncArguments(config: config)
        let command = "/usr/bin/rsync"
        
        // Log the command for debugging (without password)
        let safeCommand = "\(command) \(arguments.joined(separator: " "))"
        outputHandler("$ \(safeCommand)\n")
        
        if config.usePassword && config.password != nil && !config.password!.isEmpty {
            // Use PTY-based password handling
            sshManager.executeRsyncWithPassword(
                command: command,
                arguments: arguments,
                password: config.password,
                outputHandler: outputHandler
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    switch result {
                    case .success(let exitCode):
                        outputHandler("\nProcess completed with exit code \(exitCode)\n")
                    case .failure(let error):
                        outputHandler("\nError: \(error.localizedDescription)\n")
                    }
                }
            }
        } else {
            // Standard execution without password
            executeStandardRsync(command: command, arguments: arguments, outputHandler: outputHandler)
        }
    }
    
    private func executeStandardRsync(command: String, arguments: [String], outputHandler: @escaping (String) -> Void) {
        let process = Process()
        currentProcess = process
        
        process.launchPath = command
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    outputHandler(output)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    outputHandler(output)
                }
            }
        }
        
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isRunning = false
                let exitCode = process.terminationStatus
                outputHandler("\nProcess completed with exit code \(exitCode)\n")
            }
        }
        
        do {
            try process.run()
        } catch {
            isRunning = false
            outputHandler("Failed to start rsync: \(error.localizedDescription)\n")
        }
    }
    
    private func buildRsyncArguments(config: RsyncConfig) -> [String] {
        var args: [String] = []
        
        // Add options
        args.append(contentsOf: config.options)
        
        // Configure SSH if needed
        if config.source.contains("@") || config.destination.contains("@") {
            var sshOptions = [
                "-oStrictHostKeyChecking=no",
                "-oUserKnownHostsFile=/dev/null",
                "-oGlobalKnownHostsFile=/dev/null"
            ]
            
            // Add SSH key if specified
            if let keyPath = config.sshKeyPath, !keyPath.isEmpty {
                sshOptions.append("-i")
                sshOptions.append(keyPath)
            }
            
            // For password auth, we rely on PTY handling
            if config.usePassword {
                sshOptions.append("-oPasswordAuthentication=yes")
                sshOptions.append("-oPubkeyAuthentication=no")
            } else {
                sshOptions.append("-oPreferredAuthentications=publickey")
            }
            
            args.append("-e")
            args.append("ssh " + sshOptions.joined(separator: " "))
        }
        
        // Add source and destination
        args.append(config.source)
        args.append(config.destination)
        
        return args
    }
    
    func stopRsync() {
        currentProcess?.terminate()
        isRunning = false
    }
}
