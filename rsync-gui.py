import sys
import subprocess
from PyQt6.QtWidgets import (
    QApplication, QWidget, QLabel, QLineEdit, QTextEdit, QPushButton,
    QVBoxLayout, QHBoxLayout, QCheckBox, QGroupBox, QFileDialog,
    QGridLayout, QSpacerItem, QSizePolicy
)
from PyQt6.QtCore import Qt

import os, json, uuid
from datetime import datetime

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

    def recent(self, limit=8):
        return sorted(self.bookmarks, key=lambda b: b.lastUsed, reverse=True)[:limit]


class RsyncGUI(QWidget):
    def update_bookmark_dropdown(self):
        self.bookmarkDropdown.blockSignals(True)
        self.bookmarkDropdown.clear()
        for b in self.bookmarkManager.recent():
            self.bookmarkDropdown.addItem(b.name, b)
        self.bookmarkDropdown.blockSignals(False)

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

    def get_options_config(self):
        return {
            "archive": self.optArchive.isChecked(),
            "verbose": self.optVerbose.isChecked(),
            "progress": self.optProgress.isChecked(),
            "dryRun": self.optDryRun.isChecked(),
            "delete": self.optDelete.isChecked(),
            "humanReadable": self.optHumanReadable.isChecked(),
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
        if index < 0: return
        bookmark = self.bookmarkDropdown.itemData(index)
        if not bookmark: return

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
        self.copyContents.setChecked(o["copyContents"])

        self.update_command_preview()

    def buildBookmarkBar(self):
        bar = QHBoxLayout()
        bar.addWidget(QLabel("Bookmarks:"))
        bar.addWidget(self.bookmarkDropdown)
        bar.addWidget(self.saveBookmarkBtn)
        return bar

    def __init__(self):
        super().__init__()
        self.bookmarkManager = BookmarkManager()
        self.bookmarkDropdown = QComboBox()
        self.bookmarkDropdown.currentIndexChanged.connect(self.load_bookmark)
        self.saveBookmarkBtn = QPushButton("Save Job")
        self.saveBookmarkBtn.clicked.connect(self.save_bookmark)

        self.setWindowTitle("RSYNC GUI")
        self.setMinimumSize(720, 680)

        layout.addLayout(self.buildBookmarkBar())

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
        self.optVerbose = QCheckBox("Verbose (-v)")
        self.optProgress = QCheckBox("Progress (--progress)")
        self.optDryRun = QCheckBox("Dry run (--dry-run)")
        self.optDelete = QCheckBox("Delete (--delete)")
        self.optHumanReadable = QCheckBox("Human readable (-h)")
        self.copyContents = QCheckBox("Copy contents (trailing slash)")

        # Command preview + output
        self.commandPreview = QLabel()
        self.outputLog = QTextEdit()
        self.outputLog.setReadOnly(True)

        # Buttons
        runBtn = QPushButton("Run rsync")
        runBtn.clicked.connect(self.run_rsync)

        # Layout
        layout = QVBoxLayout()
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
        self.update_command_preview()

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
        return group

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
        return group

    def buildOptionsGroup(self):
        group = QGroupBox("Options")
        layout = QGridLayout()
        layout.addWidget(self.optArchive, 0, 0)
        layout.addWidget(self.optVerbose, 1, 0)
        layout.addWidget(self.optProgress, 2, 0)
        layout.addWidget(self.optDryRun, 3, 0)
        layout.addWidget(self.optDelete, 0, 1)
        layout.addWidget(self.optHumanReadable, 1, 1)
        layout.addWidget(self.copyContents, 2, 1)
        layout.addItem(QSpacerItem(20, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum), 3, 1)
        group.setLayout(layout)
        return group

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

    def toggleSourceFields(self):
        remote = self.sourceIsRemote.isChecked()
        for i in range(self.sourceRemoteBox.count()):
            self.sourceRemoteBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.sourceSSHBox.count()):
            self.sourceSSHBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.sourceLocalBox.count()):
            self.sourceLocalBox.itemAt(i).widget().setVisible(not remote)

    def toggleTargetFields(self):
        remote = self.targetIsRemote.isChecked()
        for i in range(self.targetRemoteBox.count()):
            self.targetRemoteBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.targetSSHBox.count()):
            self.targetSSHBox.itemAt(i).widget().setVisible(remote)
        for i in range(self.targetLocalBox.count()):
            self.targetLocalBox.itemAt(i).widget().setVisible(not remote)

    def build_command(self):
        parts = ["rsync"]
        if self.optArchive.isChecked(): parts.append("-a")
        if self.optVerbose.isChecked(): parts.append("-v")
        if self.optProgress.isChecked(): parts.append("--progress")
        if self.optDryRun.isChecked(): parts.append("--dry-run")
        if self.optDelete.isChecked(): parts.append("--delete")
        if self.optHumanReadable.isChecked(): parts.append("-h")

        # SSH key
        sshParts = []
        keyPath = None
        if self.sourceIsRemote.isChecked() and self.sourceUseSSHKey.isChecked():
            keyPath = self.sourceSSHKeyPath.text().strip()
        elif self.targetIsRemote.isChecked() and self.targetUseSSHKey.isChecked():
            keyPath = self.targetSSHKeyPath.text().strip()

        if keyPath:
            sshParts.append("ssh -i \"" + keyPath + "\"")
            parts.append("-e '" + " ".join(sshParts) + "'")

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

    def update_command_preview(self):
        cmd = self.build_command()
        self.commandPreview.setText(cmd)

    def run_rsync(self):
        cmd = self.build_command()
        self.outputLog.append(f"$ {cmd}\n")

        try:
            process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                self.outputLog.append(line)
        except Exception as e:
            self.outputLog.append(f"❌ Error: {e}")

    def pick_folder(self, field):
        folder = QFileDialog.getExistingDirectory(self, "Select Folder")
        if folder:
            field.setText(folder)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = RsyncGUI()
    window.show()
    sys.exit(app.exec())

