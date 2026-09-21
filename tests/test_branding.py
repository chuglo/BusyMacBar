#!/usr/bin/env python3
"""Regression check: the distributable must consistently use BusyMacBar."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT / "mac"


def main() -> None:
    package = (MAC / "Package.swift").read_text()
    build_script = (MAC / "build.sh").read_text()
    settings = (MAC / "Sources" / "BusyMacBar" / "Settings.swift").read_text()
    app = (MAC / "Sources" / "BusyMacBar" / "main.swift").read_text()

    assert 'name: "BusyMacBar"' in package
    assert '.executableTarget(name: "BusyMacBar", path: "Sources/BusyMacBar")' in package
    assert 'APP=build/BusyMacBar.app' in build_script
    assert 'CFBundleName</key><string>BusyMacBar</string>' in build_script
    assert 'CFBundleExecutable</key><string>BusyMacBar</string>' in build_script
    assert 'BusyMacBar talks to your BUSY Bar on your local network.' in build_script
    assert 'LEGACY_APP="$HOME/Applications/BusyMac.app"' in build_script
    assert 'Legacy BusyMac installation found' in build_script
    assert 'com.busybar.busymacbar' in build_script
    assert 'BusyMacBar.app' in build_script
    assert 'com.busybar.busymacbar' in settings
    assert 'Quit BusyMacBar' in app


if __name__ == "__main__":
    main()
    print("branding checks passed")
