#!/usr/bin/env python3
"""Verify a fresh macOS bundle and assemble reproducible release attachments."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def verify_bundle(bundle):
    """Reject personal build paths, escaping links and private data exports."""
    root = bundle.resolve()
    for path in bundle.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(root):
            raise ValueError(f"Bundle symlink escapes: {path.relative_to(bundle)}")
        if not path.is_file():
            continue
        if path.name in {"hosts.json", "credentials.json", ".env", "known_hosts"}:
            raise ValueError(f"Private data in bundle: {path.relative_to(bundle)}")
        data = path.read_bytes()
        users = re.findall(rb"/Users/([A-Za-z0-9._-]+)/", data)
        if any(user not in (b"runner", b"demo", b"user", b"example") for user in users):
            raise ValueError(f"Personal build path: {path.relative_to(bundle)}")
    run("codesign", "--verify", "--deep", "--strict", str(bundle))
    for binary in (bundle / "Contents/MacOS/waytty",
                   bundle / "Contents/Frameworks/App.framework/App"):
        arches = run("lipo", "-archs", str(binary)).split()
        if set(arches) != {"arm64", "x86_64"}:
            raise ValueError(f"Not a Universal binary: {binary.name}")


def main():
    manifest = (ROOT / "crossplatform/app/pubspec.yaml").read_text()
    version, build = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)$", manifest, re.M).groups()
    output = ROOT / "dist/release" / version
    bundle = output / "waytty.app"
    if not bundle.is_dir():
        raise ValueError("Build the release with package_macos_release.sh first")
    for key, expected in (("CFBundleShortVersionString", version), ("CFBundleVersion", build),
                          ("CFBundleIdentifier", "io.github.wayyoungboy.waytty")):
        actual = run("/usr/libexec/PlistBuddy", "-c", f"Print :{key}", str(bundle / "Contents/Info.plist"))
        if actual != expected:
            raise ValueError(f"Bundle {key} does not match source")
    if run("git", "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Release source must be committed and clean")
    verify_bundle(bundle)
    attachments = [output / f"waytty-{version}-{kind}.zip"
                   for kind in ("macos-universal", "source", "serial-sources")]
    if any(path.exists() for path in attachments):
        raise ValueError("Release ZIPs already exist; use a fresh build directory")
    run("ditto", "-c", "-k", "--norsrc", "--keepParent", str(bundle), str(attachments[0]))
    run("git", "archive", "--format=zip", f"--prefix=waytty-{version}/",
        f"--output={attachments[1]}", "HEAD")
    cache = Path(os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache"))) / "hosted/pub.dev"
    local_flutter_libserialport = ROOT / "crossplatform/packages/flutter_libserialport"
    with tempfile.TemporaryDirectory(prefix="waytty-serial-sources-") as temporary:
        sources = Path(temporary) / f"waytty-{version}-serial-sources"
        sources.mkdir()
        package_roots = {
            "libserialport-0.3.0+1": cache / "libserialport-0.3.0+1",
            # Prefer the in-repo fork (jcenter→mavenCentral) when present; fall
            # back to the hosted pub.dev copy for older checkouts.
            "flutter_libserialport-0.6.0": (
                local_flutter_libserialport
                if local_flutter_libserialport.is_dir()
                else cache / "flutter_libserialport-0.6.0"
            ),
        }
        for package, root in package_roots.items():
            if not root.is_dir():
                raise ValueError(f"Missing serial package sources: {root}")
            shutil.copytree(root, sources / package,
                            ignore=shutil.ignore_patterns(
                                ".dart_tool", "build", ".git", "android/.cxx", "example"))
        upstream = Path(temporary) / "libserialport-upstream"
        run("git", "clone", "--quiet", "--depth=1", "--branch=libserialport-0.1.1",
            "https://github.com/sigrokproject/libserialport.git", str(upstream))
        installed = ROOT / "crossplatform/app/macos/Pods/libserialport"
        for path in installed.glob("*.c"):
            if path.read_bytes() != (upstream / path.name).read_bytes():
                raise ValueError(f"Serial source differs from the built pod: {path.name}")
        shutil.copytree(upstream, sources / "libserialport-c",
                        ignore=shutil.ignore_patterns(".git"))
        podspec = Path(run("pod", "spec", "which", "libserialport", "--version=0.1.1"))
        shutil.copy2(podspec, sources / "libserialport-c/libserialport.podspec.json")
        shutil.copy2(ROOT / "docs/RELEASE.md", sources / "BUILDING.md")
        shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", sources / "THIRD_PARTY_NOTICES.md")
        run("gitleaks", "dir", str(sources), "--redact=100", "--no-banner")
        run("ditto", "-c", "-k", "--norsrc", "--keepParent", str(sources), str(attachments[2]))
    info = output / "BUILD_INFO.txt"
    flutter = os.environ.get("WAYTTY_FLUTTER", "flutter")
    info.write_text(f"waytty {version}+{build}\nCommit: {run('git', 'rev-parse', 'HEAD')}\n"
                    f"{run(flutter, '--version')}\n{run('xcodebuild', '-version')}\n"
                    "macOS 12+, arm64 + x86_64; ad-hoc signature, not notarized.\n")
    attachments.append(info)
    sums = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
                   for path in attachments)
    (output / "SHA256SUMS.txt").write_text(sums)
    print(f"Verified release attachments: {output}")


if __name__ == "__main__":
    main()
