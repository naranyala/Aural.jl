# Aural.jl

Aural.jl is a small, offline-first Julia toolkit for connecting symbolic music,
audio synthesis, sampled audio, WAV files, and baseline music-information-
retrieval (MIR) features.

The package is intentionally compact. Its current data flow is:

```text
symbolic music -> synthesis/rendering -> AudioBuffer -> analysis and WAV I/O
```

It does not require an audio device and does not currently provide realtime
streaming, MIDI, codec support beyond WAV, or machine-learning integrations.

## What is implemented

- `AudioBuffer` stores sampled audio as `channels × frames`.
- Audio operations include channel conversion, gain, peak normalization,
  trimming, and additive mixing.
- `Pitch`, `Note`, `Tempo`, `NoteEvent`, and `Score` provide a small symbolic
  music model.
- `oscillator` provides sine, cosine, saw, square, and triangle waveforms;
  `tone` is its sine alias.
- `noise`, linear/exponential ramps, `ADSR`, `envelope`, `apply_envelope`, and
  `note` support small offline synthesis experiments.
- `render` turns a constant-tempo score into audio with its current sine voice.
- `read_audio` and `write_audio` adapt WAV files through WAV.jl.
- `stft` and `spectrogram` provide one-sided FFT analysis.
- Baseline RMS, spectral centroid, spectral flux, chroma, and MFCC features are
  available for offline experiments.
- `detect_onsets` and `evaluate_events` provide point-event onset baselines.

The package is version `0.1.0` and targets Julia `1.10` or newer. The current
development and verification environment uses Julia 1.12.7.

## Installation and first run

Clone the repository, enter its directory, and instantiate the project:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Then load the package:

```julia
using Aural
```

Runtime dependencies are declared in [`Project.toml`](Project.toml): WAV.jl
for file I/O, FFTW.jl for FFTs, and DSP.jl for the default Hann window.

## Quick start: generate and write audio

```julia
using Aural

tone440 = tone(440, 2; samplerate=48_000, amplitude=0.2)
mixdown = normalize(gain(tone440, 0.5))
write_audio("tone.wav", mixdown)
```

`AudioBuffer` uses channels × frames throughout. `duration` is measured in
seconds, while `samplerate` is measured in samples per second:

```julia
nchannels(tone440)   # 1
nframes(tone440)     # 96000
duration(tone440)    # 2.0
samples(tone440)     # the underlying 1 × 96000 array
```

See [`docs/audio.md`](docs/audio.md) for ownership, channel, timing, and
mixing details.

## Quick start: render a score

```julia
using Aural

score = Score([
    NoteEvent(Note(:C, 4), 0, 1),
    NoteEvent(Note(:E, 4), 1, 1),
    NoteEvent(Note(:G, 4), 2, 2),
]; tempo=Tempo(120))

audio = render(score; samplerate=48_000, amplitude=0.2)
write_audio("melody.wav", audio)
```

Beats remain beats inside the score. `render` converts them to seconds at the
score's constant tempo. Overlapping events are mixed additively, and the output
ends at the latest event end. See
[`docs/music-and-synthesis.md`](docs/music-and-synthesis.md).

## Quick start: analyze a recording

```julia
using Aural

audio = mono(read_audio("tone.wav"))
spec = spectrogram(audio; window_size=2_048, hop_size=512, pad=false)

centroid = spectral_centroid(spec)
flux = spectral_flux(spec)
pitch_classes = chroma(spec)
cepstra = mfcc(spec; nfilters=40, ncoeffs=13)
energy = rms(audio; window_size=2_048, hop_size=512, pad=false)

values(cepstra)  # coefficients × analysis frames
times(cepstra)   # seconds, shared with the spectrogram
```

Analysis defaults to channel 1. Call `mono` when an explicit downmix is
preferred. Feature matrices use rows × analysis frames; feature tracks use one
value per analysis frame. See [`docs/analysis.md`](docs/analysis.md) for frame
placement, padding, numerical conventions, and feature definitions.

## Quick start: detect and score onsets

