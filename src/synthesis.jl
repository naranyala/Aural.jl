"""Simple offline signal generation and score rendering."""

function tone(frequency_hz::Real, duration_seconds::Real;
              samplerate::Integer=48_000, amplitude::Real=1.0, phase::Real=0.0)
    isfinite(frequency_hz) && frequency_hz >= 0 ||
        throw(ArgumentError("frequency must be finite and non-negative"))
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    isfinite(amplitude) || throw(ArgumentError("amplitude must be finite"))
    isfinite(phase) || throw(ArgumentError("phase must be finite"))

    frames = round(Int, duration_seconds * samplerate)
    data = Matrix{Float32}(undef, 1, frames)
    for frame in 1:frames
        time = (frame - 1) / samplerate
        data[1, frame] = Float32(amplitude * sin(phase + 2pi * frequency_hz * time))
    end
    return AudioBuffer(data, samplerate)
end

function render(score::Score; samplerate::Integer=48_000, amplitude::Real=0.2)
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    isfinite(amplitude) || throw(ArgumentError("amplitude must be finite"))

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
