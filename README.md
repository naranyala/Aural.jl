# Aural.jl

A small personal Julia toolkit for audio and music processing.

The starter focuses on offline audio and baseline music information retrieval:

- `AudioBuffer` for multichannel sampled audio
- Basic gain, mixing, trimming, normalization, and channel operations
- Pitches, notes, tempos, scores, and note events
- Sine-tone generation
- Simple score-to-audio rendering

WAV I/O and spectral analysis use `WAV`, `FFTW`, and `DSP`. MIDI and realtime
integrations remain planned in [`TODOS.md`](TODOS.md).

## Example

```julia
using Aural

score = Score([
    NoteEvent(Note(:C, 4), 0, 1),
    NoteEvent(Note(:E, 4), 1, 1),
    NoteEvent(Note(:G, 4), 2, 2),
]; tempo=Tempo(120))

audio = render(score; samplerate=48_000)
audio = normalize(gain(audio, 0.5))

duration(audio)
```

## MIR workflow

Start Julia with `julia --project=.` in this folder and run `using Pkg;
Pkg.instantiate()` once to install dependencies.

```julia
using Aural

write_audio("tone.wav", tone(440, 1; amplitude=0.2))
audio = mono(read_audio("tone.wav"))
spec = spectrogram(audio; window_size=2048, hop_size=512, pad=false)
centroid = spectral_centroid(spec)
flux = spectral_flux(spec)
pitch_classes = chroma(spec)
cepstra = mfcc(spec; nfilters=40, ncoeffs=13)
energy = rms(audio; window_size=2048, hop_size=512, pad=false)

values(cepstra) # coefficients × analysis frames
times(cepstra)  # seconds
```

## Onset detection and evaluation

```julia
using Aural

clicks = zeros(Float32, 8000)
clicks[[2001, 4001, 6001]] .= 1
audio = AudioBuffer(clicks, 8000)
reference = EventAnnotations([0.25, 0.5, 0.75]; kind=:onset)
estimated = detect_onsets(audio; window_size=128, hop_size=32)
score = evaluate_events(reference, estimated; tolerance=0.016)
score.f1 # 1.0 for this synthetic example
```

`detect_onsets` uses positive spectral flux and a threshold relative to its
global maximum. It selects local peaks, retaining the strongest within
`min_interval` seconds. A plateau uses its first bin; equal nearby peaks use
the earliest timestamp. Default threshold is 0.2 and minimum spacing is 50 ms.
It returns frame-center times without backtracking, may miss first-frame
attacks, and defaults to complete windows. This is an offline baseline.

`EventAnnotations` supports onset and beat point events in seconds.
`evaluate_events` returns TP/FP/FN counts, precision, recall, and F1 using
one-to-one matches within an inclusive tolerance (default 50 ms). Duplicates
cannot reuse a match; metrics with empty denominators are zero. Matching
maximizes the number of matches, not minimum timing error. Beat continuity,
note/chord intervals, dataset loaders, and real-music benchmarks remain planned.

### Analysis conventions

- Audio uses channels × samples; features use bins/features × analysis frames.
- Analysis selects channel 1 by default. Call `mono` for explicit downmixing.
- `FrameGrid` starts at sample 1. `pad=true` includes every hop starting inside
  the signal and zero-pads the tail; `pad=false` keeps complete windows only.
  Empty audio yields no frames. Timestamps mark each window's sample midpoint;
  padded windows can have timestamps beyond the recording duration.
- STFT uses a symmetric Hann window by default, with optional right-zero-padding
  to `nfft`. Coefficients are unnormalized one-sided real FFTs. Spectrogram
  values are squared magnitudes, **not** calibrated power spectral density.
- RMS uses unwindowed samples, including tail zeros. Centroid is power-weighted
  in hertz (zero for silence). Flux is the L2 norm of positive magnitude
  increases, with zero at the first frame.
- Chroma sums power into nearest 12-TET pitch classes C through B and applies
  per-frame L1 normalization. This is a simple FFT-bin baseline.
- MFCC uses HTK mel spacing, unit-peak triangular filters, natural log energies
  floored at `1e-10`, and orthonormal DCT-II including C0. No pre-emphasis,
  liftering, deltas, or cepstral mean normalization is applied.
- WAV reading defaults to Float32; writing converts samples to Float32 and uses
  WAV.jl's encoding defaults. Arbitrary source bit-depth/metadata preservation
  is not implemented.

Dependencies are currently loaded with Aural. `Project.toml` declares compatible
version ranges; the local ignored `Manifest.toml` records resolved versions.

## Development

The suite currently passes 757 assertions on Julia 1.12.7, including independent
DFT/MFCC references, exhaustive small event-matching cases, external PCM WAV
fixtures, and boundary regressions. This is not a claim of complete coverage:
real-recording accuracy, cross-platform CI, and performance testing remain open
in `TODOS.md`.

Timing clarification: `duration_beats(event)` is its duration, while
`duration_beats(score)` is the latest event end. `trim` rounds nonempty bounds
outward to sample cells and returns no samples for equal bounds.

Run the test suite with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

If cold precompilation stalls in this environment, the verified fallback is:

```sh
JULIA_PKG_PRECOMPILE_AUTO=0 julia --startup-file=no --project=. -e 'using Pkg; Pkg.test(; julia_args=["--compiled-modules=existing"])'
```
