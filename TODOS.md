# Aural.jl Roadmap

Personal audio and music-processing toolkit for Julia.

The working package name is `Aural`. Rename it before creating `Project.toml` if
another name better fits the long-term purpose.

## Product Direction

### MIR delivery status

#### Latest test audit

- [x] Expand the suite from 74 to 757 passing assertions on Julia 1.12.7.
      Counts include parameterized assertions, not 757 independent scenarios.
- [x] Add `test/regressions.jl`: ownership, empty buffers, channel/rate mismatches,
      cancellation mixing, trim boundaries, invalid inputs, music timing, and
      overlapping/muted synthesis.
- [x] Check STFT against a direct DFT for odd/even FFT lengths and custom windows.
- [x] Check centroid/flux against hand-calculated spectra and MFCC against an
      analytic two-filter example; verify gain invariants.
- [x] Compare event matching with an exhaustive assignment oracle across 192
      small sequence/tolerance combinations, including duplicates and ordering.
- [x] Test externally written PCM WAV input, mono output, missing files, and
      truncated-header rejection.
- [x] Fix confirmed defects: zero-length trims returning a sample, event duration
      reporting end time, infinite tuning acceptance, and Int16 RMS overflow.
- [ ] Measure source line/branch coverage; no coverage percentage is claimed.
- [ ] Validate real-music onset accuracy and external feature parity on datasets.
- [ ] Run CI on the minimum Julia version and other operating systems.
- [ ] Add larger malformed-file fuzzing, additional PCM bit depths/metadata,
      performance regression checks, and large-recording memory tests.
- [ ] Audit direct result constructors and mutable result arrays for invariant
      violations, extreme numeric inputs, and unsupported sample types.

API correction: `duration_beats(event)` now returns the event's duration;
`duration_beats(score)` still returns the latest event end. Compute an event's
end as `event.start_beat + duration_beats(event)`.

First four steps are implemented; annotations and evaluation now have point-event
baselines, with broader coverage still pending:

1. [x] WAV input/output through `WAV.jl`, with channel-layout conversion.
2. [x] `FrameGrid`: windows, hops, tail padding, channel selection, timestamps.
3. [x] STFT and raw-power spectrograms through FFTW with DSP Hann windows.
4. [x] Baseline RMS, power-weighted centroid, spectral flux, chroma, and MFCC.
5. [ ] Annotation types for beats, onsets, pitches, notes, and chords.
6. [ ] Dataset loaders and leakage-safe train/test splits.
7. [ ] MIR evaluation metrics and benchmark datasets.
8. [ ] Optional ML integrations, such as Flux or MLJ (not installed).

### MIR event milestone

- [x] Add `EventAnnotations` for onset and beat timestamps in seconds, with
      finite/non-negative validation, sorting, and input copying.
- [x] Add `detect_onsets` using spectral flux and relative-threshold local peaks.
- [x] Define plateau tie-breaking, strongest-peak minimum spacing, and silence
      behavior. Document first-frame and window-latency limitations.
- [x] Add `evaluate_events` and `EventScore`: maximum-cardinality one-to-one
      tolerance matching, TP/FP/FN, precision, recall, and F1.
- [x] Document inclusive tolerances, duplicate matching, and zero metrics for
      empty denominators; reject comparisons between different annotation kinds.
- [x] Verify all 74 tests on Julia 1.12.7, including 22 new event tests and
      synthetic click detection within 16 ms.
- [ ] Add interval annotations for notes/chords and continuous pitch tracks.
- [ ] Add annotation import/export with track IDs and provenance.
- [ ] Benchmark onset detection on annotated real recordings; report frame
      timing bias and sensitivity to window/hop/threshold settings.
- [ ] Add adaptive thresholds, onset backtracking, and streaming peak picking.
- [ ] Add beat tracking and continuity metrics (point-event F1 alone is insufficient).
- [ ] Add corpus-level metric aggregation and confidence intervals.
- [ ] Add dataset manifests and grouped train/validation/test splits.

