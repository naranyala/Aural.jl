# Development guide

## Repository layout

```text
Project.toml       package metadata and compatibility bounds
src/               Aural implementation and responsibility-based submodules
test/              package and regression tests
docs/              maintained Markdown documentation
README.md          project landing page
TODOS.md           roadmap and explicitly unimplemented work
```

`src/Aural.jl` defines the module, includes the top-level implementation
boundaries, and owns the explicit public export list. The analysis and event
areas are split into responsibility-based subdirectories; their loader files
preserve a stable package entry point.

The source layout is:

```text
src/
├── Aural.jl                  module definition and exports
├── audio.jl                  AudioBuffer and sample operations
├── music.jl                  symbolic music model
├── synthesis.jl              oscillators, envelopes, and rendering
├── wav_io.jl                 WAV file adapters
├── analysis.jl               analysis loader
├── analysis/                 framing, results, transforms, features, pitch
├── events.jl                 event-analysis loader
└── events/                   annotations, scoring, onsets, tempo
```

The test suite follows the same domain split:

```text
test/
├── runtests.jl               suite runner
├── regressions.jl            cross-cutting regression tests
├── edge_cases.jl             cross-domain edge-case contracts
├── events.jl                 event and tempo tests
├── analysis.jl               analysis pipeline tests
├── audio.jl                  AudioBuffer tests
├── music.jl                  symbolic music tests
└── synthesis.jl              synthesis and rendering tests
```

## Running tests

The normal command is:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The analysis example can be run with:

```sh
julia --project=. examples/analysis_summary.jl [path/to/audio.wav]
```

For an allocation and elapsed-time measurement on longer inputs:

```sh
julia --project=. benchmark/analysis.jl 10
```

Both scripts use the package's exported API and serve as integration and
performance checks.

The test suite includes:

- package load and public API checks;
- audio ownership, dimensions, rates, empty buffers, trims, mixing, and
  invalid inputs;
- symbolic timing and overlapping synthesis;
- independent direct-DFT checks for odd and even FFT sizes;
- hand-calculated centroid, flux, chroma, and MFCC references;
- exhaustive event-matching cases;
- WAV fixtures written directly through WAV.jl.

In restricted environments where Julia cannot write its package usage log, run
the test file directly with existing compiled modules:

```sh
julia --startup-file=no --compiled-modules=existing --project=. -e \
  'using Aural; include("test/runtests.jl")'
```

The local `Manifest.toml` is ignored and is only a resolved environment for a
working tree. `Project.toml` is the authoritative package metadata and
compatibility declaration.

## Keeping docs accurate

When changing a public function or type:

1. Update its source docstring or nearby explanatory comment when the behavior
   is non-obvious.
2. Update the focused guide in `docs/`.
3. Update the README only when the public workflow, limitations, or navigation
   changes.
4. Add a focused test, especially for units, empty inputs, boundaries, and
   validation behavior.
5. Run the full test suite and search the documentation for stale names or
   defaults.

Examples in documentation should use exported APIs and should be runnable
from a project-aware Julia session. Avoid documenting roadmap items as if they
were implemented.

## Design constraints

The package follows these principles:

- deterministic, offline operations;
- explicit units and array layouts;
- symbolic music independent from sampled audio;
- pure transformations where practical;
- thin adapters around external packages;
- explicit clipping, normalization, resampling, and lossy-conversion policy.

Real-time guarantees, device handling, broad codec support, and ML integrations
should not be implied until they are implemented and measured.

## Planned work

See [`../TODOS.md`](../TODOS.md) for the full roadmap. Notable open areas
include interval and continuous annotations, score-level integration of the
synthesis helpers, inverse STFT, resampling and filtering, metadata-preserving I/O, CI across
supported Julia versions and operating systems, coverage, fuzzing, performance,
and real-music benchmark validation.
