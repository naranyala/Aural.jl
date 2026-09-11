"""Small allocation/throughput smoke benchmark; run from the repository root."""

using Aural

seconds = isempty(ARGS) ? 10.0 : parse(Float64, first(ARGS))
audio = tone(440, seconds; samplerate=16_000)
# Keep the benchmark settings explicit: changing them changes both workload
# size and the memory/throughput trade-off being measured.
settings = AnalysisConfig(window_size=1024, hop_size=256, nfft=1024, pad=false)
grid = FrameGrid(nframes(audio); window_size=settings.window_size,
                 hop_size=settings.hop_size, pad=settings.pad)

println("audio_frames=$(nframes(audio)) analysis_frames=$(length(grid)) " *
        "window_size=$(settings.window_size) hop_size=$(settings.hop_size) pad=$(settings.pad)")
println("stft allocation/elapsed time:")
# @time is intentionally dependency-free; use BenchmarkTools in a follow-up
# benchmark when stable statistical samples are needed for release tracking.
@time stft(audio, settings)
println("rms allocation/elapsed time:")
@time rms(audio, settings)
