# Symbolic music and synthesis

## Pitch, notes, and frequency

`Pitch` stores a finite MIDI-number value as a `Float64`. `Note` wraps a pitch
and can be constructed from either a MIDI number or a note name, octave, and
integer accidental:

```julia
middle_c = Note(:C, 4)
c_sharp = Note(:C, 4; accidental=1)
same_pitch = Note(:D, 4; accidental=-1)

midi(middle_c)             # 60.0
frequency(Note(:A, 4))     # 440.0
frequency(middle_c)        # approximately 261.626 Hz
frequency(middle_c; tuning=432)
```

The supported note names are `:C`, `:D`, `:E`, `:F`, `:G`, `:A`, and `:B`.
The octave follows MIDI semantics: `Note(:C, 4)` is MIDI 60. Accidentals are
integer semitone offsets and are not normalized or respelled.

Frequency uses equal temperament:

```text
f = tuning × 2^((midi - 69) / 12)
```

The tuning must be finite and positive.

## Tempo and beat time

`Tempo` stores positive beats per minute. `beats_to_seconds` performs the
constant-tempo conversion:

```julia
tempo = Tempo(120)
beats_to_seconds(1, tempo)  # 0.5
```

Beats and seconds are intentionally separate. `NoteEvent` uses beats for its
start and duration, while `EventAnnotations` and audio analysis use seconds.

## Events and scores

```julia
event = NoteEvent(Note(:C, 4), 0, 1; velocity=0.75, channel=1)
score = Score([
    event,
    NoteEvent(Note(:E, 4), 1, 1),
]; tempo=Tempo(120))
```

`NoteEvent` validates non-negative finite start beats, positive finite duration,
velocity in `[0, 1]`, and MIDI channel in `1:16`. `Score` copies and sorts its
events by `start_beat`; iterating a score yields the ordered events.

There are two deliberately different duration meanings:

- `duration_beats(event)` returns the event's own duration;
- `duration_beats(score)` returns the latest event end,
  `start_beat + duration_beats(event)`, or `0.0` for an empty score.

This distinction matters when the first event starts after beat zero.

## Oscillators and noise

`oscillator` generates a single-channel Float32 waveform. The supported shapes
are `:sine`, `:cosine`, `:saw`, `:square`, and `:triangle`:

```julia
sine = oscillator(440, 1; samplerate=48_000, shape=:sine)
square = oscillator(440, 1; samplerate=48_000, shape=:square, amplitude=0.2)
saw = oscillator(220, 1; samplerate=48_000, shape=:saw)
```

Frequency is finite and non-negative, duration is finite and non-negative,
sample rate is positive, and amplitude and phase must be finite. Phase is used
by the sine, cosine, and square implementations; the current saw and triangle
implementations derive their ramps from the unshifted frequency angle.
Waveforms are direct mathematical shapes; there is no band-limiting, so
high-frequency discontinuities can alias.

`noise` generates monophonic Float32 white noise:

```julia
texture = noise(0.5; samplerate=48_000, amplitude=0.1)
```

It uses Julia's default random source and is therefore not a deterministic
fixture unless the caller controls the random seed.

`tone` is the sine-specific convenience wrapper:

```julia
tone_audio = tone(440, 1; samplerate=48_000, amplitude=0.2, phase=0)
```

`tone` creates a one-channel `AudioBuffer` of Float32 samples. The sample at
frame `n` uses time `(n - 1) / samplerate` and phase
`phase + 2π * frequency * time`. Frequency is finite and non-negative;
duration is finite and non-negative; sample rate is positive. Frame count is
`round(duration * samplerate)`.

Frame count is `round(duration * samplerate)` for all oscillator helpers.

## Ramps and ADSR envelopes

`linear_ramp` and `exponential_ramp` produce one-channel envelope buffers:

```julia
linear = linear_ramp(0, 1, 0.1; samplerate=48_000)
exponential = exponential_ramp(1, 0.1, 0.1; samplerate=48_000)
```

Ramps span their full duration. A one-frame ramp uses its start value. The
exponential form requires strictly positive start and end values.

`ADSR` stores attack, decay, sustain level, and release in seconds:

```julia
shape = ADSR(0.01, 0.02, 0.6, 0.03)
sine_short = oscillator(440, 0.25; samplerate=48_000, shape=:sine)
env = envelope(shape, 0.25; samplerate=48_000)
shaped = apply_envelope(sine_short, env)
```

Attack, decay, sustain, and release are rendered as a single-channel buffer.
The sustain phase fills the remaining duration. If attack + decay + release is
longer than the requested duration, those phases are scaled proportionally so
the envelope still has exactly the requested frame count. `apply_envelope`
requires matching frame counts but does not require matching channel counts;
the underlying array broadcast follows Julia's array-shape rules.

`note` combines an oscillator and an optional ADSR envelope:

```julia
shaped_note = note(440, 0.25; samplerate=48_000, shape=:sine, adsr=shape)
```

With `adsr=nothing`, it is equivalent to `oscillator` with the same waveform
arguments.

## Rendering a score

```julia
score = Score([
    NoteEvent(Note(:C, 4), 0, 1),
    NoteEvent(Note(:G, 4), 0, 1), # overlaps and is mixed additively
    NoteEvent(Note(:E, 4), 1, 2),
]; tempo=Tempo(120))

rendered = render(score; samplerate=48_000, amplitude=0.2)
```

Rendering converts each event's start and duration from beats to seconds,
generates a sine voice at the note frequency, scales it by
`amplitude * event.velocity`, and mixes it into a mono output. The output ends
at the latest event end. Overlapping voices add together; there is no automatic
clipping or envelope. An empty score renders to zero-frame audio.

The renderer's `amplitude` must be finite but is not otherwise clamped. A
negative value is therefore allowed and reverses the generated waveform.

Future synthesis work is tracked in [`../TODOS.md`](../TODOS.md), including
integration of custom instruments/envelopes into score rendering, rests,
release tails, deterministic voice allocation, and richer polyphonic behavior.
