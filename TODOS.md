# Aural.jl Roadmap

Personal audio and music-processing toolkit for Julia.

## Product Direction

`Aural.jl` is the reusable audio and music-processing layer. It should remain
useful from a Julia session, notebook, batch job, test suite, or another host
application without requiring WebView, Preact, JSON3, LinuxCompanion, or a
desktop session.

### Current Status

- **Tests**: Baseline package/regression coverage plus focused contract tests
  for shared analysis settings, provenance, enriched features, pitch, onset
  strengths, timing error, tempo, and beat annotations.
- **Coverage**: AudioBuffer, music model, synthesis, WAV I/O, STFT/spectrogram,
  baseline and enriched features, onset detection, tempo/beat primitives, and
  event evaluation with exhaustive oracle.
- **Dependencies**: DSP 0.8.6, FFTW 1.10.0, WAV 1.2.0 (all runtime).
- **Branch**: `main`, pushed to GitHub.

### API Correction

`duration_beats(event)` returns the event's duration; `duration_beats(score)`
returns the latest event end. Compute an event's end as
`event.start_beat + duration_beats(event)`.

## Ownership Boundary With `webview-app-with-julia`

The two repositories are intentionally layered:

| Concern | Aural.jl owns | webview-app-with-julia owns |
| --- | --- | --- |
| Audio data | `AudioBuffer`, sample-rate/layout invariants, sample conversion policy | Input selection, path permissions, cache locations, and lifecycle |
| Processing | Synthesis, mixing, framing, FFT features, onset/event algorithms | Choosing an analysis profile and scheduling work |
| Results | Julia result types, feature names, units, timestamps, provenance | Versioned JSON DTOs, frontend validation, display, export, and persistence |
| File I/O | Reusable WAV adapter and future format adapters | File discovery, supported-format messaging, and user-facing errors |
| Runtime | Offline, deterministic, in-memory operations | WebView bridge, jobs, cancellation, resource limits, and UI responsiveness |

`Aural.jl` may be consumed by the app, but must not import app modules or
depend on WebView, Preact, JSON3, LinuxCompanion, or application state. The app
must call only Aural's exported API and keep its JSON/bridge translation in an
app-owned adapter. Do not pass `AudioBuffer`, `Spectrogram`, or internal arrays
directly across the WebView boundary.

## Cross-Project Integration Contract

- Develop against `../Aural.jl` with `Pkg.develop(path="../Aural.jl")`; use a
  registered or tagged Aural release before distributing the app.
- Treat `AudioBuffer` as `channels × frames`, with sample rate in samples per
  second. Convert browser/bridge input explicitly and validate finite samples,
  positive rates, channel count, and input-size limits in the app.
- Use `read_audio`/`write_audio` only for the formats Aural actually supports.
  Unsupported codecs belong behind optional adapters; they do not expand the
  core API implicitly.
- Keep app-facing response names stable even if an Aural result type changes.
  A response should include an explicit schema version, source metadata,
  analysis settings, timestamps, values, warnings, and provenance.
- Return small summaries by default. Large spectra, frame matrices, and raw
  samples should be paged, downsampled, cached, or written to an app-owned
  artifact rather than embedded in one WebView response.
- Keep long-running work off the WebView request loop. Aural remains a
  synchronous library; the host owns worker threads/tasks, cancellation, and
  progress reporting.
- Add cross-project contract tests for representative WAV input, malformed
  input, empty/short signals, unsupported formats, numerical tolerances, and
  error-code translation.

## High-Leverage Backlog

These are the recommended next investments for the current codebase. They are
ordered by how many later features they unlock. Complete these before adding
more specialized effects, codecs, or machine-learning integrations.

### HL-1: Freeze the analysis contract and provenance [x]

The current analysis functions repeat framing keywords and return lightweight
containers with only partial metadata. A stable configuration/result contract
will make every future feature and host integration easier to trust.

