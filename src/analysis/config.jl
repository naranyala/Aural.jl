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
