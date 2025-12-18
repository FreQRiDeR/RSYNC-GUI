# -*- mode: python ; coding: utf-8 -*-
block_cipher = None

a = Analysis(
    ['rsync-gui.py'],
    pathex=[],
    binaries=[],
    datas=[('RSYNC-GUI.icns', '.')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='RSYNC-GUI',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='RSYNC-GUI.icns',  # Add icon here
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='RSYNC-GUI'
)

app = BUNDLE(
    coll,
    name='RSYNC-GUI.app',
    icon='RSYNC-GUI.icns',  # Icon for the .app bundle
    bundle_identifier='com.rsyncgui.app',
    info_plist={
        'CFBundleName': 'RSYNC-GUI',
        'CFBundleDisplayName': 'RSYNC-GUI',
        'CFBundleVersion': '1.0.5',
        'CFBundleShortVersionString': '1.0.5',
        'NSHighResolutionCapable': 'True',
        'LSBackgroundOnly': 'False',
    },
)