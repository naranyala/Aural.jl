"""A small, dependency-free representation of sampled audio."""

struct AudioBuffer{T,A<:AbstractMatrix{T}}
    samples::A
    samplerate::Int

    function AudioBuffer(data::A, samplerate::Integer) where {T,A<:AbstractMatrix{T}}
        samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
        size(data, 1) > 0 || throw(ArgumentError("audio must have at least one channel"))
        new{T,A}(data, Int(samplerate))
    end
end

AudioBuffer(data::AbstractVector, samplerate::Integer) =
    AudioBuffer(reshape(data, 1, length(data)), samplerate)

samples(audio::AudioBuffer) = audio.samples
samplerate(audio::AudioBuffer) = audio.samplerate
nchannels(audio::AudioBuffer) = size(audio.samples, 1)
nframes(audio::AudioBuffer) = size(audio.samples, 2)
duration(audio::AudioBuffer) = nframes(audio) / samplerate(audio)

Base.size(audio::AudioBuffer) = size(audio.samples)
Base.axes(audio::AudioBuffer) = axes(audio.samples)
Base.getindex(audio::AudioBuffer, indices...) = getindex(audio.samples, indices...)
Base.lastindex(audio::AudioBuffer) = lastindex(audio.samples)
Base.lastindex(audio::AudioBuffer, d::Integer) = lastindex(audio.samples, d)
Base.eltype(::Type{AudioBuffer{T,A}}) where {T,A} = T
Base.copy(audio::AudioBuffer) = AudioBuffer(copy(audio.samples), audio.samplerate)

function channel(audio::AudioBuffer, index::Integer)
    1 <= index <= nchannels(audio) || throw(BoundsError(audio, index))
    return vec(copy(@view audio.samples[index, :]))
end

function mono(audio::AudioBuffer)
    nchannels(audio) == 1 && return copy(audio)
    mixed = sum(audio.samples; dims=1) ./ nchannels(audio)
    return AudioBuffer(Array(mixed), samplerate(audio))
end

function stereo(audio::AudioBuffer)
    nchannels(audio) == 2 && return copy(audio)
    one_channel = mono(audio).samples
    return AudioBuffer(vcat(one_channel, one_channel), samplerate(audio))
end

function join_channels(first::AudioBuffer, rest::AudioBuffer...)
    audio = (first, rest...)
    rate = samplerate(first)
    frames = nframes(first)
    all(samplerate(x) == rate for x in audio) ||
        throw(ArgumentError("all buffers must have the same samplerate"))
    all(nframes(x) == frames for x in audio) ||
        throw(ArgumentError("all buffers must have the same number of frames"))
    return AudioBuffer(vcat((x.samples for x in audio)...), rate)
end

function silence(duration_seconds::Real; samplerate::Integer=48_000,
                 channels::Integer=1, T::Type=Float32)
    isfinite(duration_seconds) && duration_seconds >= 0 ||
        throw(ArgumentError("duration must be finite and non-negative"))
    samplerate > 0 || throw(ArgumentError("samplerate must be positive"))
    channels > 0 || throw(ArgumentError("channels must be positive"))
    frames = round(Int, duration_seconds * samplerate)
    return AudioBuffer(zeros(T, channels, frames), samplerate)
end

function gain(audio::AudioBuffer, factor::Number)
    return AudioBuffer(factor .* audio.samples, samplerate(audio))
end

function normalize(audio::AudioBuffer; target::Real=1.0)
    isfinite(target) && target >= 0 ||
        throw(ArgumentError("target must be finite and non-negative"))
    isempty(audio.samples) && return copy(audio)
    peak = maximum(abs, audio.samples)
    peak == 0 && return copy(audio)
    return gain(audio, target / peak)
end

"""Return a copied trim, rounding nonempty bounds outward to sample cells.

Equal bounds always return empty audio; bounds beyond the recording are clamped.
"""
function trim(audio::AudioBuffer, start_seconds::Real, stop_seconds::Real)
    isfinite(start_seconds) && isfinite(stop_seconds) ||
        throw(ArgumentError("trim bounds must be finite"))
    0 <= start_seconds <= stop_seconds ||
        throw(ArgumentError("trim requires 0 <= start <= stop"))
    start_seconds == stop_seconds && return AudioBuffer(audio.samples[:, 1:0], samplerate(audio))

    first_frame = clamp(floor(Int, start_seconds * samplerate(audio)) + 1,
                        1, nframes(audio) + 1)
    last_frame = clamp(ceil(Int, stop_seconds * samplerate(audio)),
                       0, nframes(audio))
    data = first_frame <= last_frame ?
        audio.samples[:, first_frame:last_frame] : audio.samples[:, 1:0]
    return AudioBuffer(copy(data), samplerate(audio))
end

function mix(first::AudioBuffer, second::AudioBuffer; offset::Real=0)
    samplerate(first) == samplerate(second) ||
        throw(ArgumentError("buffers must have the same samplerate"))
    nchannels(first) == nchannels(second) ||
        throw(ArgumentError("buffers must have the same number of channels"))
    isfinite(offset) && offset >= 0 ||
        throw(ArgumentError("offset must be finite and non-negative"))

    offset_frames = round(Int, offset * samplerate(first))
    total_frames = max(nframes(first), offset_frames + nframes(second))
    sample_type = promote_type(eltype(first.samples), eltype(second.samples))
    output = zeros(sample_type, nchannels(first), total_frames)
    nframes(first) > 0 && (output[:, 1:nframes(first)] .+= first.samples)
    if nframes(second) > 0
        range = (offset_frames + 1):(offset_frames + nframes(second))
        output[:, range] .+= second.samples
    end
    return AudioBuffer(output, samplerate(first))
end
