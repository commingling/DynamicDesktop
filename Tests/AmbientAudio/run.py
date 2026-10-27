#!/usr/bin/env python3
"""Exercise the real ambient-sound processor with an installed system sound."""
from array import array
from pathlib import Path
import math
import subprocess
import sys
import tempfile
import wave

root = Path(__file__).resolve().parents[2]
source = root / "Sources/AmbientSoundManager.swift"
fixture = Path("/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources/Stream.m4a")

with tempfile.TemporaryDirectory(prefix="dynamicdesktop-audio-test-") as directory:
    temp = Path(directory)
    # Expose just the processor in a temporary copy; never touch user audio settings.
    code = source.read_text()
    old = "private static func processAudioFile("
    if old not in code:
        raise SystemExit("Audio processor entry point has changed; update this test")
    (temp / "AmbientSoundManager.swift").write_text(code.replace(old, "static func processAudioFile(", 1))
    executable = temp / "audio-test"
    subprocess.run(["swiftc", str(temp / "AmbientSoundManager.swift"),
                    str(root / "Tests/AmbientAudio/main.swift"), "-o", str(executable)], check=True)
    raw_path, warm_path = temp / "raw.wav", temp / "warm.wav"

    def read_audio(path):
        with wave.open(str(path), "rb") as audio:
            channels = audio.getnchannels()
            assert audio.getsampwidth() == 2
            samples = array("h", audio.readframes(audio.getnframes()))
            if sys.byteorder != "little":
                samples.byteswap()
            return channels, samples

    # A near-full-scale correlated stereo tone exercises overlap headroom even
    # on machines without Apple's private sound resources.
    synthetic = temp / "tone.wav"
    with wave.open(str(synthetic), "wb") as tone:
        tone.setnchannels(2)
        tone.setsampwidth(2)
        tone.setframerate(48000)
        samples = array("h")
        for i in range(48000 * 3):
            value = round(32767 * 0.995 * math.sin(2 * math.pi * 440 * i / 48000))
            samples.extend((value, value))
        if sys.byteorder != "little":
            samples.byteswap()
        tone.writeframes(samples.tobytes())
    subprocess.run([str(executable), str(synthetic), str(raw_path), str(warm_path)], check=True)
    for path in (raw_path, warm_path):
        _, samples = read_audio(path)
        assert max(map(abs, samples)) <= 32113, "synthetic near-full-scale audio lost headroom"

    if not fixture.exists():
        print("Ambient audio headroom test passed; Stream.m4a checks skipped (not available)")
        raise SystemExit(0)
    subprocess.run([str(executable), str(fixture), str(raw_path), str(warm_path)], check=True)
    channels, raw = read_audio(raw_path)
    warm_channels, warm = read_audio(warm_path)
    assert channels == warm_channels and len(raw) == len(warm) and len(warm) > channels * 1000
    assert max(map(abs, warm)) < 32760, "processed audio clips"

    # Second differences emphasize high frequencies without external libraries.
    def high_frequency_energy(samples):
        return sum((samples[i] - 2 * samples[i - channels] + samples[i - 2 * channels]) ** 2
                   for i in range(2 * channels, len(samples))) / len(samples)

    ratio = high_frequency_energy(warm) / high_frequency_energy(raw)
    assert ratio < 0.5, f"warm mode does not sufficiently reduce high frequencies ({ratio:.3f})"

    # A seamless boundary should not be an outlier compared to adjacent sample steps.
    differences = sorted(abs(warm[i] - warm[i - channels]) for i in range(channels, len(warm)))
    boundary = max(abs(warm[i] - warm[len(warm) - channels + i]) for i in range(channels))
    p999 = differences[int(len(differences) * 0.999)]
    assert boundary <= max(p999, 128), f"loop seam is too abrupt: {boundary} vs {p999}"
    print(f"Ambient audio tests passed (high-frequency energy ratio {ratio:.3f}; seam {boundary}/{p999})")
