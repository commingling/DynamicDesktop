#!/usr/bin/env python3
"""Check matching rules without playing audio or modifying user settings."""
from pathlib import Path
import subprocess
import os
import uuid
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="dynamicdesktop-match-test-") as directory:
    executable = Path(directory) / "match-tests"
    subprocess.run(["swiftc", str(root / "Sources/AmbientSoundManager.swift"),
                    str(root / "Tests/AmbientMatch/main.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

    # Expose state only in an isolated temporary copy; use a fake player and
    # settings domain so no sound plays and no user preferences are changed.
    code = (root / "Sources/AmbientSoundManager.swift").read_text()
    code = code.replace("UserDefaults.standard", 'UserDefaults(suiteName: ProcessInfo.processInfo.environment["DYNAMICDESKTOP_TEST_DEFAULTS"]!)!')
    code = code.replace('private let soundDir = "/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources"',
                        'private let soundDir = ProcessInfo.processInfo.environment["DYNAMICDESKTOP_TEST_SOUNDS"]!')
    for name in ("audioCache", "activePlayer", "currentPlayingFile", "pendingFile", "currentFileRequestToken"):
        code = code.replace("private var " + name, "var " + name)
    (Path(directory) / "AmbientSoundManager.swift").write_text(code)
    sounds = Path(directory) / "sounds"
    sounds.mkdir()
    for name in ("Ocean.m4a", "Stream.m4a"):
        (sounds / name).write_bytes(b"test")
    subprocess.run(["swiftc", str(Path(directory) / "AmbientSoundManager.swift"),
                    str(root / "Tests/AmbientMatch/playback/main.swift"), "-o", str(executable)], check=True)
    env = os.environ.copy()
    env["DYNAMICDESKTOP_TEST_DEFAULTS"] = "DynamicDesktop.AmbientMatchTests." + str(uuid.uuid4())
    env["DYNAMICDESKTOP_TEST_SOUNDS"] = str(sounds)
    subprocess.run([str(executable)], env=env, check=True)
