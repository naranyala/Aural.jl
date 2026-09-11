"""Print a compact, host-friendly analysis summary for a WAV file or tone."""

using Aural

audio = if isempty(ARGS)
    # Running without arguments gives contributors a zero-setup smoke example.
    tone(440, 1.0; samplerate=16_000, amplitude=0.25)
else
    # Host applications can replace this adapter with their own AudioBuffer
    # source; the analysis pipeline itself only needs the stable package type.
    mono(read_audio(ARGS[1]))
end

# Reuse one config so every frame-based feature has identical timestamps.
settings = AnalysisConfig(window_size=1024, hop_size=256, nfft=1024, pad=false)
spec = spectrogram(audio, settings)
energy = rms(audio, settings)
centroid = spectral_centroid(spec)
pitch = pitch_track(audio, settings; fmin=60, fmax=1_000)

println("frames=$(nframes(audio)) samplerate=$(samplerate(audio)) duration=$(duration(audio))s")
println("analysis_frames=$(length(times(spec))) window=$(settings.window_size) hop=$(settings.hop_size)")
println("mean_rms=$(isempty(values(energy)) ? 0.0 : sum(values(energy)) / length(energy))")
println("mean_centroid=$(isempty(values(centroid)) ? 0.0 : sum(values(centroid)) / length(centroid)) Hz")
println("voiced_pitch_frames=$(count(>(0), values(pitch)))")