`src/events.jl` implements this milestone using existing dependencies. The full
annotation and evaluation steps above remain unchecked until their broader
requirements and dataset benchmarks are implemented.

- [x] Add direct dependencies: WAV 1.2.0, FFTW 1.10.0, DSP 0.8.6 as resolved
      locally. Compat entries allow compatible updates; they are not exact pins.
- [x] Verify 52 tests (24 MIR plus 28 starter) on Julia 1.12.7, including
      stereo WAV round-trip, DSP STFT reference, padding, timestamps, chroma,
      MFCC silence reference, invalid parameters, and empty inputs.
- [x] Document numerical conventions and runnable MIR example in README.md.
- [ ] Compare MFCC/chroma with external reference implementations on real music.
- [ ] Preserve WAV bit depth and metadata and define explicit encoding options.
- [ ] Add inverse STFT, calibrated PSD, resampling, and filtering.
- [ ] Add detailed feature provenance (window, padding, FFT and mel settings).

Verification command after repeated cold-precompilation timeouts:

```sh
JULIA_PKG_PRECOMPILE_AUTO=0 julia --startup-file=no --project=. -e 'using Pkg; Pkg.test(; julia_args=["--compiled-modules=existing"])'
```

Dependency policy update: WAV, FFTW, and DSP are now regular runtime imports.
The original dependency-free starter remains a historical milestone; optional
device/ML backends remain future work. Project.toml is authoritative; the local
Manifest.toml is ignored for this library.

Build a small, composable library that connects three domains without mixing
their responsibilities:

```text
Symbolic music -> synthesis/rendering -> sampled audio -> DSP and I/O
```

The library should support offline experimentation first. Real-time audio,
device handling, and large codec surfaces come later.

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

- [x] Choose the initial package name: `Aural`.
- [ ] Confirm whether the package is for personal use only or may become
      public.
- [x] Decide that the canonical audio layout is `channels x frames`.
- [x] Decide that generated audio defaults to `Float32`.
- [x] Decide to use plain numeric values initially; defer `Unitful.jl`.
- [x] Decide that `AudioBuffer` is a new wrapper type initially; evaluate
      `SampledSignals.SampleBuf` later.
- [x] Define Julia 1.10 as the initial minimum version; development uses
      Julia 1.12.7.
- [ ] Choose a license before publishing the package.

## Phase 0: Package Foundation

- [x] Create `Project.toml` with the chosen package name and Julia compatibility.
- [x] Create `src/Aural.jl` with a small, explicit export list.
- [x] Create `test/runtests.jl` and a basic package load test.
- [ ] Add formatting and linting conventions.
- [ ] Add CI for supported Julia versions.
- [x] Add a `README.md` with a starter example.
- [ ] Add `docs/` only after the first public API exists.
- [x] Keep the first package layout flat and use included files:
      `audio.jl`, `music.jl`, and `synthesis.jl`.
- [x] Add `analysis.jl` and `io.jl` for MIR analysis and WAV I/O.
- [ ] Split into submodules or multiple packages only after real boundaries
      emerge.

## Starter Verification

- [x] Run `Pkg.test()` successfully on Julia 1.12.7.
- [x] Cover the starter with 28 passing tests for audio buffers, music values,
      and offline synthesis.

## Phase 1: Sampled Audio Core

### `AudioBuffer`

- [x] Define an `AudioBuffer{T}` abstraction for multichannel sampled audio.
- [x] Store samples in `channels x frames` order.
- [x] Store sample rate and channel metadata with the samples.
- [x] Define constructors from vectors, matrices, and compatible array types.
- [x] Validate positive sample rates and consistent channel dimensions.
- [x] Define `nchannels`, `nframes`, `samplerate`, and `duration`.
- [x] Define safe access to individual channels and frame ranges.
- [x] Define access to the underlying array without an implicit copy.
- [x] Preserve generic numeric sample types where practical.
- [x] Default generated audio to `Float32` unless requested.

### Basic Operations

