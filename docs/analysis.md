# Time-frequency analysis and MIR features

## Framing

`FrameGrid` describes analysis windows over a signal length:

```julia
grid = FrameGrid(5; window_size=4, hop_size=2, pad=true)
```

The grid starts at sample indices `1:hop_size:signal_frames` when `pad=true`.
When `pad=false`, it keeps only starts whose complete window fits:
`1:hop_size:(signal_frames - window_size + 1)`. A padded tail is filled with
zeros. Empty audio produces no frames.

```julia
audio = AudioBuffer(collect(1.0:5), 8)
frame(audio, grid)
# [1 3 5;
#  2 4 0;
#  3 5 0;
#  4 0 0]

frame_times(grid, 8)  # [1.5, 3.5, 5.5] / 8
```

Frames are `window_size × number_of_frames`. The default channel is channel 1;
pass `channel=` for another channel. `frame_times` marks the center of each
window using zero-based sample time. With padding, a frame center can fall
after the end of the original recording.

`window_size` must be positive, and `hop_size` must be in
`1:window_size`. `frame` also requires the grid's signal length to match the
audio buffer.

## STFT and spectrograms

```julia
transform = stft(audio; window_size=2_048, hop_size=512,
                 nfft=2_048, window=:hann, pad=true)
spec = spectrogram(transform)
```

`stft` applies the selected window to each frame and computes a one-sided real
FFT. The default window is `DSP.hann`; pass `nothing`, a length-matched vector,
or a function of the window size for a custom window. `nfft` may be larger
than `window_size` for right-side zero-padding, but not smaller.

The result has:

- `coefficients(transform)`: `ComplexF64`, bins × frames;
- `frequencies(transform)`: `0:floor(nfft / 2)` scaled by sample rate;
- `times(transform)`: frame-center times in seconds.

FFT coefficients are unnormalized one-sided real FFT coefficients. A
`Spectrogram` stores `abs2` of those coefficients in `power(spec)`. These are
squared magnitudes, not calibrated power spectral density estimates.

`spectrogram(audio; kwargs...)` is shorthand for `spectrogram(stft(audio;
kwargs...))`.

## Scalar feature tracks

Feature tracks contain one value per analysis frame and expose `values(track)`
and `times(track)`.

```julia
energy = rms(audio; window_size=2_048, hop_size=512, pad=false)
centroid = spectral_centroid(spec)
flux = spectral_flux(spec)
```

The current definitions are:

- `rms`: unwindowed samples, including zero padding, with the denominator fixed
  at `window_size`;
- `spectral_centroid`: power-weighted frequency in hertz, or zero for a silent
  spectrum;
- `spectral_flux`: the L2 norm of positive frame-to-frame magnitude increases,
  with zero for the first frame.

`rms` uses channel 1 by default and otherwise follows `FrameGrid` behavior.

## Chroma

```julia
chroma_features = chroma(spec; tuning=440.0)
```

`chroma` returns a `FeatureMatrix` with 12 rows in `C, C♯/D♭, ..., B` order.
Each positive-frequency FFT bin is assigned to its nearest equal-tempered
pitch class, its power is accumulated, and each frame is L1-normalized when
non-silent. The tuning reference must be finite and positive.

This is an FFT-bin baseline: it does not perform harmonic weighting, tuning
estimation, or chroma whitening.

## MFCC

```julia
cepstra = mfcc(spec; nfilters=40, ncoeffs=13)
```

`mfcc` returns coefficients × frames. Its fixed conventions are:

- HTK mel spacing between `fmin` and `fmax`;
- unit-peak triangular filters, without area normalization;
- natural-log filter-bank energies floored at `floor` (default `1e-10`);
- orthonormal DCT-II including coefficient 0.

There is no pre-emphasis, liftering, delta computation, or cepstral mean
normalization. `1 ≤ ncoeffs ≤ nfilters` and the frequency range must lie within
`0` to the Nyquist frequency.

## Feature containers and shape conventions

`FeatureTrack{T}` stores a vector, matching timestamps, and a symbolic `name`.
It supports `length`, indexing, `values`, and `times`.

`FeatureMatrix` stores a Float64 matrix, matching timestamps, and a symbolic
`name`. Its matrix rows represent features or coefficients; its columns
represent analysis frames. Use `values` and `times` to read it.

All default analysis functions select channel 1. Use `mono(audio)` before
analysis when downmixing is part of the intended pipeline.
