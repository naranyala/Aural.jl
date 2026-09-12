function rms(audio::AudioBuffer, settings::AnalysisConfig)
    grid = _grid(audio, settings)
    output = Vector{Float64}(undef, length(grid))
    source = @view audio.samples[settings.channel, :]
    for (index, start) in enumerate(grid.starts)
        available = min(settings.window_size, nframes(audio) - start + 1)
        sum_squares = 0.0
        if available > 0
            for offset in 0:(available - 1)
                sum_squares += abs2(Float64(source[start + offset]))
            end
        end
        # Use the configured window length as the denominator, so padded tail
        # frames measure their zero fill consistently with ordinary frames.
        output[index] = sqrt(sum_squares / settings.window_size)
    end
    return FeatureTrack(output, frame_times(grid, samplerate(audio)), :rms;
                        metadata=_analysis_metadata(audio, settings))
end

function rms(audio::AudioBuffer; window_size::Integer=2_048,
             hop_size::Integer=512, channel::Integer=1, pad::Bool=true)
    return rms(audio, AnalysisConfig(window_size=window_size, hop_size=hop_size,
                                     channel=channel, pad=pad))
end

function spectral_centroid(result::Spectrogram)
    centroids = Vector{Float64}(undef, size(result.power, 2))
    for column in axes(result.power, 2)
        spectrum = result.power[:, column]
        total_power = sum(spectrum)
        centroids[column] = total_power == 0 ? 0.0 :
            sum(result.frequencies .* spectrum) / total_power
    end
    return FeatureTrack(centroids, result.times, :spectral_centroid;
                        metadata=_track_metadata(result))
end

function spectral_flux(result::Spectrogram)
    flux = zeros(Float64, size(result.power, 2))
    # Half-wave rectification makes flux respond to newly appearing energy,
    # rather than canceling increases against decreases in another bin.
    magnitudes = sqrt.(result.power)
    for column in 2:size(magnitudes, 2)
        increase = max.(magnitudes[:, column] .- magnitudes[:, column - 1], 0)
        flux[column] = sqrt(sum(abs2, increase))
    end
    return FeatureTrack(flux, result.times, :spectral_flux; metadata=_track_metadata(result))
end

function spectral_bandwidth(result::Spectrogram)
    output = Vector{Float64}(undef, size(result.power, 2))
    centroids = values(spectral_centroid(result))
    for column in axes(result.power, 2)
        spectrum = result.power[:, column]
        total = sum(spectrum)
        output[column] = total == 0 ? 0.0 :
            sqrt(sum(spectrum .* (result.frequencies .- centroids[column]).^2) / total)
    end
    return FeatureTrack(output, result.times, :spectral_bandwidth;
                        metadata=_track_metadata(result))
end

function spectral_rolloff(result::Spectrogram; fraction::Real=0.85)
    isfinite(fraction) && 0 <= fraction <= 1 ||
        throw(ArgumentError("fraction must be finite and in [0, 1]"))
    # Rolloff is the first frequency whose cumulative power reaches the chosen
    # fraction of the frame's total power.
    output = zeros(Float64, size(result.power, 2))
    for column in axes(result.power, 2)
        spectrum = result.power[:, column]
        total = sum(spectrum)
        total == 0 && continue
        target = fraction * total
        cumulative = 0.0
        for bin in axes(result.power, 1)
            cumulative += spectrum[bin]
            if cumulative >= target
                output[column] = result.frequencies[bin]
                break
            end
        end
    end
    return FeatureTrack(output, result.times, :spectral_rolloff;
                        metadata=_track_metadata(result))
end

function spectral_flatness(result::Spectrogram; floor::Real=1e-12)
    isfinite(floor) && floor > 0 || throw(ArgumentError("floor must be positive and finite"))
    output = Vector{Float64}(undef, size(result.power, 2))
    bins = size(result.power, 1)
    for column in axes(result.power, 2)
        spectrum = result.power[:, column]
        arithmetic = sum(spectrum) / bins
        output[column] = arithmetic == 0 ? 0.0 :
            exp(sum(log.(max.(spectrum, floor))) / bins) / arithmetic
    end
    return FeatureTrack(output, result.times, :spectral_flatness;
                        metadata=_track_metadata(result))
end

function zero_crossing_rate(audio::AudioBuffer, settings::AnalysisConfig)
    return _frame_track(audio, settings, :zero_crossing_rate) do segment
        length(segment) < 2 && return 0.0
        crossings = 0
        previous = segment[1] >= 0
        for index in 2:length(segment)
            current = segment[index] >= 0
            crossings += current == previous ? 0 : 1
            previous = current
        end
        crossings / (length(segment) - 1)
    end
end

function zero_crossing_rate(audio::AudioBuffer; window_size::Integer=2_048,
                            hop_size::Integer=512, channel::Integer=1, pad::Bool=true)
    return zero_crossing_rate(audio, AnalysisConfig(window_size=window_size,
                                                    hop_size=hop_size,
                                                    channel=channel, pad=pad))
end

