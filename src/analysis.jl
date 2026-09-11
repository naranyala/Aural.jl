"""Time-frequency representations and baseline MIR features."""

import DSP
import FFTW

"""Shared framing and analysis settings."""

# AnalysisConfig is the single source of truth for windowing. Keeping these
# values together prevents STFTs and frame-domain features from drifting onto
# different time grids when an application changes one setting.
struct AnalysisConfig{W}
    window_size::Int
    hop_size::Int
    nfft::Int
    channel::Int
    window::W
    pad::Bool

    function AnalysisConfig(; window_size::Integer=2_048,
                            hop_size::Integer=512,
                            nfft::Integer=window_size,
                            channel::Integer=1,
                            window=:hann,
                            pad::Bool=true)
        window_size > 0 || throw(ArgumentError("window_size must be positive"))
        0 < hop_size <= window_size ||
            throw(ArgumentError("hop_size must be in 1:window_size"))
        nfft >= window_size ||
            throw(ArgumentError("nfft must be at least window_size"))
        channel > 0 || throw(ArgumentError("channel must be positive"))
        new{typeof(window)}(Int(window_size), Int(hop_size), Int(nfft),
                            Int(channel), window, pad)
    end
end

"""Validate an audio buffer before numerical analysis."""
function validate_audio(audio::AudioBuffer; channel::Integer=1, finite::Bool=true)
    1 <= channel <= nchannels(audio) ||
        throw(ArgumentError("channel is outside the audio buffer"))
    if finite
        all(x -> x isa Real && isfinite(x), audio.samples) ||
            throw(ArgumentError("audio samples must be finite real numbers"))
    end
    return audio
end

struct FrameGrid
    signal_frames::Int
    window_size::Int
    hop_size::Int
    pad::Bool
    starts::Vector{Int}
end

function FrameGrid(signal_frames::Integer; window_size::Integer=2_048,
                   hop_size::Integer=512, pad::Bool=true)
    signal_frames >= 0 || throw(ArgumentError("signal_frames must be non-negative"))
    window_size > 0 || throw(ArgumentError("window_size must be positive"))
    0 < hop_size <= window_size ||
        throw(ArgumentError("hop_size must be in 1:window_size"))

    # With padding, include a frame beginning at every hop inside the source.
    # Without padding, require a complete window so no synthetic samples enter
    # the analysis.
    last_start = pad ? signal_frames : signal_frames - window_size + 1
    starts = last_start >= 1 ? collect(1:hop_size:last_start) : Int[]
    return FrameGrid(Int(signal_frames), Int(window_size), Int(hop_size), pad, starts)
end

Base.length(grid::FrameGrid) = length(grid.starts)
nframes(grid::FrameGrid) = length(grid)

function frame_times(grid::FrameGrid, samplerate::Integer)
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    # Report the center of each analysis window, including centers beyond the
    # source end for padded tail frames.
    return [(start - 1 + (grid.window_size - 1) / 2) / samplerate
            for start in grid.starts]
end

function frame(audio::AudioBuffer, grid::FrameGrid; channel::Integer=1)
    grid.signal_frames == nframes(audio) ||
        throw(ArgumentError("frame grid does not match audio length"))
    validate_audio(audio; channel=channel)

    # Materialize a column-major frame matrix for algorithms that need all
    # frames at once; each column owns zero-padded samples at the tail.
    output = zeros(eltype(audio.samples), grid.window_size, length(grid))
    source = audio.samples[channel, :]
    for (column, start) in enumerate(grid.starts)
        available = min(grid.window_size, nframes(audio) - start + 1)
        available > 0 && (output[1:available, column] .= source[start:(start + available - 1)])
    end
    return output
end

frame(audio::AudioBuffer, config::AnalysisConfig) =
    frame(audio, FrameGrid(nframes(audio); window_size=config.window_size,
                           hop_size=config.hop_size, pad=config.pad);
          channel=config.channel)

"""A bounded-memory iterator over padded or unpadded audio frames."""
struct FrameIterator
    audio::AudioBuffer
    grid::FrameGrid
    channel::Int
end

Base.length(iterator::FrameIterator) = length(iterator.grid)

function Base.iterate(iterator::FrameIterator, state::Int=1)
    state > length(iterator.grid) && return nothing
    start = iterator.grid.starts[state]
    width = iterator.grid.window_size
    # Each iteration returns an independent vector. This keeps the iterator
    # bounded in memory without exposing a reusable scratch buffer to callers.
    output = zeros(eltype(iterator.audio.samples), width)
    available = min(width, nframes(iterator.audio) - start + 1)
    if available > 0
        output[1:available] .= iterator.audio.samples[
            iterator.channel, start:(start + available - 1)]
    end
    return output, state + 1
