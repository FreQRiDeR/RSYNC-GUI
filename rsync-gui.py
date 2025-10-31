import sys, os, json, uuid, subprocess, tempfile
import stat
from datetime import datetime
from PyQt6.QtWidgets import (
    QApplication, QWidget, QLabel, QLineEdit, QTextEdit, QPushButton,
    QVBoxLayout, QHBoxLayout, QCheckBox, QGroupBox, QFileDialog,
    QGridLayout, QSpacerItem, QSizePolicy, QComboBox, QMessageBox, 
)
from PyQt6.QtCore import Qt

BOOKMARK_PATH = os.path.expanduser("~/.config/rsync_gui/bookmarks.json")

class SyncBookmark:
    def __init__(self, name, source, target, options, command, lastUsed=None, id=None):
        self.id = id or str(uuid.uuid4())
        self.name = name
        self.source = source
        self.target = target
        self.options = options
        self.command = command
        self.lastUsed = lastUsed or datetime.now().isoformat()

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "source": self.source,
            "target": self.target,
            "options": self.options,
            "command": self.command,
            "lastUsed": self.lastUsed
        }

    @staticmethod
    def from_dict(d):
        return SyncBookmark(
            name=d["name"],
            source=d["source"],
            target=d["target"],
            options=d["options"],
            command=d["command"],
            lastUsed=d["lastUsed"],
            id=d["id"]
        )

class BookmarkManager:
    def __init__(self):
        self.bookmarks = []
        self.load()

    def load(self):
        try:
            with open(BOOKMARK_PATH, "r") as f:
                data = json.load(f)
                self.bookmarks = [SyncBookmark.from_dict(b) for b in data]
        except:
            self.bookmarks = []

    def save(self):
        os.makedirs(os.path.dirname(BOOKMARK_PATH), exist_ok=True)
        with open(BOOKMARK_PATH, "w") as f:
            json.dump([b.to_dict() for b in self.bookmarks], f, indent=2)

    def add(self, bookmark):
        self.bookmarks = [b for b in self.bookmarks if b.id != bookmark.id]
        self.bookmarks.insert(0, bookmark)
        self.save()

    def delete(self, bookmark_id):
        self.bookmarks = [b for b in self.bookmarks if b.id != bookmark_id]
        self.save()

    def recent(self, limit=10):
        return sorted(self.bookmarks, key=lambda b: b.lastUsed, reverse=True)[:limit]
    
from PyQt6.QtWidgets import QDialog, QVBoxLayout, QListWidget, QPushButton, QLabel

class SSHKeyBrowserDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Select SSH Public Key")
        self.setMinimumSize(500, 300)

        self.layout = QVBoxLayout()
        self.keyList = QListWidget()
        self.preview = QLabel("Select a key to preview its contents.")
        self.preview.setWordWrap(True)
        self.preview.setStyleSheet("font-family: monospace;")

        self.selectBtn = QPushButton("Use Selected Key")
        self.selectBtn.setEnabled(False)
        self.selectBtn.clicked.connect(self.accept)

        self.keyList.currentItemChanged.connect(self.show_preview)

        self.layout.addWidget(self.keyList)
        self.layout.addWidget(self.preview)
        self.layout.addWidget(self.selectBtn)
        self.setLayout(self.layout)

        self.selectedKeyPath = None
        self.load_keys()

    def load_keys(self):
        ssh_dir = os.path.expanduser("~/.ssh")
        if not os.path.exists(ssh_dir):
            self.preview.setText("No ~/.ssh directory found.")
            return

        for file in os.listdir(ssh_dir):
            full_path = os.path.join(ssh_dir, file)
            if os.path.isfile(full_path) and not file.endswith(".pub"):
                self.keyList.addItem(full_path)

    def show_preview(self, current, _):
        if not current:
            self.preview.setText("Select a key to preview its contents.")
            self.selectBtn.setEnabled(False)
            return

        path = current.text()
        try:
            with open(path, "r") as f:
                content = f.read().strip()
                self.preview.setText(content)
                self.selectedKeyPath = path
                self.selectBtn.setEnabled(True)
        except Exception as e:
            self.preview.setText(f"Error reading key: {e}")
            self.selectBtn.setEnabled(False)

    def get_selected_key(self):
        return self.selectedKeyPath
    
import stat
from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QListWidget,
    QPushButton, QSpacerItem, QSizePolicy
)
import paramiko
import os

