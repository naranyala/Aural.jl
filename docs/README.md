# Aural.jl documentation

This directory contains the maintained user and contributor documentation for
the current `Aural` API. The package is deliberately small, so the guides are
organized by responsibility instead of by individual source file.

## Guides

- [`getting-started.md`](getting-started.md) — install the project, understand
  the units and array layouts, and run an end-to-end workflow.
- [`audio.md`](audio.md) — construct and transform `AudioBuffer` values.
- [`music-and-synthesis.md`](music-and-synthesis.md) — create symbolic notes,
  scores, tones, and rendered audio.
- [`analysis.md`](analysis.md) — frame audio, compute STFTs and spectrograms,
  and extract baseline features.
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
| `src/io.jl` | WAV adapters |
| `src/analysis.jl` | Framing, FFTs, spectrograms, and features |
| `src/events.jl` | Point-event annotations, onset detection, and scoring |
| `test/runtests.jl` | Package-level API and MIR tests |
| `test/regressions.jl` | Boundary and regression tests |

The roadmap in [`../TODOS.md`](../TODOS.md) is intentionally separate from the
reference documentation: it describes future work, not supported behavior.
