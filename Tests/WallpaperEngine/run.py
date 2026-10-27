#!/usr/bin/env python3
"""Run the engine with fake windows, temporary video fixtures and isolated defaults."""
from pathlib import Path
import os
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="dynamicdesktop-engine-test-") as directory:
    temp = Path(directory)
    # Isolate the three UserDefaults reads/writes without editing production files.
    source = (root / "Sources/WallpaperEngine.swift").read_text()
    source = source.replace('UserDefaults.standard', 'UserDefaults(suiteName: ProcessInfo.processInfo.environment["DYNAMICDESKTOP_TEST_DEFAULTS"]!)!')
    (temp / "WallpaperEngine.swift").write_text(source)
    executable = temp / "engine-tests"
    subprocess.run(["swiftc", str(temp / "WallpaperEngine.swift"),
                    str(root / "Tests/WallpaperEngine/VideoFixture.swift"),
                    str(root / "Tests/WallpaperEngine/main.swift"), "-o", str(executable)], check=True)
    env = os.environ.copy()
    env["DYNAMICDESKTOP_TEST_DEFAULTS"] = "DynamicDesktop.EngineTests." + str(uuid.uuid4())
    subprocess.run([str(executable), directory], env=env, check=True)