class RemoteBrowserDialog(QDialog):
    def __init__(self, host, user, key_path, start_path="~", parent=None):
        super().__init__(parent)
        self.setWindowTitle("Browse Remote Path")
        self.setMinimumSize(600, 400)

        self.host = host
        self.user = user
        self.key_path = key_path
        self.current_path = start_path

        # Layouts FIRST
        self.layout = QVBoxLayout()
        self.breadcrumbLayout = QHBoxLayout()
        self.layout.addLayout(self.breadcrumbLayout)

        # Path label
        self.pathLabel = QLabel(f"Current: {self.current_path}")
        self.layout.addWidget(self.pathLabel)

        # File list
        self.fileList = QListWidget()
        self.fileList.itemDoubleClicked.connect(self.enter_directory)
        self.layout.addWidget(self.fileList)

        # Button bar
        btnBar = QHBoxLayout()
        self.upBtn = QPushButton("⬆ Up")
        self.upBtn.setFixedSize(80, 28)
        self.upBtn.clicked.connect(self.go_up_directory)
        btnBar.addWidget(self.upBtn)
        btnBar.addStretch()
        self.selectBtn = QPushButton("Use This Path")
        self.selectBtn.setFixedSize(120, 28)
        self.selectBtn.clicked.connect(self.accept)
        btnBar.addWidget(self.selectBtn)
        self.layout.addLayout(btnBar)

        self.setLayout(self.layout)

        self.selectedPath = None
        self.client = None
        self.sftp = None

        self.connect_ssh()
        self.load_directory()

    def connect_ssh(self):
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.client.connect(hostname=self.host, username=self.user, key_filename=self.key_path)

        # Resolve ~ to full path
        if self.current_path == "~":
            stdin, stdout, stderr = self.client.exec_command("echo $HOME")
            resolved_home = stdout.read().decode().strip()
            self.current_path = resolved_home

        self.sftp = self.client.open_sftp()

    def load_directory(self):
        try:
            self.fileList.clear()
            self.pathLabel.setText(f"Current: {self.current_path}")
            self.update_breadcrumbs()
            self.sftp.chdir(self.current_path)
            items = sorted(self.sftp.listdir())  # Sort alphabetically
            for item in items:
                self.fileList.addItem(item)
        except Exception as e:
            self.fileList.addItem(f"⛔ Error: {e}")

    def enter_directory(self, item):
        name = item.text()
        full_path = os.path.join(self.current_path, name)

        try:
            attr = self.sftp.stat(full_path)
            if stat.S_ISDIR(attr.st_mode):
                self.current_path = full_path
                self.load_directory()
            else:
                self.selectedPath = full_path
                self.accept()
        except Exception as e:
            self.fileList.addItem(f"❌ Error accessing {full_path}: {e}")
            self.selectedPath = full_path
            self.accept()

    def go_up_directory(self):
        parent = os.path.dirname(self.current_path.rstrip("/"))
        if parent and parent != self.current_path:
            self.current_path = parent
            self.load_directory()

    def update_breadcrumbs(self):
        # Clear old buttons
        for i in reversed(range(self.breadcrumbLayout.count())):
            widget = self.breadcrumbLayout.itemAt(i).widget()
            if widget:
                widget.deleteLater()

        parts = self.current_path.strip("/").split("/")
        path_so_far = "/"
        for part in parts:
            path_so_far = os.path.join(path_so_far, part)
            btn = QPushButton(part)
            btn.setStyleSheet("text-decoration: underline; background: none; border: none; color: blue;")
            btn.clicked.connect(lambda _, p=path_so_far: self.jump_to_path(p))
            self.breadcrumbLayout.addWidget(btn)

        self.breadcrumbLayout.addItem(QSpacerItem(20, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum))

    def jump_to_path(self, path):
        self.current_path = path
        self.load_directory()

    def get_selected_path(self):
        return self.selectedPath or self.current_path

    def closeEvent(self, event):
        if self.sftp: self.sftp.close()
        if self.client: self.client.close()
        super().closeEvent(event)

    
