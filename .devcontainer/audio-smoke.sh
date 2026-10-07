#!/bin/bash
# Smoke test for the optional audio tooling (build args AUDIO / AUDIO_MUSIC /
# SPEECH).
# Renders a few sounds with every installed tool and checks the results are
# real, non-silent audio. Parts whose gate is off are reported as SKIP.
# Usage: bash ~/.devcontainer/audio-smoke.sh [output_dir]
set -u

OUT="${1:-$(mktemp -d /tmp/audio-smoke.XXXXXX)}"
mkdir -p "$OUT"
FAILED=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
skip() { echo "SKIP  $1"; }

# Exits non-zero when a file is missing or (near) silent.
check_audio() {
  python3 - "$1" <<'EOF'
import sys, subprocess, numpy as np
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", sys.argv[1], "-f", "f32le", "-ac", "1", "-"],
                     capture_output=True, check=True).stdout
x = np.frombuffer(raw, dtype=np.float32)
sys.exit(0 if x.size > 0 and np.abs(x).max() > 0.01 else 1)
EOF
}

# --- AUDIO: SFX stack ------------------------------------------------------
if python3 -c "import pedalboard" 2>/dev/null; then
  if python3 -c "import numpy, scipy, soundfile, pedalboard, pyloudnorm, librosa, pyo" >/dev/null 2>&1; then
    pass "python imports (numpy scipy soundfile pedalboard pyloudnorm librosa pyo)"
  else
    fail "python imports (numpy scipy soundfile pedalboard pyloudnorm librosa pyo)"
  fi

  if python3 - "$OUT/laser.wav" <<'EOF' && check_audio "$OUT/laser.wav"
import sys, numpy as np, soundfile as sf, pyloudnorm as pyln
from pedalboard import Pedalboard, LowpassFilter, Reverb
sr, dur = 44100, 0.4
t = np.arange(int(sr * dur)) / sr
freq = np.geomspace(1800, 200, t.size)
x = np.sign(np.sin(2 * np.pi * np.cumsum(freq) / sr)) * np.exp(-t * 8)
x = Pedalboard([LowpassFilter(4000), Reverb(room_size=0.2)])(x.astype(np.float32), sr)
x = x / np.abs(x).max() * 10 ** (-1 / 20)
pyln.Meter(sr, block_size=0.1).integrated_loudness(x)
sf.write(sys.argv[1], x, sr, subtype="PCM_16")
EOF
  then pass "numpy + pedalboard SFX -> WAV"; else fail "numpy + pedalboard SFX -> WAV"; fi

  if python3 - "$OUT/pyo.wav" >/dev/null 2>&1 <<'EOF' && check_audio "$OUT/pyo.wav"
import sys
from pyo import Server, Sine, Adsr
s = Server(audio="offline", nchnls=1).boot()
s.recordOptions(dur=0.5, filename=sys.argv[1], fileformat=0, sampletype=0)
env = Adsr(attack=0.01, decay=0.1, sustain=0.5, release=0.2, dur=0.5, mul=0.5).play()
osc = Sine(freq=440, mul=env).out()  # pyo objects must stay referenced or they go silent
s.start()
EOF
  then pass "pyo offline render -> WAV"; else fail "pyo offline render -> WAV"; fi

  if NODE_PATH="$(npm root -g)" node - "$OUT/jsfxr.wav" <<'EOF' && check_audio "$OUT/jsfxr.wav"
const fs = require("fs");
const { sfxr } = require("jsfxr");
const params = sfxr.generate("pickupCoin");
params.sample_size = 16;
fs.writeFileSync(process.argv[2], Buffer.from(sfxr.toWave(params).wav));
EOF
  then pass "jsfxr preset -> WAV"; else fail "jsfxr preset -> WAV"; fi

  # Same recipe as documented in AGENTS.md. ffmpeg's showspectrumpic is not
  # used: it ties the FFT window to image width, so short SFX smear into noise.
  if python3 - "$OUT/laser.wav" "$OUT/laser.png" <<'EOF' && [ -s "$OUT/laser.png" ]
import sys, numpy as np, soundfile as sf
from scipy.signal import stft
from PIL import Image
x, sr = sf.read(sys.argv[1], always_2d=True)
f, t, Z = stft(x.mean(axis=1), sr, nperseg=1024, noverlap=1024 - 128)
db = 20 * np.log10(np.abs(Z) + 1e-9)
db = np.clip((db - db.max() + 80) / 80, 0, 1)
Image.fromarray((db[::-1] * 255).astype(np.uint8)).resize((800, 400)).save(sys.argv[2])
EOF
  then pass "scipy + Pillow spectrogram -> PNG"; else fail "scipy + Pillow spectrogram -> PNG"; fi