```julia
using Aural

audio = read_audio("recording.wav")
estimated = detect_onsets(audio; window_size=1_024, hop_size=256)
reference = EventAnnotations([0.42, 1.07, 1.84]; kind=:onset)

score = evaluate_events(reference, estimated; tolerance=0.05)
(score.precision, score.recall, score.f1)
```

The detector is an offline spectral-flux baseline. It uses frame-center times,
does not backtrack peaks, and may miss an attack in the first frame. Event
matching is inclusive, one-to-one, and maximizes the number of matches; it is
not a beat-continuity or note-transcription metric. See
[`docs/events-and-evaluation.md`](docs/events-and-evaluation.md).

## Public API at a glance

### Audio

`AudioBuffer`, `samples`, `samplerate`, `nchannels`, `nframes`, `duration`,
`channel`, `mono`, `stereo`, `join_channels`, `silence`, `gain`, `normalize`,
`trim`, and `mix`.

### Music and synthesis

`Pitch`, `Note`, `Tempo`, `NoteEvent`, `Score`, `midi`, `frequency`,
`beats_to_seconds`, `duration_beats`, `oscillator`, `tone`, `noise`,
`linear_ramp`, `exponential_ramp`, `ADSR`, `envelope`, `apply_envelope`,
`note`, and `render`.

### WAV I/O

`read_audio` and `write_audio`.

### Analysis

`FrameGrid`, `frame`, `frame_times`, `STFT`, `Spectrogram`, `FeatureTrack`,
`FeatureMatrix`, `stft`, `spectrogram`, `coefficients`, `power`, `frequencies`,
`times`, `values`, `rms`, `spectral_centroid`, `spectral_flux`, `chroma`, and
`mfcc`.

### Events

`EventAnnotations`, `EventScore`, `evaluate_events`, and `detect_onsets`.

All of these names are explicitly exported from [`src/Aural.jl`](src/Aural.jl).

## Documentation map

- [`docs/README.md`](docs/README.md) — documentation index and package map.
- [`docs/getting-started.md`](docs/getting-started.md) — installation,
  conventions, and a complete first workflow.
- [`docs/audio.md`](docs/audio.md) — `AudioBuffer` and audio operations.
- [`docs/music-and-synthesis.md`](docs/music-and-synthesis.md) — symbolic music,
  timing, synthesis helpers, and score rendering.
- [`docs/analysis.md`](docs/analysis.md) — framing, STFT, spectrograms, and MIR
  features.
- [`docs/events-and-evaluation.md`](docs/events-and-evaluation.md) — onset
  detection, annotations, and point-event metrics.
- [`docs/development.md`](docs/development.md) — repository layout, testing, and
  contribution workflow.

The forward-looking roadmap is maintained in [`TODOS.md`](TODOS.md). It
includes interval annotations, richer synthesis, resampling, inverse STFT,
real-music benchmarks, CI, coverage, and performance work that are not part of
the current API.

## Testing

Run the package test suite with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The suite covers the audio and music foundations, direct DFT and MFCC
references, feature edge cases, exhaustive small event-matching cases, and
external PCM WAV fixtures. It is not a claim of real-recording accuracy or
complete branch coverage.

If Julia's package usage log is unavailable in a restricted environment, run
the test file directly while reusing existing compiled modules:

```sh
julia --startup-file=no --compiled-modules=existing --project=. -e \
  'using Aural; include("test/runtests.jl")'
```

## Current limitations

- Audio is offline and in-memory; there is no device or realtime layer.
- WAV reading defaults to `Float32`; writing converts samples to `Float32`.
- Source bit-depth and metadata are not preserved by the WAV adapter.
- `render` currently uses a sine voice; the richer oscillator and envelope
  helpers are available for explicit offline composition but are not yet wired
  into score rendering.
- `spectrogram` stores squared FFT magnitudes, not calibrated PSD estimates.
- Chroma and MFCC are deliberately simple baselines with documented fixed
  conventions, not drop-in parity with every external MIR implementation.
- Onset detection uses point-event F1 and has no adaptive threshold,
  backtracking, beat tracking, or dataset evaluation.

For planned work and explicit non-goals, see [`TODOS.md`](TODOS.md).
