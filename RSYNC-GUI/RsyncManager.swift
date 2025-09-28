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
        let sshKeyPassphrase: String?
    }
    
    func executeRsync(config: RsyncConfig, outputHandler: @escaping (String) -> Void) {
        guard !isRunning else { return }
        
        isRunning = true
        
        let command = buildRsyncCommand(config: config)
        outputHandler("$ \(command)\n")
        
        executeViaAppleScript(command: command, config: config, outputHandler: outputHandler)
    }
    
    private func buildRsyncCommand(config: RsyncConfig) -> String {
        var parts: [String] = ["/usr/bin/rsync"]  // Use system rsync
        
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
                // When using SSH key, enable public key auth and disable password auth
                sshOptions.append("-oPubkeyAuthentication=yes")
                sshOptions.append("-oPasswordAuthentication=no")
            } else {
                // No SSH key specified - use password authentication
                if config.usePassword {
                    sshOptions.append("-oPasswordAuthentication=yes")
                    sshOptions.append("-oPubkeyAuthentication=no")
                } else {
                    sshOptions.append("-oPreferredAuthentications=publickey")
                }
            }
            
            let sshCommand = "ssh " + sshOptions.joined(separator: " ")
            parts.append("-e \"\(sshCommand)\"")
        }
        
        // Add source and destination (properly escaped)
        parts.append(escapeShellArgument(config.source))
        parts.append(escapeShellArgument(config.destination))
        
        return parts.joined(separator: " ")
    }
    
    private func executeViaAppleScript(command: String, config: RsyncConfig, outputHandler: @escaping (String) -> Void) {
        var fullCommand = command
        
        // For SSH key authentication with passphrase, load key into SSH agent first
        if let keyPath = config.sshKeyPath, !keyPath.isEmpty, let passphrase = config.sshKeyPassphrase, !passphrase.isEmpty {
            // Use expect to load the key into SSH agent, then run rsync normally
            fullCommand = """
            # Load SSH key into agent with passphrase
            expect << 'LOAD_KEY_EOF'
            spawn ssh-add "\(keyPath)"
            expect {
                -re "Enter passphrase.*:" { send "\(passphrase.replacingOccurrences(of: "\"", with: "\\\""))\\r"; exp_continue }
                -re "Identity added.*" { exit 0 }
                eof { exit 0 }
                timeout { exit 1 }
            }
            LOAD_KEY_EOF
            
            # Now run rsync - SSH agent will handle authentication
            \(command)
            
            # Clean up - remove key from agent
            ssh-add -d "\(keyPath)" 2>/dev/null || true
            """
        } else if let pwd = config.password, !pwd.isEmpty {
            // Regular password authentication
            let escapedPassword = pwd.replacingOccurrences(of: "\"", with: "\\\"")
            let tempScriptPath = "/tmp/rsync_script_\(UUID().uuidString).sh"
            
            fullCommand = """
            cat > \(tempScriptPath) << 'SCRIPT_EOF'
            #!/bin/bash
            \(command)
            SCRIPT_EOF
            chmod +x \(tempScriptPath)
            
            expect << 'EXPECT_EOF'
            spawn \(tempScriptPath)
            expect {
                -re ".*assword.*:" { send "\(escapedPassword)\\r"; exp_continue }
                -re ".*yes/no.*" { send "yes\\r"; exp_continue }
                eof { exit 0 }
                timeout { exit 1 }
            }
            EXPECT_EOF
            
            rm -f \(tempScriptPath)
            """
        }
        // If no password/passphrase needed, run command directly
        
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