- [x] Introduce a small immutable `AnalysisConfig`/`FrameConfig` describing
  channel policy, window, window size, hop size, FFT size, and padding.
- [x] Make `stft`, `rms`, and future frame-based features accept the shared
  config while preserving their current keyword forms as compatibility sugar.
- [x] Add validated metadata accessors for source frames, sample rate, frame
  centers, frequency axis, and the exact configuration used.
- [x] Strengthen `FeatureTrack` and `FeatureMatrix` invariants: matching
  lengths/shapes, finite and ordered timestamps, and explicit empty behavior.
- [x] Document a versioned convention for frame centers, padded tails, array
  orientation, and units; add migration notes before changing defaults.

**Acceptance**: Every frame-based result can be interpreted without inspecting
private fields, and two features computed from the same config have identical
frame timing and provenance.

### HL-2: Build a validated, reusable feature foundation [ ]

The existing RMS/centroid/flux/chroma/MFCC primitives are useful baselines,
but common features and numerical conventions are still scattered or absent.

- [x] Add one shared finite-input and channel-policy validation path for all
  analysis entry points.
- [x] Add `spectral_bandwidth`, `spectral_rolloff`, `spectral_flatness`, and
  `zero_crossing_rate` with explicit frequency/power and threshold semantics.
- [x] Add `crest_factor`, `dc_offset`, `amplitude_db`, and `power_db` with a
  documented reference level and a defined silent-signal result.
- [ ] Add optional normalization/calibration for one-sided spectra; keep the
  current squared-magnitude behavior available and clearly named.
- [ ] Add sine, silence, impulse, noise, and stereo reference fixtures with
  expected values and numerical tolerances.

**Acceptance**: A host can request a coherent fundamental feature set and get
finite, time-aligned results with documented behavior for silence, NaN/Inf,
short signals, padding, and multichannel input.

### HL-3: Make analysis bounded and allocation-aware [ ]

`frame` currently materializes a complete window matrix and `stft` allocates a
temporary FFT buffer per analysis call. That is fine for small experiments but
will become the main limit for long recordings and desktop use.

- [x] Separate a materialized `frame` convenience API from an iterator,
  callback, or chunked frame-processing API.
- [x] Reuse scratch buffers and windows in STFT/feature pipelines where this
  does not compromise thread safety or result ownership.
- [ ] Add chunked processing for feature tracks and compact summaries without
  requiring the full recording or full feature matrix in memory.
- [ ] Add `BenchmarkTools.jl` benchmarks for bounded windows, ten-minute mono
  audio, stereo downmixing, and repeated analyses.
- [ ] Record allocation, throughput, and peak-memory budgets for the host app;
  add regression thresholds only after measuring realistic hardware.

**Acceptance**: Long-file analysis has a documented memory bound, repeated
analysis does not retain scratch buffers or source arrays unexpectedly, and
performance regressions are visible in CI or a reproducible benchmark command.

### HL-4: Turn onset analysis into a dependable MIR primitive [ ]

Onset detection is already the package's first end-to-end MIR workflow. Making
it robust creates value for rhythm, segmentation, visualization, and future
tempo estimation.

- [x] Add adaptive/local threshold options alongside the current global
  threshold fraction.
- [x] Add peak backtracking or a documented latency-compensation policy.
- [ ] Add a streaming/chunked peak picker with state carried across chunks.
- [x] Return optional onset strengths/confidence values and preserve source
  frame provenance.
- [ ] Add a small versioned annotated fixture set and report precision, recall,
  F1, and timing error separately.

**Acceptance**: The detector behaves predictably on silence, impulses,
repeated transients, plateaus, and chunk boundaries, and its metrics can be
reproduced from checked-in fixtures.

### HL-5: Add pitch and rhythm primitives with confidence [ ]

Chroma describes pitch classes but does not identify fundamental frequency or
musical time. These are the next enriched features with broad product value.

