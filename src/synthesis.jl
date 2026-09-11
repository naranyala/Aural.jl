"""Offline signal generation, envelopes, and score rendering."""

# ---------------------------------------------------------------------------
# Oscillators
# ---------------------------------------------------------------------------

const OSCILLATOR_SHAPES = Set([:sine, :cosine, :saw, :square, :triangle])

"""Generate a single-channel waveform buffer.

`shape` selects among `:sine`, `:cosine`, `:saw`, `:square`, and `:triangle`.
Phase is in radians and applied only to periodic oscillators.
"""
function oscillator(frequency_hz::Real, duration_seconds::Real;
                    samplerate::Integer=48_000, amplitude::Real=1.0,
                    phase::Real=0.0, shape::Symbol=:sine)
    shape in OSCILLATOR_SHAPES ||
        throw(ArgumentError("unknown shape :$shape; use one of $OSCILLATOR_SHAPES"))
    isfinite(frequency_hz) && frequency_hz >= 0 ||
        throw(ArgumentError("frequency must be finite and non-negative"))
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    isfinite(amplitude) || throw(ArgumentError("amplitude must be finite"))
    isfinite(phase) || throw(ArgumentError("phase must be finite"))

    # Sample zero is evaluated at t=0, so phase is independent of the
    # requested duration and the generated buffer has exactly the rounded
    # duration in frames.
    frames = round(Int, duration_seconds * samplerate)
    data = Matrix{Float32}(undef, 1, frames)
    for frame in 1:frames
        t = (frame - 1) / samplerate
        data[1, frame] = Float32(amplitude * _osc(phase, 2pi * frequency_hz * t, shape))
    end
    return AudioBuffer(data, samplerate)
end

@inline function _osc(phase::Real, theta::Real, shape::Symbol)
    if shape === :sine
        sin(phase + theta)
    elseif shape === :cosine
        cos(phase + theta)
    elseif shape === :saw
        # Ramp from -1 to +1
        2.0 * (theta / 2pi - floor(theta / 2pi + 0.5))
    elseif shape === :square
        # +1 or -1, bias positive at zero crossings
        s = sin(phase + theta)
        s >= 0 ? 1.0 : -1.0
    else # :triangle
        # Abs of saw, scaled to [-1, 1]
        x = 2.0 * (theta / 2pi - floor(theta / 2pi + 0.5))
        2.0 * abs(x) - 1.0
    end
end

"""Sine oscillator. Alias for `oscillator(...; shape=:sine)`."""
function tone(frequency_hz::Real, duration_seconds::Real;
              samplerate::Integer=48_000, amplitude::Real=1.0, phase::Real=0.0)
    oscillator(frequency_hz, duration_seconds;
               samplerate=samplerate, amplitude=amplitude, phase=phase, shape=:sine)
end

# ---------------------------------------------------------------------------
# White noise
# ---------------------------------------------------------------------------

"""Generate monophonic white noise."""
function noise(duration_seconds::Real;
               samplerate::Integer=48_000, amplitude::Real=1.0)
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    isfinite(amplitude) || throw(ArgumentError("amplitude must be finite"))

    # Keep the random source at the synthesis boundary; callers can control
    # reproducibility with Julia's normal random-number seeding tools.
    frames = round(Int, duration_seconds * samplerate)
    data = randn(Float32, 1, frames) .* Float32(amplitude)
    return AudioBuffer(data, samplerate)
end

# ---------------------------------------------------------------------------
# Envelope ramps
# ---------------------------------------------------------------------------

"""Linear ramp from `start_val` to `end_val` over `duration_seconds`."""
function linear_ramp(start_val::Real, end_val::Real, duration_seconds::Real;
                     samplerate::Integer=48_000)
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))

    frames = round(Int, duration_seconds * samplerate)
    data = Matrix{Float32}(undef, 1, frames)
    for frame in 1:frames
        t = frames <= 1 ? 0.0 : (frame - 1) / (frames - 1)
        data[1, frame] = Float32(start_val + t * (end_val - start_val))
    end
    return AudioBuffer(data, samplerate)
end

"""Exponential ramp from `start_val` to `end_val` over `duration_seconds`.

Both values must be positive. The curve follows `start * (end/start)^t`.
"""
function exponential_ramp(start_val::Real, end_val::Real, duration_seconds::Real;
                          samplerate::Integer=48_000)
    start_val > 0 || throw(ArgumentError("start_val must be positive"))
    end_val > 0 || throw(ArgumentError("end_val must be positive"))
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))

    frames = round(Int, duration_seconds * samplerate)
    data = Matrix{Float32}(undef, 1, frames)
    ratio = log(Float64(end_val)) - log(Float64(start_val))
    for frame in 1:frames
        t = frames <= 1 ? 0.0 : (frame - 1) / (frames - 1)
        data[1, frame] = Float32(exp(log(start_val) + t * ratio))
    end
    return AudioBuffer(data, samplerate)
end

# ---------------------------------------------------------------------------
# ADSR envelope
# ---------------------------------------------------------------------------

