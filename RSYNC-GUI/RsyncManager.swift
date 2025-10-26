//
//  RsyncManager.swift
//  RSYNC-GUI
//
//  Created by FreQRiDeR on 9/15/25.
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
        
        executeViaTerminal(command: command, config: config, outputHandler: outputHandler)
    }
    
    private func buildRsyncCommand(config: RsyncConfig) -> String {
        var parts: [String] = ["rsync"]
        
        // Add options
        parts.append(contentsOf: config.options)
        
        // Configure SSH if needed
        if config.source.contains("@") || config.destination.contains("@") {
            var sshParts: [String] = ["ssh"]
            
            if let keyPath = config.sshKeyPath, !keyPath.isEmpty {
                // Use tilde notation for cleaner command
                let tidyPath: String
                if keyPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    tidyPath = "~" + keyPath.dropFirst(home.count)
                } else {
                    tidyPath = keyPath
                }
                
                sshParts.append("-i")
                sshParts.append(tidyPath)
            }
            
            let sshCommand = sshParts.joined(separator: " ")
            parts.append("-e")
            parts.append("'\(sshCommand)'")
        }
        
        // Add source and destination (properly escaped)
        parts.append(escapeShellArgument(config.source))
        parts.append(escapeShellArgument(config.destination))
        
        return parts.joined(separator: " ")
    }
    
    private func executeViaTerminal(command: String, config: RsyncConfig, outputHandler: @escaping (String) -> Void) {
        // Build the full command - rsync will use system PATH
        let fullCommand = "\(command); echo ''; echo 'Press any key to close this window...'; read -n 1; exit 0"
        
        // Escape for AppleScript: backslashes first, then double quotes
        let escapedForAppleScript = fullCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        // AppleScript to launch Terminal and execute the command
        let appleScript = """
        if application "Terminal" is not running then
            tell application "Terminal"
                launch
                do script "\(escapedForAppleScript)"
            end tell
        else
            tell application "Terminal"
                activate
                do script "\(escapedForAppleScript)"
            end tell
        end if
        """
        
        outputHandler("Launching Terminal...\n")
        outputHandler("Command: \(command)\n\n")
        
        print("=== AppleScript Debug ===")
        print(appleScript)
        print("=== End Debug ===")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: appleScript)
            var errorDict: NSDictionary?
            let result = script?.executeAndReturnError(&errorDict)
            
            DispatchQueue.main.async {
                self.isRunning = false
                
                if let error = errorDict {
                    let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                    outputHandler("❌ Error launching Terminal: \(errorMessage)\n")
                    outputHandler("Make sure Terminal.app has necessary permissions.\n")
                } else {
                    outputHandler("✅ Command sent to Terminal successfully\n")
                    outputHandler("Terminal window opened - monitor progress there.\n")
                    
                    if let output = result?.stringValue, !output.isEmpty {
                        outputHandler("Terminal response: \(output)\n")
                    }
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