- [x] Add monophonic fundamental-frequency tracking with configurable range,
  confidence, and explicit unvoiced/ambiguous states.
- [x] Add tempo estimation from onset/flux evidence with confidence and a
  clearly documented BPM range and octave-error policy.
- [x] Add beat positions as a separate annotation type; do not overload point
  onset annotations with beat-continuity semantics.
- [ ] Add pitch/tempo/beat evaluation metrics and reference fixtures before
  exposing convenience APIs as production-quality results.

**Acceptance**: Pitch and rhythm outputs include confidence and provenance,
handle silence and noisy input explicitly, and are evaluated on deterministic
fixtures rather than only synthetic happy paths.

### HL-6: Make the package releasable and easy to adopt [ ]

The code is useful, but adoption is limited until its compatibility, quality,
and dependency story is reproducible outside the development machine.

- [x] Add CI for the declared Julia support range, including Julia 1.10 and the
  current development version.
- [ ] Add Aqua/package-structure checks, clean-environment tests, and a reliable
  cold-start/precompilation measurement.
- [ ] Add a tagged release and license.
- [x] Maintain a changelog and compatibility notes.
- [x] Add a minimal host-integration example.
- [ ] Keep optional codecs, devices, plotting, and ML integrations behind
  extensions or separate packages; test dependency/license obligations.
- [ ] Define which APIs are stable, experimental, or internal before changing
  `AudioBuffer` or analysis result representations.

**Acceptance**: A new user can install a tagged release in a clean Julia
environment, run the documented analysis example, and understand the support
limits without reading repository history.

These six items are the execution shortlist. The feature bundles below and the
larger possibility map remain idea pools; promote an item only when it has a
concrete use case, API shape, reference behavior, and test plan.

## Enriched Feature Roadmap

The feature roadmap is deliberately staged. Each feature must have defined
units, timestamp semantics, edge-case behavior, a reference signal, and an
app-usable summary before it is considered complete.

### Feature bundle A: trustworthy fundamentals [CURRENT/NEXT]

- [x] RMS, peak, spectral centroid, spectral flux, chroma, MFCC, and onset
  baselines.
- [x] Add bandwidth, rolloff, flatness, crest factor, decibel/dBFS, DC offset,
  and zero-crossing helpers with explicit conventions.
- [x] Add feature provenance: window, hop, FFT size, padding, channel, tuning,
  mel configuration, and source sample rate.
- [x] Define a common `AnalysisConfig` and stable result metadata without
  forcing JSON or UI concerns into the library.

### Feature bundle B: richer time-frequency analysis [ ]

- [ ] Add calibrated power/PSD options alongside the current squared-magnitude
  spectrogram.
- [ ] Add inverse STFT with overlap-add reconstruction tests.
- [ ] Add constant-Q/chroma variants only after documenting tuning, octave,
  normalization, and frequency-bin policies.
- [ ] Add reusable window/filter helpers and avoid duplicating DSP.jl types in
  the public API.

### Feature bundle C: pitch, rhythm, and events [ ]

- [x] Add fundamental-frequency tracking with confidence and unvoiced states.
- [x] Add tempo and beat representations separate from point onset events;
  downbeat and meter remain future work.
- [ ] Add interval annotations for notes/chords and continuous pitch tracks.
- [ ] Add beat-continuity and note/chord metrics in addition to point-event F1.
- [ ] Benchmark against small, versioned real-recording fixtures and publish
  known failure modes.

### Feature bundle D: practical audio processing [ ]

- [ ] Add fades, concatenation, clipping/saturation, filtering, resampling,
  convolution, and delay with explicit latency and channel rules.
- [ ] Add loudness/true-peak measurements when a documented reference and use
  case exist.
- [ ] Add chunked processing interfaces for recordings that do not fit memory.
- [ ] Keep realtime/device APIs optional and separate from the offline core.