"""Attack–decay–sustain–release envelope shape.

All times are in seconds. `sustain_level` is a amplitude multiplier in [0, 1].
"""
struct ADSR
    attack::Float64
    decay::Float64
    sustain_level::Float64
    release::Float64

    function ADSR(attack::Real, decay::Real, sustain_level::Real, release::Real)
        attack >= 0 || throw(ArgumentError("attack must be non-negative"))
        decay >= 0 || throw(ArgumentError("decay must be non-negative"))
        release >= 0 || throw(ArgumentError("release must be non-negative"))
        0 <= sustain_level <= 1 ||
            throw(ArgumentError("sustain_level must be in [0, 1]"))
        new(Float64(attack), Float64(decay), Float64(sustain_level), Float64(release))
    end
end

"""Generate an ADSR envelope as a single-channel AudioBuffer.

The sustain phase fills whatever time remains after attack, decay, and release.
If the sum of attack + decay + release exceeds `duration_seconds`, phases are
scaled proportionally so the envelope always spans exactly `duration_seconds`.
"""
function envelope(adsr::ADSR, duration_seconds::Real;
                  samplerate::Integer=48_000)
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))

    # When the requested note is shorter than its envelope phases, compress
    # attack/decay/release together instead of silently dropping a phase.
    dur = Float64(duration_seconds)
    total_phase = adsr.attack + adsr.decay + adsr.release
    scale = total_phase > dur ? dur / total_phase : 1.0
    att = adsr.attack * scale
    dec = adsr.decay * scale
    rel = adsr.release * scale
    sus = max(dur - att - dec - rel, 0.0)

    frames = round(Int, dur * samplerate)
    data = Matrix{Float32}(undef, 1, frames)
    att_frames = round(Int, att * samplerate)
    dec_frames = round(Int, dec * samplerate)
    sus_frames = round(Int, sus * samplerate)
    # Derive release from the remainder so rounding cannot make the phases
    # exceed the exact output length.
    rel_frames = frames - att_frames - dec_frames - sus_frames

    idx = 0
    # Attack: 0 → 1
    for i in 1:att_frames
        idx += 1
        data[1, idx] = att_frames <= 1 ? 1.0f0 : Float32((i - 1) / (att_frames - 1))
    end
    # Decay: 1 → sustain_level
    for i in 1:dec_frames
        idx += 1
        t = dec_frames <= 1 ? 1.0 : (i - 1) / (dec_frames - 1)
        data[1, idx] = Float32(1.0 + t * (adsr.sustain_level - 1.0))
    end
    # Sustain: hold at sustain_level
    for _ in 1:sus_frames
        idx += 1
        data[1, idx] = Float32(adsr.sustain_level)
    end
    # Release: sustain_level → 0
    for i in 1:rel_frames
        idx += 1
        t = rel_frames <= 1 ? 1.0 : (i - 1) / (rel_frames - 1)
        data[1, idx] = Float32(adsr.sustain_level * (1.0 - t))
    end

    return AudioBuffer(data, samplerate)
end

"""Multiply an audio buffer by an envelope buffer element-wise."""
function apply_envelope(audio::AudioBuffer, env::AudioBuffer)
    nframes(audio) == nframes(env) ||
        throw(ArgumentError("audio and envelope must have the same number of frames"))
    # Broadcasting preserves the channel-major layout and lets a one-channel
    # envelope scale a matching one-channel signal without special casing.
    return AudioBuffer(audio.samples .* env.samples, samplerate(audio))
end

# ---------------------------------------------------------------------------
# Combined instrument: oscillator + envelope
# ---------------------------------------------------------------------------

"""Generate a note with oscillator shape and optional ADSR envelope."""
function note(frequency_hz::Real, duration_seconds::Real;
              samplerate::Integer=48_000, amplitude::Real=1.0,
              shape::Symbol=:sine, adsr::Union{Nothing,ADSR}=nothing)
    osc = oscillator(frequency_hz, duration_seconds;
                     samplerate=samplerate, amplitude=amplitude, shape=shape)
    adsr === nothing && return osc
    env = envelope(adsr, duration_seconds; samplerate=samplerate)
    return apply_envelope(osc, env)
end

# ---------------------------------------------------------------------------
# Score rendering
# ---------------------------------------------------------------------------

"""Render a constant-tempo Score to an AudioBuffer with a sine voice."""
function render(score::Score; samplerate::Integer=48_000, amplitude::Real=0.2)
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    isfinite(amplitude) || throw(ArgumentError("amplitude must be finite"))

    # Rendering is intentionally simple and deterministic: each event becomes
    # an independent voice, then voices are accumulated on a shared timeline.
    total_seconds = beats_to_seconds(duration_beats(score), score.tempo)
    output = silence(total_seconds; samplerate=samplerate, channels=1, T=Float32)
    for event in score
        start_seconds = beats_to_seconds(event.start_beat, score.tempo)
        note_seconds = beats_to_seconds(event.duration_beats, score.tempo)
        voice = tone(frequency(event.note), note_seconds;
                     samplerate=samplerate,
                     amplitude=amplitude * event.velocity)
        output = mix(output, voice; offset=start_seconds)
    end
    return output
end
