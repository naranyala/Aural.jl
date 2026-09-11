# Changelog

## Unreleased

- Added shared `AnalysisConfig` framing and validated analysis result metadata.
- Added bounded `eachframe` iteration and reusable STFT scratch storage.
- Added bandwidth, rolloff, flatness, zero-crossing, crest, DC, dB, and
  autocorrelation pitch features.
- Added onset local thresholds, latency compensation, strengths, timing error,
  tempo estimation, and separate beat annotations.
- Added Julia 1.10/1.12/nightly CI, an analysis summary example, and a small
  performance smoke benchmark.

## 0.1.0

Initial offline audio, symbolic music, synthesis, WAV, analysis, and event
evaluation toolkit.