### Feature bundle E: higher-level and optional integrations [ ]

- [ ] Add MIDI import/export and map external metadata into `Score` explicitly.
- [ ] Add similarity/fingerprinting and embedding adapters without making ML a
  core dependency.
- [ ] Add optional FLAC/Ogg/Opus/MP3 adapters behind separate extensions or
  packages.
- [ ] Add serialization for scores, annotations, configs, and feature summaries
  with schema/version migration rules.

For the WebView product, the app backlog should select a small profile from
these bundles and define its JSON shape. Aural should not implement product
features merely because the frontend can display them.

## Session Groups

Work organized into sessions completable in one sitting. Each session lists
concrete tasks with acceptance criteria.

### Session 1: Synthesis Foundation [DONE]

Turn the package from a tone generator into a synthesizer.

- [x] Implement cosine, saw, square, and triangle oscillators.
- [x] Define phase and frequency behavior for generated buffers.
- [x] Implement deterministic white noise with an injectable random source.
- [x] Implement linear and exponential ramps.
- [x] Implement an ADSR envelope with documented time semantics.
- [x] Define a simple monophonic voice.
- [x] Implement note velocity mapping without assuming a single loudness law.
- [x] Add a simple oscillator-plus-envelope instrument.
- [x] Add tests comparing rendered duration, frequency, and amplitude envelope.
- [x] Add one example: melody → WAV file with ADSR-shaped notes.

**Acceptance**: A note with attack/release sounds musical; duration, frequency,
and amplitude match expected values within tolerance.

### Session 2: Score Rendering [NEXT]

Make scores produce real music with rests, overlaps, and multiple voices.

- [ ] Render rests and overlapping notes.
- [ ] Define deterministic voice allocation.
- [ ] Add release tails without truncating the output unexpectedly.
- [ ] Define polyphonic rendering with explicit overlap behavior.
- [ ] Add one example that writes a polyphonic melody to WAV.

**Acceptance**: A chord renders as simultaneous tones; rests produce silence;
overlapping notes don't clip unexpectedly.

### Session 3: Audio Assembly

Practical tools for building longer audio from pieces.

- [ ] Implement fade-in and fade-out.
- [ ] Implement concatenation with clear sample-rate checks.
- [ ] Implement explicit hard clipping and soft saturation separately.
- [ ] Add tests for each operation with edge cases (empty, single-sample, mismatched rates).

**Acceptance**: Two buffers concatenate cleanly; fades produce smooth ramps;
clipping/saturation behave as documented.

### Session 4: Music Theory

Unlock transposition, scales, and chords.

- [ ] Define intervals and transposition.
- [ ] Define scales and scale degrees.
- [ ] Define chords and chord symbols.
- [ ] Test enharmonic spelling separately from pitch equality.
- [ ] Make transposition and quantization pure transformations.
- [ ] Define meter and bar/beat positions if useful.

**Acceptance**: `transpose(C4, Perfect(5))` equals G4; scale/chord constructors
validate inputs; enharmonic spelling is separate from frequency equality.

### Session 5: MIDI Interchange

Connect to real music files via MIDI.jl (already probed, resolves v2.7.0).

- [ ] Add MIDI import and export.
- [ ] Map external MIDI notes into the internal NoteEvent model.
- [ ] Preserve tempo, program, channel, and metadata where useful.
- [ ] Test actual MIDI write/read round-trip against NoteEvent and Score.

**Acceptance**: A MIDI file imports as a Score; exporting and re-importing
preserves note pitches, timings, and velocities.

### Session 6: DSP Toolkit

Essential analysis and processing tools.

- [ ] Add calibrated periodograms.
- [ ] Add peak, crest factor, zero-crossing rate, and decibel helpers.
- [ ] Add DC-offset measurement and removal.
- [ ] Add FIR and IIR filtering through a stable adapter.
- [ ] Add resampling through a stable adapter.
- [ ] Define whether analysis returns plain arrays or domain-aware result types.
- [ ] Add numerical tolerance tests and known reference signals.

