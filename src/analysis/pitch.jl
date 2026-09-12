function _pitch_frame(segment, samplerate::Int, fmin::Real, fmax::Real,
                      confidence_threshold::Real)
    n = length(segment)
    n < 3 && return 0.0, 0.0
    centered = Float64.(segment)
    centered .-= sum(centered) / n
    energy = sum(abs2, centered)
    energy == 0 && return 0.0, 0.0

    lag_min = clamp(floor(Int, samplerate / fmax), 1, n - 1)
    lag_max = clamp(ceil(Int, samplerate / fmin), 1, n - 1)
    lag_min <= lag_max || return 0.0, 0.0
    # FFT autocorrelation reduces the cost of scanning candidate periods while
    # retaining the normalized correlation used as a voicing confidence score.
    padded = zeros(Float64, 2n)
    padded[1:n] .= centered
    autocorrelation = FFTW.irfft(abs2.(FFTW.rfft(padded)), 2n)
    correlations = Vector{Float64}(undef, lag_max - lag_min + 1)
    for lag in lag_min:lag_max
        correlations[lag - lag_min + 1] = autocorrelation[lag + 1] / energy
    end
    best_index = argmax(correlations)
    best_lag = lag_min + best_index - 1
    best_confidence = clamp(correlations[best_index], 0.0, 1.0)
    best_confidence >= confidence_threshold || return 0.0, best_confidence

    refined_lag = Float64(best_lag)
    if best_index > 1 && best_index < length(correlations)
        left = correlations[best_index - 1]
        center = correlations[best_index]
        right = correlations[best_index + 1]
        denominator = left - 2center + right
        denominator != 0 && (refined_lag += 0.5 * (left - right) / denominator)
    end
    return samplerate / refined_lag, best_confidence
end

function pitch_track(audio::AudioBuffer, settings::AnalysisConfig;
                     fmin::Real=50.0, fmax::Real=2_000.0,
                     confidence_threshold::Real=0.3)
    isfinite(fmin) && 0 < fmin < fmax <= samplerate(audio) / 2 ||
        throw(ArgumentError("invalid pitch frequency range"))
    isfinite(confidence_threshold) && 0 <= confidence_threshold <= 1 ||
        throw(ArgumentError("confidence_threshold must be in [0, 1]"))
    grid = _grid(audio, settings)
    pitches = Vector{Float64}(undef, length(grid))
    confidences = Vector{Float64}(undef, length(grid))
    for (index, segment) in enumerate(eachframe(audio, grid; channel=settings.channel))
        pitches[index], confidences[index] =
            _pitch_frame(segment, samplerate(audio), fmin, fmax, confidence_threshold)
    end
    return FeatureTrack(pitches, frame_times(grid, samplerate(audio)), :pitch;
                        confidence=confidences,
                        metadata=_analysis_metadata(audio, settings))
end

function pitch_track(audio::AudioBuffer; fmin::Real=50.0, fmax::Real=2_000.0,
                     confidence_threshold::Real=0.3, window_size::Integer=2_048,
                     hop_size::Integer=512, channel::Integer=1, pad::Bool=false)
    return pitch_track(audio, AnalysisConfig(window_size=window_size,
                                              hop_size=hop_size,
                                              channel=channel, pad=pad);
                       fmin=fmin, fmax=fmax,
                       confidence_threshold=confidence_threshold)
end
