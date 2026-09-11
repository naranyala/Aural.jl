"""Audio-file adapters."""

import WAV

function read_audio(path::AbstractString; T::Type=Float32)
    data, file_samplerate = WAV.wavread(path)
    samples = if ndims(data) == 1
        # WAV returns mono as a vector, while AudioBuffer consistently uses a
        # channels-by-frames matrix.
        reshape(T.(data), 1, length(data))
    elseif ndims(data) == 2
        # Multi-channel WAV data is frames-by-channels, so transpose it once at
        # the boundary rather than carrying that convention through the API.
        permutedims(T.(data))
    else
        throw(ArgumentError("WAV data must be one- or two-dimensional"))
    end
    return AudioBuffer(samples, round(Int, file_samplerate))
end

function write_audio(path::AbstractString, audio::AudioBuffer)
    # Convert back to WAV's layout and Float32 at the file boundary. The
    # in-memory buffer keeps its original element type and channel-major form.
    data = nchannels(audio) == 1 ?
        vec(Float32.(audio.samples)) : permutedims(Float32.(audio.samples))
    WAV.wavwrite(data, path; Fs=samplerate(audio))
    return path
end
