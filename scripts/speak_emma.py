#!/usr/bin/env python3
"""Synthesize speech for the FastPitch voices and write WAV files.

Speaker ids match FastPitchSpeaker in Sources/OtosakuTTS-iOS/OtosakuTTS_iOS.swift.
The script phonemizes plain English with the bundled CMU dictionary, runs
FastPitch.mlmodelc and HiFiGan.mlmodelc, and saves 16-bit mono PCM at
44.1 kHz, matching the example app.

    python3 scripts/speak_emma.py --all
    python3 scripts/speak_emma.py --speaker claire
"""

from __future__ import annotations

import argparse
import json
import re
import wave
import zipfile
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44_100
MAX_TOKENS = 240

# name, FastPitch speaker id
SPEAKERS: list[tuple[str, int]] = [
    ("emma", 92),
    ("james", 6097),
    ("daniel", 9017),
    ("michael", 6670),
    ("ryan", 6671),
    ("sophia", 8051),
    ("claire", 9136),
    ("olivia", 11614),
    ("celine", 11697),
    ("grace", 12787),
]
SPEAKER_IDS = {name: speaker_id for name, speaker_id in SPEAKERS}

# Same token pattern as Tokenizer.encodeNormalized.
TOKEN_RE = re.compile(
    r"[A-Za-z]+(?:'[A-Za-z]+)?"
    r"|[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?(?:st|nd|rd|th)?"
    r"|[0-9]+(?:\.[0-9]+)?(?:st|nd|rd|th)?"
    r"|[^A-Za-z0-9\s]"
    r"|\s+"
)

# One pangram, then a different line so every voice lasts at least ten seconds.
# The pangram contains every letter of the alphabet.
DEFAULT_TEXT = (
    "The quick brown fox jumps over the lazy dog. "
    "This second line gives the voice a little more time, so you can hear its tone, "
    "its pace, and the way it carries a full thought from start to finish. "
    "Stay with it until the line comes to a quiet end."
)

ROOT = Path(__file__).resolve().parents[1]


def load_tokens(path: Path) -> dict[str, int]:
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line]
    return {token: index for index, token in enumerate(lines)}


def phonemes_for(word: str, dictionary: dict) -> list[str]:
    cleaned = word.lower().strip("'")
    if not cleaned:
        return []
    pronunciations = dictionary.get(cleaned)
    if pronunciations:
        return list(pronunciations[0])
    return guess_phones(cleaned)


def guess_phones(word: str) -> list[str]:
    """Small fallback for words missing from the dictionary."""
    clusters = [
        ("tion", ["SH", "AH0", "N"]),
        ("sion", ["ZH", "AH0", "N"]),
        ("ch", ["CH"]),
        ("sh", ["SH"]),
        ("th", ["TH"]),
        ("ph", ["F"]),
        ("ng", ["NG"]),
        ("qu", ["K", "W"]),
        ("ck", ["K"]),
    ]
    singles = {
        "b": ["B"], "c": ["K"], "d": ["D"], "f": ["F"], "g": ["G"],
        "h": ["HH"], "j": ["JH"], "k": ["K"], "l": ["L"], "m": ["M"],
        "n": ["N"], "p": ["P"], "q": ["K"], "r": ["R"], "s": ["S"],
        "t": ["T"], "v": ["V"], "w": ["W"], "x": ["K", "S"], "z": ["Z"],
        "a": ["AE1"], "e": ["EH1"], "i": ["IH1"], "o": ["OW1"],
        "u": ["AH1"], "y": ["IY1"],
    }
    phones: list[str] = []
    index = 0
    while index < len(word):
        remaining = word[index:]
        matched = False
        for cluster, cluster_phones in clusters:
            if remaining.startswith(cluster):
                phones.extend(cluster_phones)
                index += len(cluster)
                matched = True
                break
        if matched:
            continue
        phones.extend(singles.get(word[index], []))
        index += 1
    return phones


def encode(text: str, token_to_id: dict[str, int], dictionary: dict) -> list[int]:
    space_id = token_to_id[" "]
    oov_id = token_to_id.get("<oov>")
    ids: list[int] = []

    def append_symbol(symbol: str) -> None:
        if symbol in token_to_id:
            ids.append(token_to_id[symbol])
        elif oov_id is not None:
            ids.append(oov_id)

    for match in TOKEN_RE.finditer(text):
        token = match.group(0)
        if token.strip() == "":
            append_symbol(" ")
            continue
        if token in token_to_id and not token[0].isalnum():
            append_symbol(token)
            continue
        if token[0].isdigit():
            raise ValueError(f"Spell numbers out in words before synthesizing: {token!r}")
        if token[0].isalpha():
            for phone in phonemes_for(token, dictionary):
                append_symbol(phone)

    while ids and ids[-1] == space_id:
        ids.pop()
    return ids


