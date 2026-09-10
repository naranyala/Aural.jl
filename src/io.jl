"""Audio-file adapters."""

import WAV

function read_audio(path::AbstractString; T::Type=Float32)
    data, file_samplerate = WAV.wavread(path)
    samples = if ndims(data) == 1
        reshape(T.(data), 1, length(data))
    elseif ndims(data) == 2
        permutedims(T.(data))
    else
        throw(ArgumentError("WAV data must be one- or two-dimensional"))
    end
    return AudioBuffer(samples, round(Int, file_samplerate))
end

function write_audio(path::AbstractString, audio::AudioBuffer)
    data = nchannels(audio) == 1 ?
        vec(Float32.(audio.samples)) : permutedims(Float32.(audio.samples))
    WAV.wavwrite(data, path; Fs=samplerate(audio))
    return path
end