**Acceptance**: A known sine tone has correct peak dBFS; a low-pass filter
removes high frequencies; ZCR matches expected count.

### Session 7: WAV Polish

Production-quality WAV I/O.

- [ ] Preserve sample rate, channel count, and sample format on round trips.
- [ ] Preserve WAV bit depth and metadata and define explicit encoding options.
- [ ] Decide whether load/save should use FileIO.jl or a direct API.
- [ ] Test malformed files and truncated streams.
- [ ] Add larger malformed-file fuzzing and additional PCM bit depths.
- [ ] Document native-library and codec requirements.

**Acceptance**: A 24-bit WAV round-trips without bit-depth conversion; truncated
files produce clear errors; metadata is preserved.

### Session 8: Annotations & Evaluation

Richer annotation types and MIR evaluation.

- [ ] Annotation types for beats, onsets, pitches, notes, and chords.
- [ ] Add interval annotations for notes/chords and continuous pitch tracks.
- [ ] Add annotation import/export with track IDs and provenance.
- [ ] Add adaptive thresholds, onset backtracking, and streaming peak picking.
- [ ] Add beat tracking and continuity metrics.
- [ ] Add corpus-level metric aggregation and confidence intervals.
- [ ] Benchmark onset detection on annotated real recordings.
- [ ] Compare MFCC/chroma with external reference implementations.
- [ ] Add dataset manifests and grouped train/validation/test splits.
- [ ] Add detailed feature provenance (window, padding, FFT and mel settings).

**Acceptance**: Beat tracking F1 reported on a public dataset; onset detection
benchmarked against manual annotations; features match external references.

### Session 9: CI and Quality

Automated quality gate.

- [ ] Add formatting and linting conventions.
- [ ] Add CI for supported Julia versions.
- [ ] Add property tests for duration, channel count, and sample-rate invariants.
- [ ] Add golden-file tests for known WAV, MIDI, and analysis results.
- [ ] Add round-trip tests for every supported interchange format.
- [ ] Add allocation and latency regression tests.
- [ ] Track numerical tolerances and reference implementation versions.
- [ ] Check dependency licenses and native-library obligations.

**Acceptance**: CI runs on push; property tests pass; golden files catch regressions.

### Session 10: Documentation & Release

Prepare for use and potential publication.

- [ ] Confirm whether the package is for personal use only or may become public.
- [ ] Choose a license before publishing.
- [ ] Add docs/ after the first public API exists.
- [ ] Add changelog, deprecation policy, and semantic-versioning rules.
- [ ] Define contribution, attribution, and citation requirements if public.

**Acceptance**: License chosen; docs build; changelog exists.

### Session 11: Host Integration Support [ ]

Make Aural straightforward to consume from applications without moving
application policy into the library.

- [ ] Add a small host-integration example: WAV input → analysis profile →
  compact summary and feature artifact.
- [ ] Define stable accessors for feature metadata, timestamps, values, and
  provenance so hosts do not depend on private fields.
- [ ] Add bounded-window and larger-file benchmarks for the feature bundles
  used by `webview-app-with-julia`.
- [ ] Publish a tagged release with compatibility notes, dependency/license
  information, and migration guidance.
- [ ] Add cross-project fixtures and contract tests without importing WebView,
  JSON3, or frontend code into Aural.

**Acceptance**: A host can depend on a tagged Aural release, run a documented
offline analysis, serialize its own response shape, and upgrade Aural without
private API coupling.

## Design Principles

- Keep the core deterministic and usable without an audio device.
- Keep symbolic music independent from sampled audio.
- Use explicit units: frames, seconds, hertz, beats, and samples.
- Represent audio as channels by frames unless an external adapter requires a
  different layout.
