#!/bin/bash

VERSION="1.0.5"
ARCH="amd64"
PKG_NAME="RSYNC-GUI"
BUILD_DIR="${PKG_NAME}-deb"
SPEC_FILE="rsync-gui-linux.spec"

# Check if spec file exists
if [ ! -f "$SPEC_FILE" ]; then
    echo "❌ Spec file '$SPEC_FILE' not found!"
    echo "Available spec files:"
    ls -1 *.spec 2>/dev/null || echo "  No spec files found"
    exit 1
fi

echo "🔨 Cleaning previous builds..."
rm -rf dist build ${BUILD_DIR} ${PKG_NAME}_${VERSION}_${ARCH}.deb

echo "📦 Building with PyInstaller using $SPEC_FILE..."
pyinstaller "$SPEC_FILE"

if [ ! -d "dist/RSYNC-GUI" ]; then
    echo "❌ PyInstaller build failed! dist/RSYNC-GUI directory not created."
    echo "Contents of dist/ directory:"
    ls -la dist/ 2>/dev/null || echo "  dist/ directory doesn't exist"
    exit 1
fi

echo "📁 Creating directory structure..."
mkdir -p ${BUILD_DIR}/DEBIAN
mkdir -p ${BUILD_DIR}/usr/bin
mkdir -p ${BUILD_DIR}/usr/share/applications
mkdir -p ${BUILD_DIR}/usr/share/icons/hicolor/256x256/apps
mkdir -p ${BUILD_DIR}/usr/share/pixmaps
mkdir -p ${BUILD_DIR}/opt/${PKG_NAME}

echo "📋 Copying files..."
cp -r dist/RSYNC-GUI/* ${BUILD_DIR}/opt/${PKG_NAME}/

# Copy icon to both locations for maximum compatibility
cp RSYNC-GUI.png ${BUILD_DIR}/usr/share/icons/hicolor/256x256/apps/rsync-gui.png
cp RSYNC-GUI.png ${BUILD_DIR}/usr/share/pixmaps/rsync-gui.png

echo "🚀 Creating launcher script..."
cat > ${BUILD_DIR}/usr/bin/rsync-gui << 'EOF'
#!/bin/bash
cd /opt/RSYNC-GUI
exec ./RSYNC-GUI "$@"
EOF
chmod +x ${BUILD_DIR}/usr/bin/rsync-gui

echo "🖥️  Creating desktop entry..."
cat > ${BUILD_DIR}/usr/share/applications/rsync-gui.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=RSYNC GUI
GenericName=File Synchronization Tool
Comment=Graphical interface for rsync file synchronization
Exec=rsync-gui
Icon=rsync-gui
Terminal=false
Categories=Utility;FileTools;System;FileManager;
Keywords=rsync;sync;backup;transfer;ssh;remote;synchronization;
StartupNotify=true
StartupWMClass=rsync-gui
EOF

echo "📝 Creating control file..."
cat > ${BUILD_DIR}/DEBIAN/control << EOF
Package: rsync-gui
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: rsync, libglib2.0-0, libgl1, libxcb-xinerama0, libxcb-cursor0, libfontconfig1, libdbus-1-3, gnome-terminal | xterm | konsole
Maintainer: Your Name <your.email@example.com>
Description: GUI frontend for rsync
 A PyQt6-based graphical user interface for rsync that supports
 local and remote synchronization with SSH key authentication,
 bookmarks, and remote file browsing.
 .
 Features include:
  - Easy-to-use graphical interface
  - Local and remote (SSH) synchronization
  - SSH key authentication support
  - Job bookmarks for repeated tasks
  - Remote file browser
  - Live command preview
Homepage: https://github.com/yourusername/rsync-gui
EOF

echo "⚙️  Creating postinst script..."
cat > ${BUILD_DIR}/DEBIAN/postinst << 'EOF'
#!/bin/bash
set -e

# Update desktop database
if [ -x /usr/bin/update-desktop-database ]; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi

# Update icon cache
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Update mime database
if [ -x /usr/bin/update-mime-database ]; then
    update-mime-database /usr/share/mime 2>/dev/null || true
fi

exit 0
EOF
chmod +x ${BUILD_DIR}/DEBIAN/postinst

echo "⚙️  Creating postrm script..."
cat > ${BUILD_DIR}/DEBIAN/postrm << 'EOF'
#!/bin/bash
set -e

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    # Update desktop database
    if [ -x /usr/bin/update-desktop-database ]; then
        update-desktop-database -q /usr/share/applications 2>/dev/null || true
    fi

    # Update icon cache
    if [ -x /usr/bin/gtk-update-icon-cache ]; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
    fi
fi

exit 0
EOF
chmod +x ${BUILD_DIR}/DEBIAN/postrm

echo "🔒 Setting permissions..."
find ${BUILD_DIR}/opt/${PKG_NAME} -type f -exec chmod 644 {} \;
find ${BUILD_DIR}/opt/${PKG_NAME} -type d -exec chmod 755 {} \;
chmod 755 ${BUILD_DIR}/opt/${PKG_NAME}/RSYNC-GUI
chmod 755 ${BUILD_DIR}/usr/bin/rsync-gui
chmod 644 ${BUILD_DIR}/usr/share/applications/rsync-gui.desktop
chmod 644 ${BUILD_DIR}/usr/share/icons/hicolor/256x256/apps/rsync-gui.png
chmod 644 ${BUILD_DIR}/usr/share/pixmaps/rsync-gui.png

echo "📦 Building .deb package..."
fakeroot dpkg-deb --build ${BUILD_DIR} ${PKG_NAME}_${VERSION}_${ARCH}.deb

echo "🧹 Cleaning up..."
rm -rf ${BUILD_DIR}

echo ""
echo "✅ Package built successfully: ${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo ""
echo "📥 To install:"
echo "   sudo apt install ./${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo ""
echo "🔄 Or if already installed, reinstall with:"
echo "   sudo apt remove rsync-gui && sudo apt install ./${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo ""
echo "🗑️  To uninstall:"
echo "   sudo apt remove rsync-gui"