- [x] Implement silence generation.
- [x] Implement channel selection and channel joining.
- [x] Implement mono and stereo conversion.
- [x] Implement gain changes.
- [x] Implement explicit peak normalization.
- [ ] Implement explicit hard clipping and soft saturation separately.
- [x] Implement trim and frame slicing.
- [ ] Implement concatenation with clear sample-rate checks.
- [x] Implement mixing with non-negative offsets and additive overlap.
- [ ] Implement fade-in and fade-out.
- [x] Reject mismatched sample rates and channel counts explicitly.

### First Audio API Target

The first useful API should make this workflow possible:

```julia
x = tone(440.0, 2.0; samplerate=48_000)
y = gain(x, 0.5)
z = mix(x, y; offset=0.25)
write_audio("tone.wav", z)
```

The exact names are provisional. Keep the API small until it is used in real
experiments.

## Phase 2: Symbolic Music Model

### Pitch and Harmony

- [x] Define a pitch representation with unambiguous MIDI-number semantics.
- [x] Define note names and integer accidentals.
- [x] Define conversion between pitch and frequency.
- [x] Define MIDI note-number conversion.
- [ ] Define intervals and transposition.
- [ ] Define scales and scale degrees.
- [ ] Define chords and chord symbols only after the pitch model is stable.
- [ ] Test enharmonic spelling separately from pitch equality.

### Time and Performance

- [x] Define beat-based durations without conflating them with seconds.
- [x] Define tempo as beats per minute.
- [ ] Define meter and bar/beat positions if they prove useful.
- [x] Define `NoteEvent` with pitch, start beat, duration, velocity, and channel
      or voice information.
- [ ] Define rests and control events only when required by actual use cases.
- [x] Define `Score` as an ordered collection of validated events.
- [ ] Define tempo maps only after constant-tempo rendering works.
- [x] Define beat-to-second conversion at the rendering boundary.

### Symbolic API Target

- [x] Make it possible to construct a short melody without raw MIDI objects.
- [ ] Make transposition and quantization pure transformations.
- [ ] Keep notation, MIDI representation, and synthesis voice selection
      separate.

## Phase 3: Synthesis and Rendering

### Signal Generators

- [x] Implement a sine oscillator through `tone`.
- [ ] Implement cosine, saw, square, and triangle oscillators.
- [ ] Define phase and frequency behavior for generated buffers.
- [ ] Implement deterministic white noise with an injectable random source.
- [ ] Implement wavetable lookup only if basic oscillators are insufficient.
- [ ] Define oscillator behavior at discontinuities and band-limiting limits.

### Envelopes and Voices

- [ ] Implement linear and exponential ramps.
- [ ] Implement an ADSR envelope with documented time semantics.
- [ ] Define a simple monophonic voice.
- [ ] Define polyphonic rendering with explicit overlap behavior.
- [ ] Implement note velocity mapping without assuming a single loudness law.
- [ ] Add a simple oscillator-plus-envelope instrument.

### Score Rendering

- [x] Render a constant-tempo `Score` to an `AudioBuffer` with a sine voice.
- [ ] Render rests and overlapping notes.
- [ ] Define deterministic voice allocation.
- [ ] Add release tails without truncating the output unexpectedly.
- [ ] Add tests comparing rendered duration, frequency, and amplitude envelope.
- [ ] Add one example that creates a melody and writes a WAV file.

## Phase 4: DSP and Audio Analysis

- [x] Add Hann/rectangular/custom windows and document normalization choices.
- [x] Add FFT-based spectrum calculation.
- [x] Add raw-power spectrograms.
- [ ] Add calibrated periodograms.
- [ ] Add RMS, peak, crest factor, zero-crossing rate, and decibel helpers.
- [ ] Add DC-offset measurement and removal.
- [ ] Add FIR and IIR filtering through a stable adapter.
- [ ] Add resampling through a stable adapter.
- [ ] Add onset and silence detection only after core measurements are stable.
- [ ] Define whether analysis returns plain arrays or domain-aware result types.
- [ ] Add numerical tolerance tests and known reference signals.