- Prefer immutable metadata and pure transforms where practical.
- Make clipping, normalization, resampling, and lossy conversion explicit.
- Keep external packages behind small integration files.
- Do not re-export an entire dependency as part of the public API.
- Add a test and a small usage example for every public concept.
- Avoid real-time guarantees until allocation and latency behavior are measured.

## Decisions To Lock

- [x] Package name: `Aural`.
- [ ] Confirm personal use vs public.
- [x] Canonical audio layout: `channels x frames`.
- [x] Generated audio defaults to `Float32`.
- [x] Plain numeric values initially; defer `Unitful.jl`.
- [x] `AudioBuffer` is a new wrapper type; evaluate `SampledSignals` later.
- [x] Julia 1.10 minimum; development on Julia 1.12.7.
- [ ] Choose a license.

## Reference: Dependency Plan

### Julia Standard Libraries

- [ ] `LinearAlgebra`: vector and matrix operations.
- [ ] `Statistics`: common signal statistics.
- [ ] `Random`: deterministic noise and test fixtures.
- [ ] `Dates`: file or recording metadata only if needed.

### First-Wave Third-Party

- [x] `FFTW.jl`: FFT for STFT.
- [x] `DSP.jl`: filters, windows, spectrograms (Phase 4).
- [x] `WAV.jl`: WAV read/write (Phase 5).
- [ ] `MIDI.jl`: MIDI file parsing (Phase 5).
- [ ] `FileIO.jl`: common load/save dispatch (only if multiple formats justify it).

### Audio Buffer and Streaming

- [ ] `SampledSignals.jl`: evaluate before finalizing AudioBuffer.
- [ ] `PortAudio.jl`: defer to Phase 6.
- [ ] `LibSndFile.jl`: compare with WAV.jl before choosing backend.
- [ ] `FixedPointNumbers.jl`: keep out of core unless required.
- [ ] `Unitful.jl`: evaluate carefully for typed units.

### Development Dependencies

- [ ] `Documenter.jl`: API docs after public concepts stabilize.
- [ ] `Aqua.jl`: package quality checks.
- [ ] `BenchmarkTools.jl`: allocation and throughput benchmarks.
- [ ] `Plots.jl` or `Makie.jl`: optional visualization only.

### Dependency Probe Results

Checked 2026-09-09 with Julia 1.12.7:

- [x] `DSP` v0.8.6 resolves and loads.
- [x] `MIDI` v2.7.0 resolves and loads.
- [x] `WAV` v1.2.0 resolves and loads.
- [x] `FileIO` v1.20.0 resolves and loads.
- [x] WAV write/read round-trip tested against AudioBuffer.
- [ ] MIDI write/read round-trip tested against NoteEvent and Score.
- [ ] Measure precompilation and load-time cost.

### Dependency Rules

- [ ] Keep Phase 1 free of external runtime dependencies where practical.
- [ ] Add one dependency at a time and record why it is needed.
- [ ] Prefer a thin adapter over exposing a dependency's types everywhere.
- [ ] Avoid simultaneously adopting overlapping audio-buffer abstractions.
- [ ] Keep device, codec, and plotting dependencies optional.
- [ ] Check license, maintenance, Julia compatibility, and native libs before adoption.
- [ ] Add package extensions for optional integrations.
- [x] Record dependency ranges in Project.toml; ignore local manifest.

## Reference: Possibility Map

Plausible future directions. Move items into sessions only when there is a
concrete use case, a stable API idea, and acceptable cost.

### Audio Semantics And Correctness

- [ ] Interleaved vs planar storage at every I/O boundary.
- [ ] Channel layouts beyond mono and stereo.
- [ ] Sample format conversion for integer PCM, fixed point, and float.
- [ ] Headroom and behavior for values outside [-1, 1].
- [ ] NaN, infinity, empty-buffer, and zero-length behavior.
- [ ] Phase, frame origin, inclusive/exclusive time ranges, and rounding.
- [ ] dB reference conventions for amplitude, power, and full scale.
- [ ] Pan laws and stereo-width semantics.
- [ ] Clock and sample-rate metadata for recorded or streamed material.
- [ ] Loudness measurements (LUFS, true peak) if needed.
- [ ] Channel alignment and latency metadata for multitrack material.

