#!/usr/bin/env python3
"""Put an `apk`-backend game on a USB-attached Android device, over adb.

The Strom client does the same job over the air (fetch the pinned APK,
fetch the payload from IPFS, open the app); this is the wired version for
a recipe that is not pinned yet, and for the one thing the client cannot
do: since Android 11 no app may write into another app's `Android/data`,
so a port with no file picker (`android.apk.files` in the manifest) only
gets its data from a PC.

    scripts/android-adb-install.py <slug> [--serial S] [--launch] [--no-payload]

Reads `nix build .#androidManifests.<slug>`, installs the APK it pins (by URL and sha256, the bytes the client installs),
pushes `.#androidPayloads.<slug>` to `/sdcard/Download/Strom/<slug>`
(where the client would have put it), then pushes every `files` entry to
its absolute device path. Prints the recipe's setup text with `{dir}`
filled in, because the picker step inside the port is still the player's.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEVICE_ROOT = "/sdcard/Download/Strom"


def nix_build(attr: str) -> Path:
    proc = subprocess.run(
        ["nix", "build", f"{ROOT}#{attr}", "--no-link", "--print-out-paths"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        sys.exit(1)
    return Path(proc.stdout.strip().splitlines()[-1])


def adb(
    serial: str | None, *args: str, check: bool = True
) -> subprocess.CompletedProcess:
    cmd = ["adb"] + (["-s", serial] if serial else []) + list(args)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        sys.stderr.write(f"{' '.join(cmd)}\n{proc.stdout}{proc.stderr}")
        sys.exit(1)
    return proc


def fetch_apk(apk: dict) -> Path:
    """The bytes the client installs: the manifest's URL, checked against its
    sha256. Not `.#apks.<slug>`: a game that builds its own APK (balatro's
    balatromobile build) keeps that under `outputs.apk`, while the port the
    `apk` backend installs is the one named here."""
    cache = Path.home() / ".cache/strom-apk"
    cache.mkdir(parents=True, exist_ok=True)
    out = cache / f"{apk['appId']}-{apk['version']}.apk"
    if not (
        out.is_file() and hashlib.sha256(out.read_bytes()).hexdigest() == apk["sha256"]
    ):
        with urllib.request.urlopen(apk["url"]) as r:
            data = r.read()
        got = hashlib.sha256(data).hexdigest()
        if got != apk["sha256"]:
            sys.exit(f"{apk['url']}: sha256 {got}, manifest says {apk['sha256']}")
        out.write_bytes(data)
    return out


def push_tree(serial: str | None, tree: Path, dest: str) -> int:
    """Push every file under `tree` to `dest`, keeping relative paths."""
    n = 0
    for f in sorted(p for p in tree.rglob("*") if p.is_file()):
        rel = f.relative_to(tree).as_posix()
        target = f"{dest}/{rel}"
        parent = target.rsplit("/", 1)[0]
        adb(serial, "shell", "mkdir", "-p", f"'{parent}'")
        adb(serial, "push", str(f), target)
        n += 1
    return n


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("slug")
    ap.add_argument("--serial", "-s", help="adb device serial")
    ap.add_argument("--launch", action="store_true", help="open the app afterwards")
    ap.add_argument("--no-payload", action="store_true", help="install the APK only")
    a = ap.parse_args()

    manifest = json.loads(nix_build(f"androidManifests.{a.slug}").read_text())
    if manifest.get("backend") != "apk":
        sys.exit(f"{a.slug}: backend is {manifest.get('backend')!r}, not 'apk'")
    apk = manifest["apk"]
    app_id = apk["appId"]

    print(f"installing {app_id} {apk['version']}")
    adb(a.serial, "install", "-r", str(fetch_apk(apk)))

    device_dir = f"{DEVICE_ROOT}/{a.slug}"
    if not a.no_payload and "payload" in manifest:
        tree = nix_build(f"androidPayloads.{a.slug}")
        print(f"pushing payload to {device_dir}")
        n = push_tree(a.serial, tree, device_dir)
        print(f"pushed {n} files")
        for rel, dest in apk.get("files", {}).items():
            src = tree / rel
            if not src.is_file():
                sys.exit(f"{a.slug}: files entry {rel!r} is not in the payload tree")
            parent = dest.rsplit("/", 1)[0]
            adb(a.serial, "shell", "mkdir", "-p", f"'{parent}'")
            adb(a.serial, "push", str(src), dest)
            print(f"placed {rel} -> {dest}")

    setup = apk.get("setup", "").replace("{dir}", device_dir)
    if setup:
        print(f"in the app: {setup}")

    if a.launch:
        adb(
            a.serial,
            "shell",
            "monkey",
            "-p",
            app_id,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        )
        print(f"launched {app_id}")


if __name__ == "__main__":
    main()