def resolve_models(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit

    direct_candidates = [
        ROOT / "TTSModels",
        ROOT / ".model-cache" / "TTSModels",
    ]
    for candidate in direct_candidates:
        if (candidate / "FastPitch.mlmodelc").is_dir():
            return candidate

    archive = ROOT / "TTSModels.zip"
    if not archive.is_file():
        raise FileNotFoundError(
            "Could not find FastPitch.mlmodelc. Pass --models, or keep TTSModels.zip "
            "at the repository root."
        )

    cache = ROOT / ".model-cache"
    cache.mkdir(parents=True, exist_ok=True)
    marker = cache / "TTSModels" / "FastPitch.mlmodelc"
    if not marker.is_dir():
        with zipfile.ZipFile(archive) as zipped:
            zipped.extractall(cache)
    return cache / "TTSModels"


def write_wav(path: Path, samples: np.ndarray) -> None:
    audio = np.asarray(samples, dtype=np.float32).reshape(-1)
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak > 1.0:
        audio = audio / peak
    pcm = np.clip(audio, -1.0, 1.0)
    pcm_i16 = (pcm * 32767.0).astype(np.int16)

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm_i16.tobytes())


class VoiceEngine:
    """Loaded FastPitch and HiFiGAN models, reused across speakers."""

    def __init__(self, models_dir: Path, text: str) -> None:
        from coremltools.models import CompiledMLModel

        token_to_id = load_tokens(models_dir / "tokens.txt")
        with (models_dir / "cmudict.json").open(encoding="utf-8") as handle:
            dictionary = json.load(handle)

        token_ids = encode(text, token_to_id, dictionary)
        if len(token_ids) < 2 or len(token_ids) > MAX_TOKENS:
            raise ValueError(
                f"The model accepts 2 to {MAX_TOKENS} tokens; this line produced {len(token_ids)}."
            )

        self.phones = np.array([token_ids], dtype=np.int32)
        self.fastpitch = CompiledMLModel(str(models_dir / "FastPitch.mlmodelc"))
        self.hifigan = CompiledMLModel(str(models_dir / "HiFiGan.mlmodelc"))

    def speak(self, speaker_id: int) -> np.ndarray:
        speaker = np.array([speaker_id], dtype=np.int32)
        spec = np.asarray(
            self.fastpitch.predict({"x": self.phones, "speaker": speaker})["spec"],
            dtype=np.float32,
        )
        if spec.ndim == 2:
            spec = spec[np.newaxis, ...]
        if spec.shape[1] != 80 and spec.shape[-1] == 80:
            spec = np.transpose(spec, (0, 2, 1))
        return np.asarray(self.hifigan.predict({"x": spec})["waveform"], dtype=np.float32)


def render(engine: VoiceEngine, name: str, speaker_id: int, path: Path) -> None:
    samples = engine.speak(speaker_id)
    write_wav(path, samples)
    duration = samples.size / SAMPLE_RATE
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    print(f"Wrote {path} ({duration:.2f}s, peak {peak:.3f}, {name} {speaker_id})")


def main() -> None:
    parser = argparse.ArgumentParser(description="Write WAV samples of the FastPitch voices.")
    parser.add_argument("--text", default=DEFAULT_TEXT, help="Plain English for the voice to say.")
    parser.add_argument(
        "--speaker",
        default="emma",
        choices=sorted(SPEAKER_IDS),
        help="One voice to render. Ignored when --all is set.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Write samples/<name>.wav for every voice, using the same sentence.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Output WAV for a single voice, or the directory used by --all.",
    )
    parser.add_argument(
        "--models",
        type=Path,
        default=None,
        help="Directory containing FastPitch.mlmodelc, HiFiGan.mlmodelc, tokens.txt, and cmudict.json.",
    )
    args = parser.parse_args()

    models_dir = resolve_models(args.models)
    engine = VoiceEngine(models_dir, args.text)

    if args.all:
        out_dir = args.out or (ROOT / "samples")
        for name, speaker_id in SPEAKERS:
            render(engine, name, speaker_id, out_dir / f"{name}.wav")
        return

    speaker_id = SPEAKER_IDS[args.speaker]
    out_path = args.out or (ROOT / "samples" / f"{args.speaker}.wav")
    render(engine, args.speaker, speaker_id, out_path)


if __name__ == "__main__":
    main()