### Advanced DSP

- [ ] STFT and inverse STFT with documented padding and overlap rules.
- [ ] Convolution and convolution reverb.
- [ ] Equalizers, shelving filters, and parametric filter helpers.
- [ ] Delay lines, echoes, chorus, flanger, and phaser effects.
- [ ] Compressors, limiters, gates, expanders, and transient shaping.
- [ ] Pitch shifting and time stretching.
- [ ] Phase vocoder tools.
- [ ] Alias-reduced oscillator and oversampling strategies.
- [ ] Multirate processing and polyphase filter banks.
- [ ] Wavelet or constant-Q analysis if a real use case appears.
- [ ] Numerical stability guidance for long-running filters and feedback.

### Audio Analysis And Machine Learning

- [ ] Fundamental-frequency and pitch tracking.
- [ ] Onset, beat, tempo, and downbeat detection.
- [ ] Chroma, constant-Q, spectral centroid, rolloff, flux, and MFCCs.
- [ ] Note or chord recognition experiments.
- [ ] Voice activity and silence classification.
- [ ] Source separation or stem-analysis experiments.
- [ ] Audio fingerprinting or similarity search.
- [ ] Embedding/model adapters without making ML a core dependency.
- [ ] Feature timestamps, window centers, padding, and confidence scores.
- [ ] Reproducible datasets and reference clips.

### Music Theory, Tuning, And Notation

- [ ] Tunings beyond twelve-tone equal temperament.
- [ ] Just intonation, alternate temperaments, and arbitrary cents.
- [ ] Separate pitch identity, spelling, and sounding frequency.
- [ ] Microtonal accidentals and pitch bends.
- [ ] Phrase, articulation, dynamics, ornaments, and expressive markings.
- [ ] Richer meter, tuplets, swing, polyrhythm, and rubato.
- [ ] Repeated sections, cues, and score navigation.
- [ ] MusicXML, ABC notation, and LilyPond interchange.
- [ ] MIDI 2.0, MPE, controller curves, program changes, and SysEx.
- [ ] How notation preserves information that MIDI cannot represent.

### Instruments And Sound Design

- [ ] Subtractive, additive, FM, AM, and wavetable instruments.
- [ ] Physical-model or waveguide experiments.
- [ ] Granular synthesis and sample playback.
- [ ] Samplers with loop points, root notes, and velocity layers.
- [ ] Modulation sources, LFOs, and parameter automation.
- [ ] Buses, sends, returns, and effect chains.
- [ ] Instrument interface for offline and block-based rendering.
- [ ] Preset serialization and versioning.
- [ ] Deterministic seed handling for procedural instruments.

### Composition And Interaction

- [ ] Lazy or streaming event patterns for long compositions.
- [ ] Pattern transformations: repeat, rotate, mirror, and stretch.
- [ ] Generative rhythm and melody helpers.
- [ ] Constraint-based or rule-based composition experiments.
- [ ] Live-coding-friendly APIs and concise constructors.
- [ ] Notebook examples with waveform and spectrogram displays.
- [ ] Interactive piano-roll or score visualization.
- [ ] Reproducible random composition seeds.
- [ ] Serialization for scores, patterns, and project metadata.

### Interoperability And Production Audio

- [ ] Preserve common metadata: artist, title, album, markers, cues.
- [ ] Broadcast-oriented WAV metadata when required.
- [ ] Streaming readers and writers for non-seekable sources.
- [ ] Format probing and clear unsupported-format errors.
- [ ] Optional FLAC, Ogg, Opus, and MP3 adapters.
- [ ] JACK, ALSA, PipeWire, CoreAudio, and WASAPI device paths.
- [ ] Plugin hosting or export (LV2, VST, CLAP) only if production-audio.
- [ ] DAW project data import/export if needed.
- [ ] Network audio or OSC integration for concrete installations.