## Phase 5: File and Interchange I/O

- [x] Start with WAV input and output.
- [ ] Preserve sample rate, channel count, and sample format on round trips.
- [ ] Decide whether `load`/`save` should use `FileIO.jl` or a direct API.
- [ ] Add MIDI import and export.
- [ ] Map external MIDI notes into the internal `NoteEvent` model.
- [ ] Preserve tempo, program, channel, and metadata where useful.
- [ ] Add FLAC, Ogg, Opus, and MP3 only as optional adapters.
- [ ] Test malformed files and truncated streams.
- [ ] Document native-library and codec requirements for each adapter.

## Phase 6: Streaming and Real-Time Audio

- [ ] Define `SampleSource` and `SampleSink` interfaces only when offline
      buffers are insufficient.
- [ ] Define block size, latency, underrun, and overrun semantics.
- [ ] Measure allocations inside the audio callback path.
- [ ] Add PortAudio playback and recording as an optional integration.
- [ ] Add a safe offline fallback for every real-time example.
- [ ] Ensure device code is not loaded by the core package import.
- [ ] Add explicit resource cleanup and `do`-block examples.
- [ ] Document platform-specific setup for Linux, macOS, and Windows.

## Phase 7: Higher-Level Music Tools

- [ ] Add quantization and humanization.
- [ ] Add chord progression helpers.
- [ ] Add rhythm and pattern combinators.
- [ ] Add MIDI performance analysis.
- [ ] Add spectral feature extraction where there is a concrete use case.
- [ ] Add composition helpers only after the lower-level event model is stable.
- [ ] Consider separate packages if symbolic music grows independently from DSP.

## Possibility Map And Parking Lot

This section records plausible future directions without promising that all of
them belong in the package. An item should move into the recommended order only
when there is a concrete use case, a stable API idea, and an acceptable cost in
dependencies and maintenance.

### Audio Semantics And Correctness

- [ ] Define interleaved versus planar sample storage at every I/O boundary.
- [ ] Define channel layouts beyond mono and stereo, including surround labels.
- [ ] Define sample format conversion for integer PCM, fixed point, and float.
- [ ] Define headroom and behavior for values outside `[-1, 1]`.
- [ ] Define NaN, infinity, empty-buffer, and zero-length behavior.
- [ ] Define phase, frame origin, inclusive/exclusive time ranges, and rounding.
- [ ] Define dB reference conventions for amplitude, power, and full scale.
- [ ] Define pan laws and stereo-width semantics.
- [ ] Define clock and sample-rate metadata for recorded or streamed material.
- [ ] Add loudness measurements such as LUFS and true peak if needed.
- [ ] Add channel alignment and latency metadata for multitrack material.

### Advanced DSP

- [ ] Add STFT and inverse STFT with documented padding and overlap rules.
- [ ] Add convolution and convolution reverb.
- [ ] Add equalizers, shelving filters, and parametric filter helpers.
- [ ] Add delay lines, echoes, chorus, flanger, and phaser effects.
- [ ] Add compressors, limiters, gates, expanders, and transient shaping.
- [ ] Add pitch shifting and time stretching.
- [ ] Add phase vocoder tools.
- [ ] Add alias-reduced oscillator and oversampling strategies.
- [ ] Add multirate processing and polyphase filter banks.
- [ ] Add wavelet or constant-Q analysis if a real use case appears.
- [ ] Add numerical stability guidance for long-running filters and feedback.

### Audio Analysis And Machine Learning

- [ ] Add fundamental-frequency and pitch tracking.
- [ ] Add onset, beat, tempo, and downbeat detection.
- [ ] Add chroma, constant-Q, spectral centroid, rolloff, flux, and MFCCs.
- [ ] Add note or chord recognition experiments.
- [ ] Add voice activity and silence classification.
- [ ] Add source separation or stem-analysis experiments.
- [ ] Add audio fingerprinting or similarity search.
- [ ] Add embedding/model adapters without making machine learning a core
      dependency.
