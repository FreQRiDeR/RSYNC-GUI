//
//  RsyncManager.swift
//  RSYNC-GUI
//
//  AppleScript-based implementation to bypass sandboxing
//

import Foundation
import AppKit

class RsyncManager: ObservableObject {
    @Published var isRunning = false
    
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
        
        let command = buildRsyncCommand(config: config)
        outputHandler("$ \(command)\n")
        
        executeViaAppleScript(command: command, password: config.password, outputHandler: outputHandler)
    }
    
    private func buildRsyncCommand(config: RsyncConfig) -> String {
        var parts: [String] = ["rsync"]
        
        // Add options
        parts.append(contentsOf: config.options)
        
        // Configure SSH if needed
        if config.source.contains("@") || config.destination.contains("@") {
            var sshOptions = [
                "-oStrictHostKeyChecking=no",
                "-oUserKnownHostsFile=/dev/null",
                "-oGlobalKnownHostsFile=/dev/null"
            ]
            
            // Add SSH key if specified
            if let keyPath = config.sshKeyPath, !keyPath.isEmpty {
                sshOptions.append("-i \"\(keyPath)\"")
            }
            
            // Authentication preferences
            if config.usePassword {
                sshOptions.append("-oPasswordAuthentication=yes")
                sshOptions.append("-oPubkeyAuthentication=no")
            } else {
                sshOptions.append("-oPreferredAuthentications=publickey")
            }
            
            let sshCommand = "ssh " + sshOptions.joined(separator: " ")
            parts.append("-e \"\(sshCommand)\"")
        }
        
        // Add source and destination (properly escaped)
        parts.append(escapeShellArgument(config.source))
        parts.append(escapeShellArgument(config.destination))
        
        return parts.joined(separator: " ")
    }
    
    private func executeViaAppleScript(command: String, password: String?, outputHandler: @escaping (String) -> Void) {
        var fullCommand = command
        
        // If password is provided, use expect for automation
        if let pwd = password, !pwd.isEmpty {
            let escapedPassword = pwd.replacingOccurrences(of: "'", with: "'\"'\"'")
            let escapedCommand = command.replacingOccurrences(of: "'", with: "'\"'\"'")
            
            fullCommand = """
            expect -c "
            spawn sh -c '\(escapedCommand)'
            expect {
                -re \\".*assword.*:\\" { send \\"\(escapedPassword)\\\\r\\"; exp_continue }
                -re \\".*yes/no.*\\" { send \\"yes\\\\r\\"; exp_continue }
                eof { exit }
                timeout { exit 1 }
            }
            "
            """
        }
        
        // Escape the command for AppleScript
        let escapedForAppleScript = fullCommand.replacingOccurrences(of: "\\", with: "\\\\")
                                                .replacingOccurrences(of: "\"", with: "\\\"")
        
        let appleScript = """
        do shell script "\(escapedForAppleScript)"
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: appleScript)
            var errorDict: NSDictionary?
            
            let result = script?.executeAndReturnError(&errorDict)
            
            DispatchQueue.main.async {
                self.isRunning = false
                
                if let error = errorDict {
                    let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                    outputHandler("Error: \(errorMessage)\n")
                } else {
                    // AppleScript do shell script captures stdout
                    if let output = result?.stringValue, !output.isEmpty {
                        outputHandler(output)
                    }
                    outputHandler("\nCommand completed successfully\n")
                }
            }
        }
    }
    
    private func escapeShellArgument(_ argument: String) -> String {
        // Escape special characters for shell execution
        let escaped = argument.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
    
    func stopRsync() {
        isRunning = false
        
        // Try to kill any running rsync processes
        let killScript = "do shell script \"pkill -f rsync\" with administrator privileges"
        let script = NSAppleScript(source: killScript)
        var errorDict: NSDictionary?
        script?.executeAndReturnError(&errorDict)
    }
}