function dc_offset(audio::AudioBuffer, settings::AnalysisConfig)
    return _frame_track(audio, settings, :dc_offset) do segment
        sum(Float64.(segment)) / length(segment)
    end
end

function dc_offset(audio::AudioBuffer; window_size::Integer=2_048,
                   hop_size::Integer=512, channel::Integer=1, pad::Bool=true)
    return dc_offset(audio, AnalysisConfig(window_size=window_size, hop_size=hop_size,
                                           channel=channel, pad=pad))
end

function crest_factor(audio::AudioBuffer, settings::AnalysisConfig)
    return _frame_track(audio, settings, :crest_factor) do segment
        peak = maximum(abs, segment)
        energy = sqrt(sum(x -> abs2(Float64(x)), segment) / length(segment))
        energy == 0 ? 0.0 : peak / energy
    end
end

function crest_factor(audio::AudioBuffer; window_size::Integer=2_048,
                      hop_size::Integer=512, channel::Integer=1, pad::Bool=true)
    return crest_factor(audio, AnalysisConfig(window_size=window_size, hop_size=hop_size,
                                              channel=channel, pad=pad))
end

function amplitude_db(audio::AudioBuffer, settings::AnalysisConfig;
                      reference::Real=1.0, floor::Real=1e-12)
    isfinite(reference) && reference > 0 ||
        throw(ArgumentError("reference must be positive and finite"))
    isfinite(floor) && floor > 0 || throw(ArgumentError("floor must be positive and finite"))
    track = rms(audio, settings)
    result = 20 .* log10.(max.(values(track), floor) ./ reference)
    return FeatureTrack(result, times(track), :amplitude_db;
                        metadata=metadata(track))
end

function amplitude_db(audio::AudioBuffer; reference::Real=1.0, floor::Real=1e-12,
                      window_size::Integer=2_048, hop_size::Integer=512,
                      channel::Integer=1, pad::Bool=true)
    settings = AnalysisConfig(window_size=window_size, hop_size=hop_size,
                               channel=channel, pad=pad)
    return amplitude_db(audio, settings; reference=reference, floor=floor)
end

function power_db(result::Spectrogram; reference::Real=1.0, floor::Real=1e-12)
    isfinite(reference) && reference > 0 ||
        throw(ArgumentError("reference must be positive and finite"))
    isfinite(floor) && floor > 0 || throw(ArgumentError("floor must be positive and finite"))
    result_values = 10 .* log10.(max.(result.power, floor) ./ reference)
    return FeatureMatrix(result_values, result.times, :power_db;
                         metadata=_matrix_metadata(result))
end

function chroma(result::Spectrogram; tuning::Real=440.0)
    isfinite(tuning) && tuning > 0 || throw(ArgumentError("tuning must be positive and finite"))
    # Fold frequency bins into twelve pitch classes, then normalize each frame
    # so chroma describes spectral shape rather than absolute loudness.
    output = zeros(12, size(result.power, 2))
    for (bin, hz) in enumerate(result.frequencies)
        hz > 0 || continue
        pitch_class = mod(round(Int, 69 + 12log2(hz / tuning)), 12) + 1
        output[pitch_class, :] .+= result.power[bin, :]
    end
    for column in axes(output, 2)
        total = sum(@view output[:, column])
        total > 0 && (output[:, column] ./= total)
    end
    return FeatureMatrix(output, copy(result.times), :chroma;
                         metadata=_matrix_metadata(result))
end

"""HTK-mel triangular filters and orthonormal DCT-II including C0."""
function mfcc(result::Spectrogram; nfilters::Integer=40, ncoeffs::Integer=13,
              fmin::Real=0, fmax::Real=result.samplerate / 2, floor::Real=1e-10)
    1 <= ncoeffs <= nfilters || throw(ArgumentError("require 1 <= ncoeffs <= nfilters"))
    0 <= fmin < fmax <= result.samplerate / 2 || throw(ArgumentError("invalid frequency range"))
    isfinite(floor) && floor > 0 || throw(ArgumentError("floor must be finite and positive"))
    mel(hz) = 2595log10(1 + hz / 700)
    hz(m) = 700(expm1(m * log(10) / 2595))
    edges = hz.(range(mel(fmin), mel(fmax); length=nfilters + 2))
    filters = zeros(nfilters, length(result.frequencies))
    for band in 1:nfilters, (bin, frequency) in enumerate(result.frequencies)
        filters[band, bin] = max(0, min(
            (frequency - edges[band]) / (edges[band + 1] - edges[band]),
            (edges[band + 2] - frequency) / (edges[band + 2] - edges[band + 1])))
    end
    energies = log.(max.(filters * result.power, floor))
    basis = [(k == 0 ? sqrt(1 / nfilters) : sqrt(2 / nfilters)) *
             cospi(k * (band - 0.5) / nfilters)
             for k in 0:(ncoeffs - 1), band in 1:nfilters]
    return FeatureMatrix(basis * energies, copy(result.times), :mfcc;
                         metadata=_matrix_metadata(result))
end