- [ ] Define feature timestamps, window centers, padding, and confidence scores.
- [ ] Add reproducible datasets and reference clips for analysis evaluation.

### Music Theory, Tuning, And Notation

- [ ] Support tunings beyond twelve-tone equal temperament.
- [ ] Support just intonation, alternate temperaments, and arbitrary cents.
- [ ] Separate pitch identity, spelling, and sounding frequency.
- [ ] Support microtonal accidentals and pitch bends.
- [ ] Add phrase, articulation, dynamics, ornaments, and expressive markings.
- [ ] Add richer meter, tuplets, swing, polyrhythm, and rubato.
- [ ] Add repeated sections, cues, and score navigation.
- [ ] Evaluate MusicXML, ABC notation, and LilyPond interchange.
- [ ] Evaluate MIDI 2.0, MPE, controller curves, program changes, and SysEx.
- [ ] Define how notation preserves information that MIDI cannot represent.

### Instruments And Sound Design

- [ ] Add subtractive, additive, FM, AM, and wavetable instruments.
- [ ] Add physical-model or waveguide experiments.
- [ ] Add granular synthesis and sample playback.
- [ ] Add samplers with loop points, root notes, and velocity layers.
- [ ] Add modulation sources, LFOs, and parameter automation.
- [ ] Add buses, sends, returns, and effect chains.
- [ ] Define an instrument interface that can render offline and in blocks.
- [ ] Define preset serialization and versioning.
- [ ] Add deterministic seed handling for procedural instruments.
- [ ] Keep instrument implementations separate from the symbolic score model.

### Composition And Interaction

- [ ] Add lazy or streaming event patterns for long compositions.
- [ ] Add pattern transformations such as repeat, rotate, mirror, and stretch.
- [ ] Add generative rhythm and melody helpers.
- [ ] Add constraint-based or rule-based composition experiments.
- [ ] Add live-coding-friendly APIs and concise constructors.
- [ ] Add notebook examples with waveform and spectrogram displays.
- [ ] Add interactive piano-roll or score visualization if useful.
- [ ] Add reproducible random composition seeds.
- [ ] Define serialization for scores, patterns, and project metadata.

### Interoperability And Production Audio

- [ ] Preserve common metadata such as artist, title, album, markers, and cues.
- [ ] Support broadcast-oriented WAV metadata when required.
- [ ] Add streaming readers and writers for non-seekable sources.
- [ ] Add format probing and clear unsupported-format errors.
- [ ] Add optional FLAC, Ogg, Opus, and MP3 adapters.
- [ ] Evaluate JACK, ALSA, PipeWire, CoreAudio, and WASAPI device paths.
- [ ] Evaluate plugin hosting or export paths such as LV2, VST, or CLAP only
      if the package becomes a production-audio tool.
- [ ] Define import/export behavior for DAW project data if needed.
- [ ] Add network audio or OSC integration only for a concrete installation.

### Real-Time Reliability

- [ ] Define a no-allocation callback subset of the API.
- [ ] Define thread-safety and ownership rules for audio buffers.
- [ ] Add lock-free or bounded queues for control messages where needed.
- [ ] Handle device clock drift and sample-rate mismatch.
- [ ] Define underrun, overrun, cancellation, and shutdown behavior.
- [ ] Add latency measurement and round-trip latency tests.
- [ ] Add full-duplex input/output examples.
- [ ] Add graceful degradation when a device disappears.
- [ ] Document which operations are forbidden on the audio callback thread.

### Performance And Deployment

- [ ] Add benchmarks for allocation, throughput, latency, and memory use.
- [ ] Profile generated code for common sample types and channel counts.
- [ ] Evaluate SIMD and multithreading only after measuring a bottleneck.
- [ ] Define chunked processing for audio longer than available memory.
- [ ] Add caching for repeated spectra, wavetables, and impulse responses.
- [ ] Evaluate GPU processing only for workloads that justify transfer costs.
- [ ] Test package behavior in a clean Julia environment.
- [ ] Consider sysimage or precompile improvements only after the API settles.
- [ ] Document reproducible environments for examples and rendered assets.

