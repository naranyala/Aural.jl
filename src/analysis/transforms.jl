function _window_values(window, size::Int)
    values = if window === :hann
        DSP.hann(size)
    elseif window === nothing
        ones(Float64, size)
    elseif window isa Function
        window(size)
    elseif window isa AbstractVector
        window
    else
        throw(ArgumentError("window must be :hann, nothing, a function, or a vector"))
    end
    length(values) == size || throw(ArgumentError("window has the wrong length"))
    all(isfinite, values) || throw(ArgumentError("window must be finite"))
    return Float64.(values)
end

function _validate_config(audio::AudioBuffer, settings::AnalysisConfig)
    validate_audio(audio; channel=settings.channel)
    _window_values(settings.window, settings.window_size)
    return settings
end

function _grid(audio::AudioBuffer, settings::AnalysisConfig)
    _validate_config(audio, settings)
    return FrameGrid(nframes(audio); window_size=settings.window_size,
                     hop_size=settings.hop_size, pad=settings.pad)
end

_analysis_metadata(audio::AudioBuffer, settings::AnalysisConfig) =
    (; analysis_version=1, config=settings, source_frames=nframes(audio),
       samplerate=samplerate(audio),
       channel=settings.channel, layout=:frames, source_layout=:channels_x_frames)

_track_metadata(result::Spectrogram) = merge(metadata(result), (; layout=:frames))
_matrix_metadata(result::Spectrogram) =
    merge(metadata(result), (; layout=:features_x_frames))

function stft(audio::AudioBuffer, settings::AnalysisConfig)
    grid = _grid(audio, settings)
    window_values = _window_values(settings.window, settings.window_size)
    output = Matrix{ComplexF64}(undef, fld(settings.nfft, 2) + 1, length(grid))
    source = @view audio.samples[settings.channel, :]
    # Reuse one zero-padded FFT input buffer for every frame. The result matrix
    # owns its coefficients, while the temporary segment does not accumulate
    # allocations proportional to the number of frames.
    segment = zeros(Float64, settings.nfft)

    for (column, start) in enumerate(grid.starts)
        # Clear the complete FFT input so padded samples are guaranteed to be
        # zero, then apply the window only to source samples that exist.
        segment .= 0.0
        available = min(settings.window_size, nframes(audio) - start + 1)
        if available > 0
            segment[1:available] .= source[start:(start + available - 1)]
            segment[1:available] .*= window_values[1:available]
        end
        output[:, column] = FFTW.rfft(segment)
    end

    frequency_axis = collect(0:fld(settings.nfft, 2)) .* (samplerate(audio) / settings.nfft)
    return STFT(output, frequency_axis, frame_times(grid, samplerate(audio)),
                samplerate(audio), settings.window_size, settings.hop_size,
                nframes(audio), settings)
end

function stft(audio::AudioBuffer; window_size::Integer=2_048,
              hop_size::Integer=512, nfft::Integer=window_size,
              channel::Integer=1, window=:hann, pad::Bool=true)
    return stft(audio, AnalysisConfig(window_size=window_size, hop_size=hop_size,
                                      nfft=nfft, channel=channel, window=window, pad=pad))
end

function spectrogram(result::STFT)
    return Spectrogram(abs2.(result.data), result.frequencies, result.times,
                       result.samplerate, result.window_size, result.hop_size,
                       result.source_frames, result.config)
end

spectrogram(audio::AudioBuffer, settings::AnalysisConfig) =
    spectrogram(stft(audio, settings))

spectrogram(audio::AudioBuffer; kwargs...) = spectrogram(stft(audio; kwargs...))

function _frame_track(operation, audio::AudioBuffer, settings::AnalysisConfig, name::Symbol)
    grid = _grid(audio, settings)
    output = Vector{Float64}(undef, length(grid))
    for (index, segment) in enumerate(eachframe(audio, grid; channel=settings.channel))
        output[index] = operation(segment)
    end
    return FeatureTrack(output, frame_times(grid, samplerate(audio)), name;
                        metadata=_analysis_metadata(audio, settings))
end