end

function eachframe(audio::AudioBuffer, grid::FrameGrid; channel::Integer=1)
    grid.signal_frames == nframes(audio) ||
        throw(ArgumentError("frame grid does not match audio length"))
    validate_audio(audio; channel=channel)
    return FrameIterator(audio, grid, Int(channel))
end

function eachframe(audio::AudioBuffer, config::AnalysisConfig)
    grid = FrameGrid(nframes(audio); window_size=config.window_size,
                     hop_size=config.hop_size, pad=config.pad)
    return eachframe(audio, grid; channel=config.channel)
end

struct STFT
    data::Matrix{ComplexF64}
    frequencies::Vector{Float64}
    times::Vector{Float64}
    samplerate::Int
    window_size::Int
    hop_size::Int
    source_frames::Int
    config::AnalysisConfig
end

function STFT(data::AbstractMatrix{<:Complex}, frequencies::AbstractVector{<:Real},
              times::AbstractVector{<:Real}, samplerate::Integer,
              window_size::Integer, hop_size::Integer)
    # Normalize result storage to stable, interoperable arrays at the public
    # boundary; callers do not need to know which FFT element type was used.
    matrix = ComplexF64.(data)
    freq = Float64.(frequencies)
    stamps = Float64.(times)
    size(matrix, 1) == length(freq) ||
        throw(ArgumentError("STFT rows must match frequencies"))
    size(matrix, 2) == length(stamps) ||
        throw(ArgumentError("STFT columns must match times"))
    all(isfinite, matrix) || throw(ArgumentError("STFT coefficients must be finite"))
    all(isfinite, freq) && all(x -> x >= 0, freq) &&
        (length(freq) < 2 || all(diff(freq) .> 0)) ||
        throw(ArgumentError("STFT frequencies must be finite and increasing"))
    all(isfinite, stamps) && all(x -> x >= 0, stamps) &&
        (length(stamps) < 2 || all(diff(stamps) .> 0)) ||
        throw(ArgumentError("STFT times must be finite and increasing"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    config = AnalysisConfig(window_size=window_size, hop_size=hop_size,
                            nfft=max(window_size, 2 * (length(freq) - 1)))
    return STFT(matrix, freq, stamps, Int(samplerate), Int(window_size),
                Int(hop_size), 0, config)
end

coefficients(result::STFT) = result.data
frequencies(result::STFT) = result.frequencies
times(result::STFT) = result.times
samplerate(result::STFT) = result.samplerate
source_frames(result::STFT) = result.source_frames
config(result::STFT) = result.config
metadata(result::STFT) = (; analysis_version=1, config=result.config,
                          source_frames=result.source_frames,
                          samplerate=result.samplerate, channel=result.config.channel,
                          layout=:frequency_bins_x_frames,
                          source_layout=:channels_x_frames)

struct Spectrogram
    power::Matrix{Float64}
    frequencies::Vector{Float64}
    times::Vector{Float64}
    samplerate::Int
    window_size::Int
    hop_size::Int
    source_frames::Int
    config::AnalysisConfig

    function Spectrogram(power::AbstractMatrix{<:Real}, frequencies::AbstractVector{<:Real},
                         times::AbstractVector{<:Real}, samplerate::Integer,
                         window_size::Integer, hop_size::Integer,
                         source_frames::Integer=0,
                         config::AnalysisConfig=AnalysisConfig(window_size=window_size,
                             hop_size=hop_size,
                             nfft=max(window_size, 2 * (length(frequencies) - 1))))
        data = Float64.(power)
        freq = Float64.(frequencies)
        stamps = Float64.(times)
        size(data, 1) == length(freq) ||
            throw(ArgumentError("spectrogram rows must match frequencies"))
        size(data, 2) == length(stamps) ||
            throw(ArgumentError("spectrogram columns must match times"))
        all(isfinite, data) && all(x -> x >= 0, data) ||
            throw(ArgumentError("spectrogram power must be finite and non-negative"))
        all(isfinite, freq) && all(x -> x >= 0, freq) &&
            (length(freq) < 2 || all(diff(freq) .> 0)) ||
            throw(ArgumentError("spectrogram frequencies must be finite and increasing"))
        all(isfinite, stamps) && all(x -> x >= 0, stamps) &&
            (length(stamps) < 2 || all(diff(stamps) .> 0)) ||
            throw(ArgumentError("spectrogram times must be finite and increasing"))
        samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
        source_frames >= 0 || throw(ArgumentError("source_frames must be non-negative"))
        new(data, freq, stamps, Int(samplerate), Int(window_size), Int(hop_size),
            Int(source_frames), config)
    end
end

power(result::Spectrogram) = result.power
frequencies(result::Spectrogram) = result.frequencies
times(result::Spectrogram) = result.times
samplerate(result::Spectrogram) = result.samplerate
source_frames(result::Spectrogram) = result.source_frames
config(result::Spectrogram) = result.config
metadata(result::Spectrogram) = (; analysis_version=1, config=result.config,
                                 source_frames=result.source_frames,
                                 samplerate=result.samplerate, channel=result.config.channel,
                                 layout=:frequency_bins_x_frames,
                                 source_layout=:channels_x_frames)

struct FeatureTrack{T}
    values::Vector{T}
    times::Vector{Float64}
    name::Symbol
    confidence::Union{Nothing,Vector{Float64}}
    metadata::NamedTuple

    function FeatureTrack(values::AbstractVector{T}, times::AbstractVector{<:Real},
                          name::Symbol; confidence=nothing, metadata=(;)) where T
        length(values) == length(times) ||
            throw(ArgumentError("feature values and times must have equal lengths"))
        stamps = Float64.(times)
        all(isfinite, stamps) && all(x -> x >= 0, stamps) &&
            (length(stamps) < 2 || all(diff(stamps) .> 0)) ||
            throw(ArgumentError("feature times must be finite, non-negative, and increasing"))
        data = collect(values)
        all(isfinite, data) || throw(ArgumentError("feature values must be finite"))
        conf = confidence === nothing ? nothing : Float64.(confidence)
        if conf !== nothing
            length(conf) == length(data) ||
                throw(ArgumentError("confidence must match feature values"))
            all(x -> isfinite(x) && 0 <= x <= 1, conf) ||
                throw(ArgumentError("confidence must be finite and in [0, 1]"))
        end
        metadata isa NamedTuple || throw(ArgumentError("metadata must be a NamedTuple"))
        new{T}(data, stamps, name, conf, metadata)
    end
end

Base.length(feature::FeatureTrack) = length(feature.values)
Base.isempty(feature::FeatureTrack) = isempty(feature.values)
Base.getindex(feature::FeatureTrack, index...) = getindex(feature.values, index...)
Base.values(feature::FeatureTrack) = feature.values
times(feature::FeatureTrack) = feature.times
confidence(feature::FeatureTrack) =
    feature.confidence === nothing ? nothing : copy(feature.confidence)
metadata(feature::FeatureTrack) = feature.metadata
config(feature::FeatureTrack) = hasproperty(feature.metadata, :config) ?
    getproperty(feature.metadata, :config) : nothing
source_frames(feature::FeatureTrack) = hasproperty(feature.metadata, :source_frames) ?
    getproperty(feature.metadata, :source_frames) : 0

"""Matrix-valued features, with feature rows and analysis-frame columns."""
struct FeatureMatrix
    values::Matrix{Float64}
    times::Vector{Float64}
    name::Symbol
    metadata::NamedTuple

    function FeatureMatrix(values::AbstractMatrix{<:Real}, times::AbstractVector{<:Real},
                           name::Symbol; metadata=(;))
        data = Float64.(values)
        stamps = Float64.(times)
        size(data, 2) == length(stamps) ||
            throw(ArgumentError("feature columns must match times"))
        all(isfinite, data) || throw(ArgumentError("feature values must be finite"))
        all(isfinite, stamps) && all(x -> x >= 0, stamps) &&
            (length(stamps) < 2 || all(diff(stamps) .> 0)) ||
            throw(ArgumentError("feature times must be finite, non-negative, and increasing"))
        metadata isa NamedTuple || throw(ArgumentError("metadata must be a NamedTuple"))
        new(data, stamps, name, metadata)
    end
end

Base.values(feature::FeatureMatrix) = feature.values
Base.isempty(feature::FeatureMatrix) = isempty(feature.times)
times(feature::FeatureMatrix) = feature.times
metadata(feature::FeatureMatrix) = feature.metadata
config(feature::FeatureMatrix) = hasproperty(feature.metadata, :config) ?
    getproperty(feature.metadata, :config) : nothing
source_frames(feature::FeatureMatrix) = hasproperty(feature.metadata, :source_frames) ?
    getproperty(feature.metadata, :source_frames) : 0

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
