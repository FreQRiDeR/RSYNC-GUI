<div align="center">
             <img src="/RSYNC-GUI.png" width="400" />
</div>

RSYNC-GUI
=========

A small macOS SwiftUI GUI wrapper for rsync. It lets you pick local source/target paths (via a file browser), enter remote rsync-style endpoints (user@host:/path), toggle the most popular rsync options, preview the generated command, and run rsync while capturing stdout/stderr into an output pane.

This repository contains a minimal, modern-looking macOS app that demonstrates the core features you requested. It intentionally relies on the system rsync and ssh for remote transfers.

<div align="center">
             <img src="/window1.png" width="700" />
</div>

Quick features
- Local and remote source/target selection (remote entered as `user@host:/path`).
- Common options exposed: Archive (-a), Verbose (-v), Human readable (-h), --progress, --delete, --dry-run.
- Toggle to copy folder contents vs folder itself (adds trailing slash to the source path).
- Command preview (monospaced) and Run/Stop controls.
- Output console capturing stdout and stderr.

How it works
- The app generates an `rsync` command and runs it using `/bin/bash -lc "<command>"` to allow SSH agent forwarding and shell features.
- Remote browsing is not fully implemented; remote endpoints are entered manually. Implementing a full remote file browser requires either:
  - Running `ssh user@host ls -la ...` and parsing the output (basic approach), or
  - Integrating an SSH/SFTP library (libssh2, NMSSH, or similar) for a more robust UI experience.

Requirements
- macOS (development done with SwiftUI). Project is not sandboxed in this demo.
- `rsync` available on PATH (macOS ships with rsync; you can also install a newer rsync with Homebrew if desired).
- SSH access to remote hosts for remote-to-remote transfers. The app does not manage SSH keys or passwords — it relies on the system SSH agent or interactive prompts.

Build & run
1. Open `RSYNC-GUI.xcodeproj` in Xcode (or the workspace if present).
2. Select the macOS target and run the app.

Notes and caveats
- Authentication: For unattended transfers, configure SSH keys and an ssh-agent. The GUI will not capture interactive password prompts reliably. Use passwordless authentication keys for app as it can't reliably use passphrases yet.
- Trailing slash: The "Copy contents of folder" toggle appends a trailing slash to the source path when enabled. This is how rsync distinguishes copying the folder contents (trailing slash) vs the folder itself.
- Output streaming: The app captures stdout and stderr and shows them in the Output pane. If you need truly real-time streaming for very verbose transfers, we can refine the reading loop to use incremental reads of availableData instead of readToEnd() in some setups.

Next improvements (optional)
- Add remote browsing modal that shells out to `ssh user@host ls -la` and lets users pick remote directories.
- Integrate SFTP/SSH library for a native remote browser (better UX and progress reporting).
- Add profiles/presets saving common targets and option sets.
- Add code signing & entitlements if distributing outside development.

Contact
If you want me to add remote browsing, improve output streaming, or add persistent profiles, tell me which feature to implement next and I'll proceed.

Thanks for using RSYNC-GUI!

FreqRiDeR
