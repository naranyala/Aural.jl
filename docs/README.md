# Aural.jl documentation

This directory contains user and contributor documentation for the `Aural` API.
The guides are organized by responsibility rather than by individual source
file.

## Guides

- [`getting-started.md`](getting-started.md) — install the project, understand
  the units and array layouts, and run an end-to-end workflow.
- [`audio.md`](audio.md) — construct and transform `AudioBuffer` values.
- [`music-and-synthesis.md`](music-and-synthesis.md) — create symbolic notes,
  scores, tones, and rendered audio.
- [`analysis.md`](analysis.md) — frame audio, compute STFTs and spectrograms,
  and extract MIR features.
- [`events-and-evaluation.md`](events-and-evaluation.md) — detect onsets and
  evaluate point-event predictions.
- [`development.md`](development.md) — navigate the repository, run tests, and
  keep documentation aligned with the implementation.

## Package shape

```text
symbolic music
      │
      ▼
  tone/render ───────► AudioBuffer ◄────── read_audio
                            │                  │
                            ├── audio ops      └── WAV files
                            └── stft/features/events
```

The canonical audio layout is `channels × frames`. Symbolic timing is in beats
until `render` converts it to seconds. Analysis outputs are time-aligned to
frame centers and are either one-dimensional tracks or matrices with feature
rows and analysis-frame columns.

## Source map

| File | Responsibility |
| --- | --- |
| `src/Aural.jl` | Module definition and explicit exports |
| `src/audio.jl` | `AudioBuffer` and sample operations |
| `src/music.jl` | Pitch, note, tempo, event, and score types |
| `src/synthesis.jl` | Oscillators, noise, envelopes, and score rendering |
| `src/analysis.jl` | Analysis loader and public include boundary |
| `src/analysis/` | Framing, result containers, transforms, features, and pitch |
| `src/events.jl` | Event loader and public include boundary |
| `src/events/` | Annotations, scoring, onset detection, and tempo estimation |
| `src/wav_io.jl` | WAV adapters |
| `test/runtests.jl` | Test runner and suite ordering |
| `test/regressions.jl` | Boundary and regression tests |
| `test/edge_cases.jl` | Cross-domain edge-case contracts |
| `test/events.jl` | Event and tempo behavior |
| `test/analysis.jl` | Analysis pipeline behavior |
| `test/audio.jl` | AudioBuffer behavior |
| `test/music.jl` | Symbolic music behavior |
| `test/synthesis.jl` | Synthesis and rendering behavior |

The roadmap in [`../TODOS.md`](../TODOS.md) is separate from the reference
documentation and describes planned work, not supported behavior.
