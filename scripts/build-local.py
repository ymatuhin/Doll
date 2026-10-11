#!/usr/bin/env python3
"""Build a locally signed Doll.app using macOS Command Line Tools (no Xcode)."""
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
DEPS = BUILD / "dependencies"
APP = BUILD / "Doll.app"
MIN_MACOS = "12.0"


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def write_plist(path, values):
    with path.open("wb") as stream:
        plistlib.dump(values, stream)


def main():
    if platform.system() != "Darwin":
        raise SystemExit("This build requires macOS Command Line Tools.")
    DEPS.mkdir(parents=True, exist_ok=True)
    pins = json.loads((ROOT / "Doll.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["object"]["pins"]
    for pin in pins:
        name, revision = pin["package"], pin["state"]["revision"]
        dest = DEPS / name
        stamp = dest / ".doll-revision"
        if stamp.exists() and stamp.read_text() == revision:
            continue
        repo = pin["repositoryURL"].replace("git@github.com:", "https://github.com/").removesuffix(".git")
        archive = DEPS / f"{name}.tar.gz"
        run("curl", "-fLsS", "--retry", "3", f"{repo}/archive/{revision}.tar.gz", "-o", archive)
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir()
        run("tar", "-xzf", archive, "-C", dest, "--strip-components=1")
        stamp.write_text(revision)

    sources = BUILD / "Sources/Doll"
    if sources.exists():
        shutil.rmtree(sources)
    for source in (ROOT / "Doll").rglob("*.swift"):
        target = sources / source.relative_to(ROOT / "Doll")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    (BUILD / "Package.swift").write_text('''// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "DollLocal", platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../MonitorCore"),
        .package(path: "dependencies/KeyboardShortcuts"),
        .package(path: "dependencies/LaunchAtLogin"),
        .package(path: "dependencies/Introspect")
    ],
    targets: [.executableTarget(name: "Doll", dependencies: [
        .product(name: "Monitor", package: "MonitorCore"),
        .product(name: "Utils", package: "MonitorCore"),
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        .product(name: "LaunchAtLogin", package: "LaunchAtLogin"),
        .product(name: "Introspect", package: "Introspect")
    ])]
)
''')
    default_sdk = Path(subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip())
    # CLT 27 ships SwiftUI's new @State macro declarations without SwiftUIMacros.
    # Prefer the installed 26.5 SDK; DOLL_SDKROOT can select another SDK.
    compatible_sdk = default_sdk.parent / "MacOSX26.5.sdk"
    sdk = os.environ.get("DOLL_SDKROOT") or str(
        compatible_sdk if compatible_sdk.exists() else default_sdk)
    env = dict(os.environ, SDKROOT=sdk,
               CLANG_MODULE_CACHE_PATH=str(BUILD / "module-cache"))
    swift_args = ["xcrun", "swift", "build", "--package-path", BUILD,
                  "--disable-sandbox", "--cache-path", BUILD / "cache",
                  "--configuration", "release", "--sdk", sdk]
    run(*swift_args, env=env)
    products = Path(subprocess.check_output(
        [str(arg) for arg in swift_args + ["--show-bin-path"]], env=env, text=True).strip())

    if APP.exists():
        shutil.rmtree(APP)
    contents = APP / "Contents"
    resources = contents / "Resources"
    (contents / "MacOS").mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(products / "Doll", contents / "MacOS/Doll")
    for bundle in products.glob("*.bundle"):
        shutil.copytree(bundle, resources / bundle.name)
    for localization in (ROOT / "Doll").glob("*.lproj"):
        shutil.copytree(localization, resources / localization.name)
    # AppKit also loads named loose images; asset catalogs require Xcode's actool.
    assets = ROOT / "Doll/Assets.xcassets"
    for imageset in assets.glob("*.imageset"):
        items = json.loads((imageset / "Contents.json").read_text())["images"]
        for item in items:
            if "filename" in item:
                source = imageset / item["filename"]
                scale = "" if item.get("scale", "1x") == "1x" else "@" + item["scale"]
                shutil.copy2(source, resources / f"{imageset.stem}{scale}{source.suffix}")
    iconset = BUILD / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "" if scale == 1 else "@2x"
            shutil.copy2(assets / f"AppIcon.appiconset/{size * scale}.png",
                         iconset / f"icon_{size}x{size}{suffix}.png")
    run("iconutil", "-c", "icns", iconset, "-o", resources / "AppIcon.icns")
    write_plist(contents / "Info.plist", {
        "CFBundleExecutable": "Doll", "CFBundleIdentifier": "com.xiaogd.Doll",
        "CFBundleName": "Doll", "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundleDevelopmentRegion": "en",
        "CFBundleShortVersionString": "0.0.9.3", "CFBundleVersion": "5",
        "CFBundleIconFile": "AppIcon", "LSMinimumSystemVersion": MIN_MACOS,
        "LSUIElement": True, "NSPrincipalClass": "Doll.DollApplication",
        "DollIncludedPullRequests": [70, 71, 75],
    })
    # Compile the login helper from the same pinned sources, without Xcode's copy phase.
    helper = contents / "Library/LoginItems/LaunchAtLoginHelper.app/Contents"
    (helper / "MacOS").mkdir(parents=True)
    run("xcrun", "swiftc", "-O", "-sdk", sdk,
        "-target", f"{platform.machine()}-apple-macosx{MIN_MACOS}",
        DEPS / "LaunchAtLogin/Sources/LaunchAtLoginHelper/main.swift",
        "-o", helper / "MacOS/LaunchAtLoginHelper", env=env)
    write_plist(helper / "Info.plist", {
        "CFBundleExecutable": "LaunchAtLoginHelper",
        "CFBundleIdentifier": "com.xiaogd.Doll-LaunchAtLoginHelper",
        "CFBundleName": "LaunchAtLoginHelper", "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundleVersion": "1",
        "LSBackgroundOnly": True, "LSMinimumSystemVersion": MIN_MACOS,
        "NSPrincipalClass": "NSApplication",
    })
    licenses = resources / "Licenses"
    licenses.mkdir()
    for name in ("KeyboardShortcuts", "LaunchAtLogin", "Introspect"):
        for license_file in (DEPS / name).iterdir():
            if license_file.name.lower() in ("license", "license.md", "license.txt"):
                shutil.copy2(license_file, licenses / f"{name}.txt")
    for license_file in ROOT.glob("LICENSE*"):
        shutil.copy2(license_file, licenses / license_file.name)
    run("codesign", "--force", "--sign", "-", helper.parent)
    run("codesign", "--force", "--sign", "-", APP)
    run("codesign", "--verify", "--deep", "--strict", APP)
    archive = BUILD / f"Doll-0.0.9.3-{platform.machine()}.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, archive)
    print(f"Built: {APP}\nArchive: {archive}")


if __name__ == "__main__":
    main()
