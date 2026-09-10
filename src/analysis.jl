"""Time-frequency representations and baseline MIR features."""

import DSP
import FFTW

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

    last_start = pad ? signal_frames : signal_frames - window_size + 1
    starts = last_start >= 1 ? collect(1:hop_size:last_start) : Int[]
    return FrameGrid(Int(signal_frames), Int(window_size), Int(hop_size), pad, starts)
end

Base.length(grid::FrameGrid) = length(grid.starts)
nframes(grid::FrameGrid) = length(grid)

function frame_times(grid::FrameGrid, samplerate::Integer)
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    return [(start - 1 + (grid.window_size - 1) / 2) / samplerate
            for start in grid.starts]
end

function frame(audio::AudioBuffer, grid::FrameGrid; channel::Integer=1)
    grid.signal_frames == nframes(audio) ||
        throw(ArgumentError("frame grid does not match audio length"))
    1 <= channel <= nchannels(audio) ||
        throw(ArgumentError("channel is outside the audio buffer"))

    output = zeros(eltype(audio.samples), grid.window_size, length(grid))
    source = audio.samples[channel, :]
    for (column, start) in enumerate(grid.starts)
        available = min(grid.window_size, nframes(audio) - start + 1)
        available > 0 && (output[1:available, column] .= source[start:(start + available - 1)])
    end
    return output
end

struct STFT
    data::Matrix{ComplexF64}
    frequencies::Vector{Float64}
    times::Vector{Float64}
    samplerate::Int
    window_size::Int
    hop_size::Int
end

coefficients(result::STFT) = result.data
frequencies(result::STFT) = result.frequencies
times(result::STFT) = result.times

struct Spectrogram
    power::Matrix{Float64}
    frequencies::Vector{Float64}
    times::Vector{Float64}
    samplerate::Int
    window_size::Int
    hop_size::Int
end

power(result::Spectrogram) = result.power
frequencies(result::Spectrogram) = result.frequencies
times(result::Spectrogram) = result.times

struct FeatureTrack{T}
    values::Vector{T}
    times::Vector{Float64}
    name::Symbol

    function FeatureTrack(values::AbstractVector{T}, times::AbstractVector{<:Real},
                          name::Symbol) where T
        length(values) == length(times) ||
            throw(ArgumentError("feature values and times must have equal lengths"))
        new{T}(collect(values), Float64.(times), name)
    end
end

Base.length(feature::FeatureTrack) = length(feature.values)
Base.getindex(feature::FeatureTrack, index...) = getindex(feature.values, index...)
Base.values(feature::FeatureTrack) = feature.values
times(feature::FeatureTrack) = feature.times

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

function stft(audio::AudioBuffer; window_size::Integer=2_048,
              hop_size::Integer=512, nfft::Integer=window_size,
              channel::Integer=1, window=:hann, pad::Bool=true)
    nfft >= window_size || throw(ArgumentError("nfft must be at least window_size"))
    grid = FrameGrid(nframes(audio); window_size=window_size,
                     hop_size=hop_size, pad=pad)
    framed = frame(audio, grid; channel=channel)
    window_values = _window_values(window, grid.window_size)
    output = Matrix{ComplexF64}(undef, fld(nfft, 2) + 1, length(grid))

    for column in axes(framed, 2)
        segment = zeros(Float64, nfft)
        segment[1:grid.window_size] .= Float64.(framed[:, column]) .* window_values
        output[:, column] = FFTW.rfft(segment)
    end

    frequency_axis = collect(0:fld(nfft, 2)) .* (samplerate(audio) / nfft)
    return STFT(output, frequency_axis, frame_times(grid, samplerate(audio)),
                samplerate(audio), grid.window_size, grid.hop_size)
end

"""Matrix-valued features (feature rows × analysis frames), with timestamps."""
struct FeatureMatrix
    values::Matrix{Float64}
    times::Vector{Float64}
    name::Symbol
end
Base.values(feature::FeatureMatrix) = feature.values
times(feature::FeatureMatrix) = feature.times

"""FFT-bin chroma: C through B, power summed by nearest 12-TET pitch, L1 normalized."""
function chroma(result::Spectrogram; tuning::Real=440.0)
    isfinite(tuning) && tuning > 0 || throw(ArgumentError("tuning must be positive and finite"))
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
    return FeatureMatrix(output, copy(result.times), :chroma)
end

"""HTK-mel triangular filters, natural-log energies, orthonormal DCT-II including C0.

Filters have unit peak (no area normalization). Returns coefficients × frames.
"""
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
    return FeatureMatrix(basis * energies, copy(result.times), :mfcc)
end

function spectrogram(result::STFT)
    return Spectrogram(abs2.(result.data), result.frequencies, result.times,
                       result.samplerate, result.window_size, result.hop_size)
end

spectrogram(audio::AudioBuffer; kwargs...) = spectrogram(stft(audio; kwargs...))

function rms(audio::AudioBuffer; window_size::Integer=2_048,
             hop_size::Integer=512, channel::Integer=1, pad::Bool=true)
    grid = FrameGrid(nframes(audio); window_size=window_size,
                     hop_size=hop_size, pad=pad)
    framed = frame(audio, grid; channel=channel)
    result = [sqrt(sum(x -> abs2(Float64(x)), framed[:, column]) / window_size)
              for column in axes(framed, 2)]
    return FeatureTrack(result, frame_times(grid, samplerate(audio)), :rms)
end

function spectral_centroid(result::Spectrogram)
    centroids = Vector{Float64}(undef, size(result.power, 2))
    for column in axes(result.power, 2)
        spectrum = result.power[:, column]
        total_power = sum(spectrum)
        centroids[column] = total_power == 0 ? 0.0 :
            sum(result.frequencies .* spectrum) / total_power
    end
    return FeatureTrack(centroids, result.times, :spectral_centroid)
end

function spectral_flux(result::Spectrogram)
    flux = zeros(Float64, size(result.power, 2))
    magnitudes = sqrt.(result.power)
    for column in 2:size(magnitudes, 2)
        increase = max.(magnitudes[:, column] .- magnitudes[:, column - 1], 0)
        flux[column] = sqrt(sum(abs2, increase))
    end
    return FeatureTrack(flux, result.times, :spectral_flux)
end
