# Aural.jl

Aural.jl is an offline Julia package for symbolic music, audio synthesis, WAV
I/O, and music-information-retrieval (MIR) analysis.

The data flow is:

```text
symbolic music -> synthesis/rendering -> AudioBuffer -> analysis and WAV I/O
```

Aural operates on in-memory audio and does not provide audio-device I/O,
realtime streaming, MIDI, codecs beyond WAV, or machine-learning integrations.

## Features

- `AudioBuffer` stores sampled audio as `channels × frames`.
- Audio operations include channel conversion, gain, peak normalization,
  trimming, and additive mixing.
- `Pitch`, `Note`, `Tempo`, `NoteEvent`, and `Score` provide a symbolic music
  model.
- `oscillator` provides sine, cosine, saw, square, and triangle waveforms;
  `tone` is its sine alias.
- `noise`, linear/exponential ramps, `ADSR`, `envelope`, `apply_envelope`, and
  `note` support offline synthesis.
- `render` turns a constant-tempo score into audio with a sine voice.
- `read_audio` and `write_audio` adapt WAV files through WAV.jl.
- `stft` and `spectrogram` provide one-sided FFT analysis.
- RMS, spectral centroid, spectral flux, bandwidth, rolloff, flatness,
  zero-crossing rate, crest factor, DC offset, dB, chroma, MFCC, and
  autocorrelation pitch features are available for offline analysis.
- `detect_onsets` supports global/local thresholds, latency compensation, and
  optional strengths; `evaluate_events`, `timing_error`, and `tempo_estimate`
  provide point-event evaluation and tempo/beat estimation.

Aural.jl is version `0.1.0` and supports Julia `1.10` and later. The
development and verification environment uses Julia 1.12.7.

## Installation

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

## Generate and write audio

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

## Render a score

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

## Analyze audio

```julia
using Aural

audio = mono(read_audio("tone.wav"))
settings = AnalysisConfig(window_size=2_048, hop_size=512, nfft=2_048, pad=false)
spec = spectrogram(audio, settings)

centroid = spectral_centroid(spec)
flux = spectral_flux(spec)
pitch_classes = chroma(spec)
cepstra = mfcc(spec; nfilters=40, ncoeffs=13)
energy = rms(audio, settings)
pitch = pitch_track(audio, settings)

values(cepstra)  # coefficients × analysis frames
times(cepstra)   # seconds, shared with the spectrogram
```

Analysis defaults to channel 1. Call `mono` when an explicit downmix is
preferred. Feature matrices use rows × analysis frames; feature tracks use one
value per analysis frame. See [`docs/analysis.md`](docs/analysis.md) for frame
placement, padding, numerical conventions, and feature definitions.

## Detect and evaluate onsets

```julia
using Aural

audio = read_audio("recording.wav")
estimated = detect_onsets(audio; window_size=1_024, hop_size=256)
reference = EventAnnotations([0.42, 1.07, 1.84]; kind=:onset)

score = evaluate_events(reference, estimated; tolerance=0.05)
(score.precision, score.recall, score.f1)
timing_error(reference, estimated; tolerance=0.05)
```

The detector uses spectral flux and frame-center timestamps. It supports local
thresholds and explicit latency compensation, and may miss an attack in the
first frame. Event matching is inclusive, one-to-one, and maximizes the number
of matches; it is not a beat-continuity or note-transcription metric. See
[`docs/events-and-evaluation.md`](docs/events-and-evaluation.md).

## Public API

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

`AnalysisConfig`, `validate_audio`, `FrameGrid`, `frame`, `eachframe`,
`frame_times`, `STFT`, `Spectrogram`, `FeatureTrack`, `FeatureMatrix`, `stft`,
`spectrogram`, `coefficients`, `power`, `frequencies`, `times`, `values`,
`metadata`, `config`, `source_frames`, `confidence`, `rms`, spectral scalar
features, `chroma`, `mfcc`, and `pitch_track`.

### Events

`EventAnnotations`, `EventScore`, `evaluate_events`, `timing_error`,
`detect_onsets`, `TempoEstimate`, `tempo_estimate`, and `beat_positions`.

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
- [`docs/events-and-evaluation.md`](docs/events-and-evaluation.md) — onset,
  tempo, beat annotations, and point-event metrics.
- [`docs/development.md`](docs/development.md) — repository layout, testing, and
  contribution workflow.
- [`CHANGELOG.md`](CHANGELOG.md) — released and unreleased public changes.

Planned work is maintained in [`TODOS.md`](TODOS.md). It includes interval
annotations, richer synthesis, resampling, inverse STFT, real-music benchmarks,
CI, coverage, and performance work that is not part of the supported API.

To run the analysis summary example, use
[`examples/analysis_summary.jl`](examples/analysis_summary.jl) with no argument
for a generated tone or with a WAV path as its first argument.

## Testing

Run the package test suite with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The suite covers the audio and music foundations, direct DFT and MFCC
references, feature edge cases, exhaustive event-matching cases, and external
PCM WAV fixtures. It does not measure real-recording accuracy or provide
complete branch coverage.

If Julia's package usage log is unavailable in a restricted environment, run
the test file directly while reusing existing compiled modules:

```sh
julia --startup-file=no --compiled-modules=existing --project=. -e \
  'using Aural; include("test/runtests.jl")'
```

## Limitations

- Audio is offline and in-memory; there is no device or realtime layer.
- WAV reading defaults to `Float32`; writing converts samples to `Float32`.
- Source bit-depth and metadata are not preserved by the WAV adapter.
- `render` uses a sine voice; the oscillator and envelope helpers are available
  for explicit composition but are not wired into score rendering.
- `spectrogram` stores squared FFT magnitudes, not calibrated PSD estimates.
- Chroma and MFCC use documented fixed conventions and are not drop-in
  replacements for every external MIR implementation.
- Onset detection uses point-event F1 and has no streaming state, sub-frame
  backtracking, beat-continuity scoring, or dataset evaluation.

For planned work and explicit non-goals, see [`TODOS.md`](TODOS.md).
