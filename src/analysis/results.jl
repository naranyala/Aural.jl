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
