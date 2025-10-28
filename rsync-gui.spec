# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['rsync-gui.py'],          # your entry script
    pathex=[],
    binaries=[],
    datas=[],
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
    name='RSYNC-GUI',          # output binary name
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,             # True = show terminal, False = GUI-only
    disable_windowed_traceback=False,
    argv_emulation=False,      # macOS only
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
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