### Testing And Quality

- [ ] Add property tests for duration, channel count, and sample-rate invariants.
- [ ] Add golden-file tests for known WAV, MIDI, and analysis results.
- [ ] Add round-trip tests for every supported interchange format.
- [ ] Add malformed-input and fuzz tests at file boundaries.
- [ ] Add cross-platform CI for supported Julia versions.
- [ ] Add allocation and latency regression tests for realtime code.
- [ ] Add perceptual listening tests for synthesis and DSP changes.
- [ ] Track numerical tolerances and reference implementation versions.
- [ ] Check dependency licenses and transitive native-library obligations.
- [ ] Add changelog, deprecation policy, and semantic-versioning rules.

### Package Ecosystem And Maintenance

- [ ] Decide whether the project should eventually split into core, DSP,
      music, I/O, and realtime packages.
- [ ] Define extension boundaries so optional dependencies stay optional.
- [ ] Define public versus experimental APIs.
- [ ] Add deprecation and migration notes when representations change.
- [ ] Add issue templates for bugs, feature requests, and design proposals.
- [ ] Record major API decisions in short design notes.
- [ ] Track upstream compatibility for audio and MIDI dependencies.
- [ ] Decide whether generated test audio and example assets may be committed.
- [ ] Define contribution, attribution, and citation requirements if public.

### Explicit Non-Goals To Revisit

- [ ] Do not become a full DAW unless the project direction changes.
- [ ] Do not promise sample-accurate realtime behavior without dedicated tests.
- [ ] Do not implement every codec in the core package.
- [ ] Do not duplicate mature DSP or MIDI packages without a demonstrated gap.
- [ ] Do not make plotting, machine learning, or device access mandatory.
- [ ] Do not support every music-notation tradition in the first release.
- [ ] Revisit these non-goals when actual projects expose a missing capability.

## External Dependency Plan

Dependencies are grouped by when they should enter the project. Do not add the
entire list to the initial environment.

### Julia Standard Libraries

- [ ] `LinearAlgebra`: vector and matrix operations.
- [ ] `Statistics`: common signal statistics.
- [ ] `Random`: deterministic noise and test fixtures.
- [ ] `Dates`: use only for file or recording metadata if needed.
- [ ] `Test`: test suite support.

### First-Wave Third-Party Candidates

- [x] `FFTW.jl`: third-party FFT library, used for STFT (not a Julia stdlib).

- [ ] `DSP.jl`: filters, windows, convolution, periodograms, spectrograms,
      and resampling. Candidate for Phase 4, not necessarily a Phase 1
      dependency.
- [ ] `MIDI.jl`: MIDI file parsing and writing. Candidate for Phase 5.
- [ ] `WAV.jl`: simple pure-Julia WAV read/write and playback. Candidate for
      the first I/O adapter.
- [ ] `FileIO.jl`: common `load` and `save` dispatch. Add only if multiple
      file-format adapters justify it.

### Audio Buffer and Streaming Candidates

- [ ] `SampledSignals.jl`: sample-rate-aware buffers and source/sink streams.
      Evaluate before designing `AudioBuffer`; it may be an integration target
      or a dependency rather than something to duplicate.
- [ ] `PortAudio.jl`: cross-platform audio-device input and output. Defer to
      Phase 6; it integrates with `SampledSignals.jl` and native PortAudio.
- [ ] `LibSndFile.jl`: broader file-format support and streaming I/O. Compare
      it with `WAV.jl` before choosing a first file backend.
- [ ] `FixedPointNumbers.jl`: precise PCM sample representations for file and
      device boundaries. Keep it out of the core unless required.
- [ ] `Unitful.jl`: typed seconds, hertz, decibels, and related quantities.
      Evaluate carefully because it improves correctness but increases API
      and type complexity.

### Music and Codec Candidates

