# Sampled audio

## `AudioBuffer`

`AudioBuffer` is the core sampled-audio container. Its samples are stored as a
`channels × frames` array, together with a positive integer sample rate.

```julia
audio = AudioBuffer(Float32[0, 0.5, -1, 0.25], 1_000)

size(audio)       # (1, 4)
nchannels(audio)  # 1
nframes(audio)    # 4
duration(audio)   # 0.004
```

A vector input is interpreted as one channel. A matrix input is already
expected to be in channels × frames order. At least one channel is required;
zero-frame audio is valid.

Useful accessors are:

- `samples(audio)` — the underlying sample array, without an implicit copy;
- `samplerate(audio)` — the sample rate;
- `nchannels(audio)` and `nframes(audio)` — dimensions;
- `duration(audio)` — `nframes / samplerate` in seconds;
- `channel(audio, i)` — a copied vector for channel `i`;
- `audio[i, j]` — indexing forwarded to the sample array.

The constructor preserves the input element type where possible. Generated
audio from `silence` and `tone` defaults to `Float32`, but transformations can
promote types when their inputs require it.

## Creating and changing channels

```julia
mono_audio = silence(1; samplerate=48_000)
stereo_audio = stereo(mono_audio)
left = channel(stereo_audio, 1)
joined = join_channels(mono_audio, mono_audio)
downmixed = mono(stereo_audio)
```

`mono` averages all channels. `stereo` preserves two-channel audio and
otherwise duplicates the mono downmix. `join_channels` concatenates channel
rows and requires every input to have the same sample rate and frame count.

## Generating and transforming samples

```julia
quiet = silence(0.5; samplerate=48_000, channels=2)
louder = gain(quiet, 2)
normalized = normalize(louder; target=0.9)
```

`silence` rounds `duration_seconds * samplerate` to the nearest integer frame
count. `gain` multiplies every sample. `normalize` scales the peak absolute
sample to `target`; a silent buffer is returned unchanged, and `target=0`
produces silence.

`trim` uses seconds and returns a copy:

```julia
part = trim(audio, 0.001, 0.003)
```

For nonempty intervals, the start is rounded down and the stop is rounded up
to sample cells, then clamped to the recording. Equal bounds always return a
zero-frame buffer. Bounds must satisfy `0 ≤ start ≤ stop` and be finite.

`mix` adds two buffers sample by sample:

```julia
delayed = mix(audio, audio; offset=0.002)
```

The offset is in seconds and is rounded to the nearest frame. The output is
long enough to contain both inputs. Sample rates and channel counts must
match; offsets must be finite and non-negative. Overlap is additive, so values
can exceed the nominal `[-1, 1]` range until the caller normalizes or otherwise
handles them.

## Invariants and failure modes

The following are rejected with `ArgumentError`:

- non-positive sample rates;
- a matrix with zero channels;
- invalid silence/tone durations or channel counts;
- incompatible sample rates or channel counts in `mix`;
- incompatible sample rates or frame counts in `join_channels`;
- negative or non-finite mix offsets.

There is no implicit clipping. The current package has no hard-clip or
soft-saturation operation; use a deliberate transform such as `normalize` or
write your own policy when a bounded signal is required.

## WAV input and output

```julia
write_audio("input.wav", audio)
loaded = read_audio("input.wav")
loaded64 = read_audio("input.wav"; T=Float64)
```

`read_audio` accepts mono and multichannel WAV data and converts it to
channels × frames. It defaults to `Float32`; `T` controls the in-memory sample
type. `write_audio` converts samples to `Float32` before passing them to
WAV.jl. The adapter currently does not promise source bit-depth or metadata
preservation, and it returns the output path.
