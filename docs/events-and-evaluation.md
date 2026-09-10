# Events and evaluation

## Point annotations

`EventAnnotations` represents point events in seconds:

```julia
onsets = EventAnnotations([0.75, 0.25, 0.5]; kind=:onset)
times(onsets)  # [0.25, 0.5, 0.75]
```

The input is copied and sorted. Times must be finite and non-negative. The
supported kinds are `:onset` and `:beat`; duplicate timestamps are retained as
distinct events. These annotations are independent of beat-based
`NoteEvent`s.

## Onset detection from a feature track

```julia
flux = spectral_flux(spectrogram(audio; window_size=1_024, hop_size=256,
                                 pad=false))
estimated = detect_onsets(flux; threshold=0.2, min_interval=0.05)
```

The feature-track detector requires a track named `:spectral_flux`. Flux values
must be finite and non-negative, and timestamps must be finite, non-negative,
and strictly increasing.

Detection works as follows:

1. Compute `cutoff = threshold * maximum(flux)`.
2. Keep values strictly above the cutoff that are greater than the previous
   bin and at least as large as the next bin.
3. Rank candidate peaks by descending flux strength, with earlier timestamps
   breaking ties.
4. Keep a candidate only when it is at least `min_interval` seconds from every
   selected event.

The first bin of a plateau wins because a candidate must be strictly greater
than its predecessor and only needs to be greater than or equal to its
successor. `threshold` is a fraction in `[0, 1]`; `min_interval` is finite and
non-negative. The returned timestamps are the original feature timestamps.

## Onset detection from audio

```julia
estimated = detect_onsets(audio; window_size=1_024, hop_size=256)
```

The audio method computes an STFT, converts it to a spectrogram, computes
spectral flux, and applies the feature-track detector. It defaults to
`pad=false`; remaining keywords are passed to `stft`, so `window_size`,
`hop_size`, `nfft`, `channel`, and `window` can be supplied. Returned events
whose frame time is at or beyond the recording duration are removed.

This is an offline baseline. It uses frame centers, does not backtrack peaks or
estimate sub-frame timing, and may miss an attack that occurs in the first
analysis frame. It is not a streaming detector.

## Event scoring

```julia
reference = EventAnnotations([0.25, 0.5, 0.75])
estimated = EventAnnotations([0.26, 0.9])
result = evaluate_events(reference, estimated; tolerance=0.05)

result.true_positives
result.false_positives
result.false_negatives
result.precision
result.recall
result.f1
```

The tolerance is in seconds and is inclusive. Events are matched one-to-one;
duplicates cannot reuse a match. For a uniform tolerance, the implementation's
earliest-first scan maximizes the number of matches, but it does not minimize
total timing error among equally large matchings. Reference and estimated
annotations must have the same kind.

Precision, recall, and F1 use zero when their relevant denominator is empty;
F1 is also zero when both event sequences are empty. This is micro-level
point-event scoring, not interval overlap, beat continuity, transcription
accuracy, or corpus-level evaluation.

Broader annotations, adaptive thresholds, beat tracking, dataset manifests,
and benchmark aggregation are future work listed in [`../TODOS.md`](../TODOS.md).