- [ ] `MusicManipulations.jl`: quantization, transposition, humanization, and
      music-performance analysis. Evaluate after the internal event model.
- [ ] `Opus.jl`: optional Opus codec integration. Treat as experimental until
      maintenance and current Julia compatibility are verified.
- [ ] `MP3.jl`: do not adopt initially; its upstream repository is explicitly
      marked unmaintained. Prefer an external command or a maintained adapter
      if MP3 support becomes necessary.

### Development and Documentation Dependencies

- [ ] `Documenter.jl`: API documentation after public concepts stabilize.
- [ ] `Aqua.jl`: package quality checks.
- [ ] `BenchmarkTools.jl`: allocation and throughput benchmarks.
- [ ] `Plots.jl` or `Makie.jl`: optional examples and visualization only; do
      not make plotting a runtime dependency.

### Dependency Probe Result

Checked on 2026-09-09 with Julia 1.12.7 in a temporary environment:

- [x] `DSP` resolved as v0.8.6.
- [x] `MIDI` resolved as v2.7.0.
- [x] `WAV` resolved as v1.2.0.
- [x] `FileIO` resolved as v1.20.0.
- [x] `using DSP, MIDI, WAV, FileIO` completed successfully.
- [x] Test actual WAV write/read behavior against `AudioBuffer`.
- [ ] Test actual MIDI write/read behavior against `NoteEvent` and `Score`.
- [ ] Measure the precompilation and load-time cost before making any of these
      packages unconditional dependencies.

The first probe required a long precompilation step for FFTW and DSP dependencies.
The MIR implementation now imports these backends during package loading;
optional extensions remain a possible future optimization.

## Dependency Rules

- [ ] Keep Phase 1 free of external runtime dependencies where practical.
- [ ] Add one dependency at a time and record why it is needed.
- [ ] Prefer a thin adapter over exposing a dependency's types everywhere.
- [ ] Avoid simultaneously adopting overlapping audio-buffer abstractions.
- [ ] Keep device, codec, and plotting dependencies optional.
- [ ] Check license, maintenance activity, Julia compatibility, and native
      library requirements before adoption.
- [ ] Add package extensions when an optional integration can remain unloaded
      from the core path.
- [x] Record dependency ranges in `Project.toml`; ignore the local library manifest.

## Suggested Initial Dependency Experiment

- [x] Create a temporary environment outside the package.
- [ ] Add `DSP`, `MIDI`, `WAV`, and `FileIO` one at a time.
- [x] Verify each package on Julia 1.12.7.
- [ ] Prototype one WAV round trip and one MIDI round trip.
- [ ] Prototype a DSP filter and a spectrum calculation.
- [ ] Compare `WAV.jl` against `LibSndFile.jl` before selecting the first I/O
      backend.
- [ ] Evaluate `SampledSignals.jl` before finalizing `AudioBuffer`.
- [ ] Do not install `PortAudio.jl` until a working offline audio path exists.

## Definition Of A Useful First Release

- [x] Generate a tone and a short melody.
- [x] Mix and normalize audio buffers.
- [ ] Render a score with a simple oscillator and envelope.
- [x] Write and read WAV files.
- [ ] Read and write a basic MIDI file.
- [x] Compute a spectrum and a spectrogram.
- [x] Pass tests for sample-rate, duration, channel, and timing behavior.
- [x] Explain the public API in a concise README.

## Current Recommended Order

1. [x] Lock the initial package name and representation decisions.
2. [x] Create the minimal Julia package skeleton.
3. [x] Implement and test `AudioBuffer`.
4. [x] Implement tone generation and basic transforms.
5. [x] Add WAV I/O using the selected backend.
6. [x] Implement pitch, note, tempo, and `NoteEvent`.
7. [x] Render a score into an audio buffer.
8. [ ] Add `DSP.jl` analysis and filtering.
9. [ ] Add `MIDI.jl` interchange.
10. [ ] Evaluate `SampledSignals.jl` and `PortAudio.jl` for streaming.