class RsyncGUI(QWidget):
    def build_command(self):
        parts = ["rsync"]
        if self.optArchive.isChecked(): parts.append("-a")
        if self.optVerbose.isChecked(): parts.append("-v")
        if self.optProgress.isChecked(): parts.append("--progress")
        if self.optDryRun.isChecked(): parts.append("--dry-run")
        if self.optDelete.isChecked(): parts.append("--delete")
        if self.optIgnoreExisting.isChecked(): parts.append("--ignore-existing")
        if self.optHumanReadable.isChecked(): parts.append("-h")


        # SSH key
        sshParts = []
        keyPath = None
        if self.sourceIsRemote.isChecked() and self.sourceUseSSHKey.isChecked():
            keyPath = self.sourceSSHKeyPath.text().strip()
        elif self.targetIsRemote.isChecked() and self.targetUseSSHKey.isChecked():
            keyPath = self.targetSSHKeyPath.text().strip()

        if keyPath:
            sshParts.append(f'ssh -i "{keyPath}" -o IdentitiesOnly=yes')
            parts.append(f"-e '{' '.join(sshParts)}'")

        # Source
        if self.sourceIsRemote.isChecked():
            src = f"{self.sourceUser.text()}@{self.sourceHost.text()}:{self.sourceRemotePath.text()}"
        else:
            src = self.sourceLocalPath.text().strip()
        if self.copyContents.isChecked() and src and not src.endswith("/"):
            src += "/"

        # Target
        if self.targetIsRemote.isChecked():
            dst = f"{self.targetUser.text()}@{self.targetHost.text()}:{self.targetRemotePath.text()}"
        else:
            dst = self.targetLocalPath.text().strip()

        parts.append(f'"{src}"')
        parts.append(f'"{dst}"')
        return " ".join(parts)

    import subprocess

    def run_rsync(self):
        cmd = self.build_command()
        self.outputLog.append(f"$ {cmd}\n")

        if sys.platform == "darwin":
            escaped_cmd = cmd.replace('"', '\\"')
            script = f'''
            tell application "Terminal"
                activate
                set currentTab to do script "zsh -i -c \\"{escaped_cmd}; echo '\\nPress any key to close...'; read -k 1 -s; osascript -e 'tell application \\\\\\"Terminal\\\\\\" to close (first window whose name contains \\\\\\"rsync\\\\\\")' &> /dev/null || osascript -e 'tell application \\\\\\"Terminal\\\\\\" to close front window'\\""
            end tell
            '''
            result = subprocess.run(["osascript", "-e", script])
            if result.returncode != 0:
                self.outputLog.append("âŒ Failed to launch macOS Terminal.\n")
        else:
            # Linux - create temporary script
            with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
                f.write(f'''#!/bin/bash
{cmd}
echo ""
echo "Press any key to close..."
read -n 1 -s
exit
''')
                script_path = f.name
            
            os.chmod(script_path, 0o755)
            
            try:
                subprocess.Popen([
                    "gnome-terminal", "--",
                    "bash", "-c", f"{script_path}; rm -f {script_path}; exit"
                ])
            except FileNotFoundError:
                self.outputLog.append("⛔ Failed to launch terminal: gnome-terminal not found.\n")
                os.unlink(script_path)


    def update_bookmark(self):
        index = self.bookmarkDropdown.currentIndex()
        if index < 0: return
        bookmark = self.bookmarkDropdown.itemData(index)
        if not bookmark: return

        bookmark.name = self.suggest_bookmark_name()
        bookmark.source = self.get_source_config()
        bookmark.target = self.get_target_config()
        bookmark.options = self.get_options_config()
        bookmark.command = self.build_command()
        bookmark.lastUsed = datetime.now().isoformat()

        self.bookmarkManager.add(bookmark)
        self.update_bookmark_dropdown()
        self.bookmarkDropdown.setCurrentIndex(0)

    def delete_bookmark(self):
        index = self.bookmarkDropdown.currentIndex()
        if index < 0: return
        bookmark = self.bookmarkDropdown.itemData(index)
        if not bookmark: return

        confirm = QMessageBox.question(self, "Delete Bookmark",
            f"Are you sure you want to delete '{bookmark.name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)

        if confirm == QMessageBox.StandardButton.Yes:
            self.bookmarkManager.delete(bookmark.id)
            self.update_bookmark_dropdown()
            self.bookmarkDropdown.setCurrentIndex(-1)
            self.commandPreview.setText("")

    def __init__(self):
        super().__init__()
        from PyQt6.QtGui import QIcon
        import sys, os
        icon_path = os.path.join(getattr(sys, '_MEIPASS', os.path.abspath(".")), "RSYNC-GUI.png")
        self.setWindowIcon(QIcon(icon_path))

        self.setWindowTitle("RSYNC GUI")
        self.setMinimumSize(600, 780)
        self.resize(600, 780)

        self.setWindowTitle("RSYNC GUI")
        self.setMinimumSize(600, 780)   # Prevents shrinking too small
        self.resize(600, 780)  # Sets initial window size

        # Bookmark system
        self.bookmarkManager = BookmarkManager()
        self.bookmarkDropdown = QComboBox()
        self.bookmarkDropdown.currentIndexChanged.connect(self.load_bookmark)
        self.saveBookmarkBtn = QPushButton("Save Job")
        self.saveBookmarkBtn.clicked.connect(self.save_bookmark)
        self.updateBookmarkBtn = QPushButton("Update")
        self.updateBookmarkBtn.clicked.connect(self.update_bookmark)
        self.deleteBookmarkBtn = QPushButton("Delete")
        self.deleteBookmarkBtn.clicked.connect(self.delete_bookmark)

        # Source
        self.sourceIsRemote = QCheckBox("Remote")
        self.sourceUser = QLineEdit()
        self.sourceHost = QLineEdit()
        self.sourceRemotePath = QLineEdit()
        self.sourceLocalPath = QLineEdit()
        self.sourceUseSSHKey = QCheckBox("Use SSH key")
        self.sourceSSHKeyPath = QLineEdit()

        # Target
        self.targetIsRemote = QCheckBox("Remote")
        self.targetUser = QLineEdit()
        self.targetHost = QLineEdit()
        self.targetRemotePath = QLineEdit()
        self.targetLocalPath = QLineEdit()
        self.targetUseSSHKey = QCheckBox("Use SSH key")
        self.targetSSHKeyPath = QLineEdit()

        # Options
        self.optArchive = QCheckBox("Archive (-a)")
        self.optArchive.setChecked(True)

        self.optVerbose = QCheckBox("Verbose (-v)")
        self.optVerbose.setChecked(True)

        self.optProgress = QCheckBox("Progress (--progress)")
        self.optProgress.setChecked(True)

        self.optDryRun = QCheckBox("Dry run (--dry-run)")
        self.optDryRun.setChecked(False)

        self.optDelete = QCheckBox("Delete (--delete)")
        self.optDelete.setChecked(False)

        self.optHumanReadable = QCheckBox("Human readable (-h)")
        self.optHumanReadable.setChecked(True)

        self.optIgnoreExisting = QCheckBox("Ignore existing (--ignore-existing)")
        self.optIgnoreExisting.setChecked(False)

        self.copyContents = QCheckBox("Copy contents (trailing slash)")
        self.copyContents.setChecked(False)


        # Command preview + output
        self.commandPreview = QTextEdit()
        self.commandPreview.setReadOnly(True)
        self.commandPreview.setMaximumHeight(60)
        self.commandPreview.setStyleSheet("font-family: monospace;")

        self.outputLog = QTextEdit()
        self.outputLog.setReadOnly(True)
        self.outputLog.setStyleSheet("font-family: monospace;")

        # Buttons
        runBtn = QPushButton("Run rsync")
        runBtn.clicked.connect(self.run_rsync)

        # Layout
        layout = QVBoxLayout()
        layout.addLayout(self.buildBookmarkBar())
        layout.addWidget(self.buildSourceGroup())
        layout.addWidget(self.buildTargetGroup())
        layout.addWidget(self.buildOptionsGroup())
        layout.addWidget(QLabel("Command Preview:"))
        layout.addWidget(self.commandPreview)
        layout.addWidget(runBtn)
        layout.addWidget(QLabel("Output:"))
        layout.addWidget(self.outputLog)
        self.setLayout(layout)

        # Live preview connections
        self.connectLivePreview()
        self.toggleSourceFields()
        self.toggleTargetFields()
        self.update_bookmark_dropdown()
        self.update_command_preview()

    def buildBookmarkBar(self):
        bar = QHBoxLayout()
        bar.addWidget(QLabel("Bookmarks:"))
        bar.addWidget(self.bookmarkDropdown)
        bar.addWidget(self.saveBookmarkBtn)
        bar.addWidget(self.updateBookmarkBtn)
        bar.addWidget(self.deleteBookmarkBtn)
        return bar
    
    def update_bookmark_dropdown(self):
        self.bookmarkDropdown.blockSignals(True)
        self.bookmarkDropdown.clear()
        self.bookmarkDropdown.addItem("-", None)
        for b in self.bookmarkManager.recent():
            self.bookmarkDropdown.addItem(b.name, b)
        self.bookmarkDropdown.blockSignals(False)
        self.bookmarkDropdown.setCurrentIndex(0)

        if self.bookmarkDropdown.count() == 1:
            self.load_bookmark(0)

    def reset_fields(self):
        # Source
        self.sourceIsRemote.setChecked(False)
        self.sourceUser.clear()
        self.sourceHost.clear()
        self.sourceRemotePath.clear()
        self.sourceLocalPath.clear()
        self.sourceUseSSHKey.setChecked(False)
        self.sourceSSHKeyPath.clear()

        # Target
        self.targetIsRemote.setChecked(False)
        self.targetUser.clear()
        self.targetHost.clear()
        self.targetRemotePath.clear()
        self.targetLocalPath.clear()
        self.targetUseSSHKey.setChecked(False)
        self.targetSSHKeyPath.clear()

        # Options (defaults)
        self.optArchive.setChecked(True)
        self.optVerbose.setChecked(True)
        self.optProgress.setChecked(True)
        self.optDryRun.setChecked(False)
        self.optDelete.setChecked(False)
        self.optHumanReadable.setChecked(True)
        self.optIgnoreExisting.setChecked(False)
        self.copyContents.setChecked(False)

        # Command preview + output
        self.commandPreview.clear()
        self.outputLog.clear()

        # Refresh UI toggles
        self.toggleSourceFields()
        self.toggleTargetFields()
        self.update_command_preview()

    def suggest_bookmark_name(self):
        src = self.sourceRemotePath.text() if self.sourceIsRemote.isChecked() else self.sourceLocalPath.text()
        dst = self.targetRemotePath.text() if self.targetIsRemote.isChecked() else self.targetLocalPath.text()
        return f"{os.path.basename(src)} → {os.path.basename(dst)}"

    def get_source_config(self):
        return {
            "isRemote": self.sourceIsRemote.isChecked(),
            "user": self.sourceUser.text(),
            "host": self.sourceHost.text(),
            "remotePath": self.sourceRemotePath.text(),
            "localPath": self.sourceLocalPath.text(),
            "useSSHKey": self.sourceUseSSHKey.isChecked(),
            "sshKeyPath": self.sourceSSHKeyPath.text()
        }

    def buildSourceGroup(self):
        group = QGroupBox("Source")
        layout = QVBoxLayout()
        layout.addWidget(self.sourceIsRemote)

        self.sourceIsRemote.stateChanged.connect(self.toggleSourceFields)

        self.sourceRemoteBox = QHBoxLayout()
        self.sourceRemoteBox.addWidget(QLabel("User"))
        self.sourceRemoteBox.addWidget(self.sourceUser)
        self.sourceRemoteBox.addWidget(QLabel("Host"))
        self.sourceRemoteBox.addWidget(self.sourceHost)
        self.sourceRemoteBox.addWidget(QLabel("Path"))
        self.sourceRemoteBox.addWidget(self.sourceRemotePath)
        browseRemoteBtn = QPushButton("Browse Remote…")
        browseRemoteBtn.clicked.connect(lambda: self.pick_remote_path(
            self.sourceRemotePath, self.sourceUser, self.sourceHost, self.sourceSSHKeyPath))
        self.sourceRemoteBox.addWidget(browseRemoteBtn)


        self.sourceSSHBox = QHBoxLayout()
        self.sourceSSHBox.addWidget(self.sourceUseSSHKey)
        self.sourceSSHBox.addWidget(QLabel("SSH Key Path"))
        self.sourceSSHBox.addWidget(self.sourceSSHKeyPath)

        self.sourceLocalBox = QHBoxLayout()
        self.sourceLocalBox.addWidget(QLabel("Local Path"))
        self.sourceLocalBox.addWidget(self.sourceLocalPath)
        browseBtn = QPushButton("Browse")
        browseBtn.clicked.connect(lambda: self.pick_folder(self.sourceLocalPath))
        self.sourceLocalBox.addWidget(browseBtn)

        layout.addLayout(self.sourceRemoteBox)
        layout.addLayout(self.sourceSSHBox)
        layout.addLayout(self.sourceLocalBox)
        group.setLayout(layout)
        browseKeyBtn = QPushButton("Browse Key")
        browseKeyBtn.clicked.connect(lambda: self.pick_ssh_key(self.sourceSSHKeyPath))
        self.sourceSSHBox.addWidget(browseKeyBtn)
        return group
              
    def toggleSourceFields(self):
        remote = self.sourceIsRemote.isChecked()
        for i in range(self.sourceRemoteBox.count()):
            self.sourceRemoteBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.sourceSSHBox.count()):
            self.sourceSSHBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.sourceLocalBox.count()):
            self.sourceLocalBox.itemAt(i).widget().setVisible(not remote)

    def buildTargetGroup(self):
        group = QGroupBox("Target")
        layout = QVBoxLayout()
        layout.addWidget(self.targetIsRemote)

        self.targetIsRemote.stateChanged.connect(self.toggleTargetFields)

        self.targetRemoteBox = QHBoxLayout()
        self.targetRemoteBox.addWidget(QLabel("User"))
        self.targetRemoteBox.addWidget(self.targetUser)
        self.targetRemoteBox.addWidget(QLabel("Host"))
        self.targetRemoteBox.addWidget(self.targetHost)
        self.targetRemoteBox.addWidget(QLabel("Path"))
        self.targetRemoteBox.addWidget(self.targetRemotePath)
        browseRemoteBtn = QPushButton("Browse Remote…")
        browseRemoteBtn.clicked.connect(lambda: self.pick_remote_path(
            self.targetRemotePath, self.targetUser, self.targetHost, self.targetSSHKeyPath))
        self.targetRemoteBox.addWidget(browseRemoteBtn)

        

        self.targetSSHBox = QHBoxLayout()
        self.targetSSHBox.addWidget(self.targetUseSSHKey)
        self.targetSSHBox.addWidget(QLabel("SSH Key Path"))
        self.targetSSHBox.addWidget(self.targetSSHKeyPath)

        self.targetLocalBox = QHBoxLayout()
        self.targetLocalBox.addWidget(QLabel("Local Path"))
        self.targetLocalBox.addWidget(self.targetLocalPath)
        browseBtn = QPushButton("Browse")
        browseBtn.clicked.connect(lambda: self.pick_folder(self.targetLocalPath))
        self.targetLocalBox.addWidget(browseBtn)

        layout.addLayout(self.targetRemoteBox)
        layout.addLayout(self.targetSSHBox)
        layout.addLayout(self.targetLocalBox)
        group.setLayout(layout)
        browseKeyBtn = QPushButton("Browse Key")
        browseKeyBtn.clicked.connect(lambda: self.pick_ssh_key(self.targetSSHKeyPath))
        self.targetSSHBox.addWidget(browseKeyBtn)
        return group
    
    def pick_folder(self, field):
        folder = QFileDialog.getExistingDirectory(self, "Select Folder")
        if folder:
            field.setText(folder)

    def pick_remote_path(self, field, userField, hostField, keyField):
        host = hostField.text().strip()
        user = userField.text().strip()
        key = keyField.text().strip()
        if not host or not user or not key:
            QMessageBox.warning(self, "Missing Info", "Please fill in user, host, and SSH key path.")
            return

        # Use existing path from field or default to home
        start_path = field.text().strip() or "~"
        
        dialog = RemoteBrowserDialog(host, user, key, start_path=start_path, parent=self)
        if dialog.exec():
            selected = dialog.get_selected_path()
            if selected:
                field.setText(selected)

    def pick_ssh_key(self, field):
        dialog = SSHKeyBrowserDialog(self)
        if dialog.exec():
            selected = dialog.get_selected_key()
            if selected:
                field.setText(selected)

    def toggleTargetFields(self):
        remote = self.targetIsRemote.isChecked()
        for i in range(self.targetRemoteBox.count()):
            self.targetRemoteBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.targetSSHBox.count()):
            self.targetSSHBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.targetLocalBox.count()):
            self.targetLocalBox.itemAt(i).widget().setVisible(not remote)

    def get_target_config(self):
        return {
            "isRemote": self.targetIsRemote.isChecked(),
            "user": self.targetUser.text(),
            "host": self.targetHost.text(),
            "remotePath": self.targetRemotePath.text(),
            "localPath": self.targetLocalPath.text(),
            "useSSHKey": self.targetUseSSHKey.isChecked(),
            "sshKeyPath": self.targetSSHKeyPath.text()
        }
    
    def buildOptionsGroup(self):
        group = QGroupBox("Options")
        layout = QGridLayout()

        layout.setHorizontalSpacing(170)  # 👈 Add generous spacing between columns
        layout.setVerticalSpacing(8)     # Optional: tighten vertical spacing

        layout.addWidget(self.optArchive, 0, 0)
        layout.addWidget(self.optVerbose, 1, 0)
        layout.addWidget(self.optProgress, 2, 0)
        layout.addWidget(self.optDryRun, 3, 0)

        layout.addWidget(self.optDelete, 0, 1)
        layout.addWidget(self.optHumanReadable, 1, 1)
        layout.addWidget(self.optIgnoreExisting, 2, 1)
        layout.addWidget(self.copyContents, 3, 1)
        
        layout.addItem(QSpacerItem(20, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum), 3, 1)

        group.setLayout(layout)
        return group


    def get_options_config(self):
        return {
            "archive": self.optArchive.isChecked(),
            "verbose": self.optVerbose.isChecked(),
            "progress": self.optProgress.isChecked(),
            "dryRun": self.optDryRun.isChecked(),
            "delete": self.optDelete.isChecked(),
            "humanReadable": self.optHumanReadable.isChecked(),
            "ignoreExisting": self.optIgnoreExisting.isChecked(),
            "copyContents": self.copyContents.isChecked()
        }

    def save_bookmark(self):
        name = self.suggest_bookmark_name()
        bookmark = SyncBookmark(
            name=name,
            source=self.get_source_config(),
            target=self.get_target_config(),
            options=self.get_options_config(),
            command=self.build_command()
        )
        self.bookmarkManager.add(bookmark)
        self.update_bookmark_dropdown()

    def load_bookmark(self, index):
        if index == 0:
            self.reset_fields()
            return

        if index < 0:
            return

        bookmark = self.bookmarkDropdown.itemData(index)
        if not bookmark:
            return

        s = bookmark.source
        self.sourceIsRemote.setChecked(s["isRemote"])
        self.sourceUser.setText(s["user"])
        self.sourceHost.setText(s["host"])
        self.sourceRemotePath.setText(s["remotePath"])
        self.sourceLocalPath.setText(s["localPath"])
        self.sourceUseSSHKey.setChecked(s["useSSHKey"])
        self.sourceSSHKeyPath.setText(s["sshKeyPath"])

        t = bookmark.target
        self.targetIsRemote.setChecked(t["isRemote"])
        self.targetUser.setText(t["user"])
        self.targetHost.setText(t["host"])
        self.targetRemotePath.setText(t["remotePath"])
        self.targetLocalPath.setText(t["localPath"])
        self.targetUseSSHKey.setChecked(t["useSSHKey"])
        self.targetSSHKeyPath.setText(t["sshKeyPath"])

        o = bookmark.options
        self.optArchive.setChecked(o["archive"])
        self.optVerbose.setChecked(o["verbose"])
        self.optProgress.setChecked(o["progress"])
        self.optDryRun.setChecked(o["dryRun"])
        self.optDelete.setChecked(o["delete"])
        self.optHumanReadable.setChecked(o["humanReadable"])
        self.optIgnoreExisting.setChecked(o["ignoreExisting"])
        self.copyContents.setChecked(o["copyContents"])



    def connectLivePreview(self):
        fields = [
            self.sourceUser, self.sourceHost, self.sourceRemotePath, self.sourceLocalPath,
            self.targetUser, self.targetHost, self.targetRemotePath, self.targetLocalPath,
            self.sourceSSHKeyPath, self.targetSSHKeyPath
        ]
        for field in fields:
            field.textChanged.connect(self.update_command_preview)

        toggles = [
            self.sourceIsRemote, self.sourceUseSSHKey,
            self.targetIsRemote, self.targetUseSSHKey,
            self.optArchive, self.optVerbose, self.optProgress,
            self.optDryRun, self.optDelete, self.optHumanReadable,
            self.copyContents
        ]
        for toggle in toggles:
            toggle.stateChanged.connect(self.update_command_preview)

    def update_command_preview(self):
        cmd = self.build_command()
        self.commandPreview.setText(cmd)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = RsyncGUI()
    window.show()
    sys.exit(app.exec())