else
  skip "SFX stack (built with AUDIO=off)"
fi

# --- AUDIO_MUSIC: MIDI + FluidSynth ----------------------------------------
if command -v fluidsynth >/dev/null; then
  if python3 - "$OUT/song.mid" <<'EOF'
import sys, mido
mid = mido.MidiFile()
track = mido.MidiTrack()
mid.tracks.append(track)
track.append(mido.Message("program_change", program=0))
for note in (60, 64, 67, 72):
    track.append(mido.Message("note_on", note=note, velocity=100, time=0))
    track.append(mido.Message("note_off", note=note, velocity=0, time=240))
mid.save(sys.argv[1])
EOF
  then pass "mido MIDI file"; else fail "mido MIDI file"; fi

  for sf2 in FluidR3_GM GeneralUser-GS; do
    font="/usr/share/sounds/sf2/$sf2.sf2"
    if [ -f "$font" ] \
      && fluidsynth -ni -q -F "$OUT/song-$sf2.wav" -r 44100 "$font" "$OUT/song.mid" >/dev/null 2>&1 \
      && ffmpeg -v error -y -i "$OUT/song-$sf2.wav" -c:a libvorbis -q:a 5 "$OUT/song-$sf2.ogg" \
      && check_audio "$OUT/song-$sf2.ogg"; then
      pass "fluidsynth ($sf2) -> OGG"
    else
      fail "fluidsynth ($sf2) -> OGG"
    fi
  done
else
  skip "music stack (built with AUDIO_MUSIC=off)"
fi

# --- SPEECH: espeak-ng + Kokoro ---------------------------------------------
if command -v espeak-ng >/dev/null; then
  if espeak-ng -v en+m3 -w "$OUT/espeak.wav" "Wave seven incoming" && check_audio "$OUT/espeak.wav"; then
    pass "espeak-ng -> WAV"
  else
    fail "espeak-ng -> WAV"
  fi

  if python3 - "$OUT/kokoro.wav" >/dev/null 2>&1 <<'EOF' && check_audio "$OUT/kokoro.wav"
import sys, soundfile as sf
from kokoro_onnx import Kokoro
k = Kokoro("/opt/kokoro/kokoro-v1.0.onnx", "/opt/kokoro/voices-v1.0.bin")
samples, sr = k.create("Wave seven incoming. Hold the line!", voice="am_michael", speed=1.0, lang="en-us")
sf.write(sys.argv[1], samples, sr)
EOF
  then pass "Kokoro -> WAV"; else fail "Kokoro -> WAV"; fi

  # Singing: espeak-ng has no exact pitch control, but SSML range="0%" makes it
  # monotone, so each syllable can be measured and shifted onto its note.
  if python3 -c "import librosa" 2>/dev/null; then
    if python3 - "$OUT/sing.wav" >/dev/null 2>&1 <<'EOF' && check_audio "$OUT/sing.wav"
import io, subprocess, sys, numpy as np, librosa, soundfile as sf
SR, BPM = 22050, 100

def syllable(text, midi, beats, voice="en+f3"):
    ssml = f'<speak><prosody range="0%">{text}</prosody></speak>'
    wav = subprocess.run(["espeak-ng", "-m", "-v", voice, "--stdout", ssml], capture_output=True, check=True).stdout
    y, sr = sf.read(io.BytesIO(wav))
    y = librosa.resample(y, orig_sr=sr, target_sr=SR)
    f0, voiced, _ = librosa.pyin(y, fmin=60, fmax=600, sr=SR)
    y = librosa.effects.pitch_shift(y, sr=SR, n_steps=12 * np.log2(librosa.midi_to_hz(midi) / np.nanmedian(f0[voiced])))
    return librosa.effects.time_stretch(y, rate=len(y) / (SR * beats * 60 / BPM))

notes = [("twin", 60, 1), ("kle", 60, 1), ("twin", 67, 1), ("kle", 67, 1), ("lit", 69, 1), ("tle", 69, 1), ("star", 67, 2)]
y = np.concatenate([syllable(*n) for n in notes])
f0, voiced, _ = librosa.pyin(y[int(SR * 2.4):int(SR * 3.0)], fmin=100, fmax=800, sr=SR)  # "lit", A4
assert abs(np.nanmedian(f0[voiced]) - 440) < 10
sf.write(sys.argv[1], y / np.abs(y).max() * 0.9, SR, subtype="PCM_16")
EOF
    then pass "espeak-ng + librosa singing -> WAV"; else fail "espeak-ng + librosa singing -> WAV"; fi
  else
    skip "espeak-ng singing (needs librosa, built with AUDIO=off)"
  fi
else
  skip "speech stack (built with SPEECH=off)"
fi

echo "Outputs in $OUT"
exit $FAILED
