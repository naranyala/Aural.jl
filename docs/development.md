# Development guide

## Repository layout

```text
Project.toml       package metadata and compatibility bounds
src/               Aural implementation
test/              package and regression tests
docs/              maintained Markdown documentation
README.md          project landing page
TODOS.md           roadmap and explicitly unimplemented work
```

The source is intentionally flat. `src/Aural.jl` defines the module, includes
the implementation files, and owns the explicit public export list.

## Running tests

The normal command is:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The test suite includes:

- package load and public API checks;
- audio ownership, dimensions, rates, empty buffers, trims, mixing, and
  invalid inputs;
- symbolic timing and overlapping synthesis;
- independent direct-DFT checks for odd and even FFT sizes;
- hand-calculated centroid, flux, chroma, and MFCC references;
- exhaustive small event-matching cases;
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

The current package favors:

- deterministic, offline operations;
- explicit units and array layouts;
- symbolic music independent from sampled audio;
- pure transformations where practical;
- small adapters around external packages;
- explicit clipping, normalization, resampling, and lossy-conversion policy.

Real-time guarantees, device handling, broad codec support, and ML integrations
should not be implied until they are implemented and measured.

## Planned work

See [`../TODOS.md`](../TODOS.md) for the full roadmap. Notable open areas
include interval and continuous annotations, score-level integration of the
synthesis helpers, inverse STFT, resampling and filtering, metadata-preserving I/O, CI across
supported Julia versions and operating systems, coverage, fuzzing, performance,
and real-music benchmark validation.
