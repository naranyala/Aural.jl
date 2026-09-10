# Getting started

## Requirements

Aural.jl is a Julia package targeting Julia 1.10 or newer. The repository's
current verification environment is Julia 1.12.7. Runtime dependencies are
WAV.jl, FFTW.jl, and DSP.jl; they are declared in `Project.toml`.

From the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Start a project-aware Julia session:

```sh
julia --project=.
```

Then:

```julia
using Aural
```

## Units and layouts

Keep these conventions in mind when moving between APIs:

| Concept | Representation |
| --- | --- |
| Audio samples | `channels × frames` matrix |
| Sample rate | samples per second (`Int`) |
| Audio duration | seconds (`Float64`) |
| Frequency | hertz |
| Symbolic position/duration | beats |
| Tempo | beats per minute |
| Event annotations | seconds |
| Feature tracks | one value per analysis frame |
| Feature matrices | rows/features × analysis frames |

The package does not attach physical units to numeric values. The caller is
responsible for passing values in the units shown above.

## A complete small workflow

The following example creates audio, writes it to WAV, reads it back, computes
features, and detects point events:

```julia
using Aural

score = Score([
    NoteEvent(Note(:C, 4), 0, 1),
    NoteEvent(Note(:E, 4), 1, 1),
    NoteEvent(Note(:G, 4), 2, 2),
]; tempo=Tempo(120))

rendered = render(score; samplerate=16_000)
write_audio("example.wav", rendered)

audio = read_audio("example.wav")
spec = spectrogram(audio; window_size=512, hop_size=128, pad=false)
centroid = spectral_centroid(spec)
flux = spectral_flux(spec)
cepstra = mfcc(spec; nfilters=20, ncoeffs=8)
onsets = detect_onsets(audio; window_size=512, hop_size=128)
```

Inspect data through the package accessors instead of relying on internal
fields:

```julia
samplerate(audio)
duration(audio)
frequencies(spec)
times(spec)
values(centroid)
values(cepstra)
times(onsets)
```

## A note about ownership

`AudioBuffer(data, rate)` stores a matrix or vector in the buffer; it does not
implicitly copy the input. `samples(audio)` returns that underlying array, so
mutating it mutates the buffer. Use `copy(audio)` or `copy(samples(audio))`
when isolation is needed. Channel extraction through `channel` returns a copy.

Most transformations return a new `AudioBuffer`. In particular, `gain`,
`normalize`, `trim`, `mix`, `mono`, `stereo`, and `join_channels` do not promise
in-place operation.

## Where to go next

- Read [`audio.md`](audio.md) for sample-level operations and edge cases.
- Read [`music-and-synthesis.md`](music-and-synthesis.md) for beats and score
  rendering.
- Read [`analysis.md`](analysis.md) for frame placement and feature semantics.
- Read [`events-and-evaluation.md`](events-and-evaluation.md) for onset scoring.