### Real-Time Reliability

- [ ] No-allocation callback subset of the API.
- [ ] Thread-safety and ownership rules for audio buffers.
- [ ] Lock-free or bounded queues for control messages.
- [ ] Device clock drift and sample-rate mismatch handling.
- [ ] Underrun, overrun, cancellation, and shutdown behavior.
- [ ] Latency measurement and round-trip latency tests.
- [ ] Full-duplex input/output examples.
- [ ] Graceful degradation when a device disappears.
- [ ] Documentation of forbidden operations on the audio callback thread.

### Performance And Deployment

- [ ] Benchmarks for allocation, throughput, latency, and memory use.
- [ ] Profile generated code for common sample types and channel counts.
- [ ] SIMD and multithreading after measuring a bottleneck.
- [ ] Chunked processing for audio longer than available memory.
- [ ] Caching for repeated spectra, wavetables, and impulse responses.
- [ ] GPU processing only for workloads that justify transfer costs.
- [ ] Test package behavior in a clean Julia environment.
- [ ] Sysimage or precompile improvements after the API settles.
- [ ] Reproducible environments for examples and rendered assets.

### Testing And Quality

- [ ] Property tests for duration, channel count, and sample-rate invariants.
- [ ] Golden-file tests for known WAV, MIDI, and analysis results.
- [ ] Round-trip tests for every supported interchange format.
- [ ] Malformed-input and fuzz tests at file boundaries.
- [ ] Cross-platform CI for supported Julia versions.
- [ ] Allocation and latency regression tests for realtime code.
- [ ] Perceptual listening tests for synthesis and DSP changes.
- [ ] Numerical tolerances and reference implementation versions.
- [ ] Dependency licenses and transitive native-library obligations.
- [ ] Changelog, deprecation policy, and semantic-versioning rules.

### Package Ecosystem And Maintenance

- [ ] Split into core, DSP, music, I/O, and realtime packages if warranted.
- [ ] Extension boundaries so optional dependencies stay optional.
- [ ] Public versus experimental APIs.
- [ ] Deprecation and migration notes when representations change.
- [ ] Issue templates for bugs, feature requests, and design proposals.
- [ ] Record major API decisions in short design notes.
- [ ] Track upstream compatibility for audio and MIDI dependencies.
- [ ] Decide whether generated test audio and example assets may be committed.
- [ ] Contribution, attribution, and citation requirements if public.

### Explicit Non-Goals To Revisit

- [ ] Do not become a full DAW unless the project direction changes.
- [ ] Do not promise sample-accurate realtime behavior without dedicated tests.
- [ ] Do not implement every codec in the core package.
- [ ] Do not duplicate mature DSP or MIDI packages without a demonstrated gap.
- [ ] Do not make plotting, machine learning, or device access mandatory.
- [ ] Do not support every music-notation tradition in the first release.
- [ ] Revisit these non-goals when actual projects expose a missing capability.

## Definition Of A Useful First Release

- [x] Generate a tone and a short melody.
- [x] Mix and normalize audio buffers.
- [x] Render a score with a simple oscillator and envelope.
- [x] Write and read WAV files.
- [ ] Read and write a basic MIDI file.
- [x] Compute a spectrum and a spectrogram.
- [x] Pass tests for sample-rate, duration, channel, and timing behavior.
- [x] Explain the public API in a concise README.

## Verification Command

After repeated cold-precompilation timeouts:

```sh
JULIA_PKG_PRECOMPILE_AUTO=0 julia --startup-file=no --project=. -e 'using Pkg; Pkg.test(; julia_args=["--compiled-modules=existing"])'
```
