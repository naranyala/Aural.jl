using Test
using Aural
import DSP
include("regressions.jl")

# MIR tests use small synthetic signals so timing, metadata, and edge-case
# behavior stay deterministic and fast enough for every supported Julia version.
@testset "MIR events and evaluation" begin
    input = [2.0, 1.0]
    refs = EventAnnotations(input)
    @test times(refs) == [1, 2]
    @test input == [2, 1]
    @test_throws ArgumentError EventAnnotations([NaN])
    @test_throws ArgumentError EventAnnotations([-1.0])
    @test_throws ArgumentError EventAnnotations([1.0]; kind=:chord)
    result = evaluate_events(refs, EventAnnotations([1.01, 1.02, 3]))
    @test (result.true_positives, result.false_positives, result.false_negatives) == (1, 2, 1)
    @test result.precision ≈ 1/3
    @test result.recall == 0.5
    @test result.f1 == 0.4
    # A nearest-first assignment can lose a match here; chronological matching must not.
    @test evaluate_events(EventAnnotations([1, 1.125]), EventAnnotations([0.9375, 1.0625]); tolerance=0.0625).true_positives == 2
    @test evaluate_events(EventAnnotations([1, 1]), EventAnnotations([1]); tolerance=0).true_positives == 1
    @test evaluate_events(EventAnnotations(Float64[]), EventAnnotations(Float64[])).f1 == 0
    @test evaluate_events(refs, EventAnnotations(Float64[])).false_negatives == 2
    @test_throws ArgumentError evaluate_events(refs, refs; tolerance=-1)
    @test_throws ArgumentError evaluate_events(refs, EventAnnotations([1]; kind=:beat))
    annotated = EventAnnotations([0.4, 0.1]; strengths=[4., 1.])
    @test times(annotated) == [0.1, 0.4]
    @test strengths(annotated) == [1., 4.]
    @test event_strengths(annotated) == strengths(annotated)
    @test metadata(annotated) == (;)
    @test timing_error(EventAnnotations([1., 2.]), EventAnnotations([1.1, 2.05]);
                       tolerance=0.2) ≈ 0.075
    @test_throws ArgumentError EventAnnotations([0.1]; strengths=[NaN])
    @test_throws ArgumentError EventAnnotations([0.1]; strengths=[1., 2.])
    flux = FeatureTrack([0., 2, 2, 0, 3, 0], collect(0.:0.1:0.5), :spectral_flux)
    @test times(detect_onsets(flux; min_interval=0.05)) ≈ [0.1, 0.4]
    @test times(detect_onsets(flux; min_interval=0.35)) ≈ [0.4]
    detected_with_strengths = detect_onsets(flux; return_strengths=true)
    @test strengths(detected_with_strengths) ≈ [2., 3.]
    @test times(detect_onsets(flux; latency_compensation=0.15)) ≈ [0., 0.25]
    changing_flux = FeatureTrack([0., 1, 0, 10, 0], [0., 0.1, 0.2, 0.3, 0.4], :spectral_flux)
    @test times(detect_onsets(changing_flux; threshold=0.5)) == [0.3]
    @test times(detect_onsets(changing_flux; threshold=0.5,
                              threshold_mode=:local, local_window=1)) == [0.1, 0.3]
    @test isempty(times(detect_onsets(FeatureTrack(zeros(4), collect(0.:3.), :spectral_flux))))
    @test_throws ArgumentError detect_onsets(flux; threshold=2)
    @test_throws ArgumentError detect_onsets(flux; threshold_mode=:adaptive)
    @test_throws ArgumentError detect_onsets(flux; local_window=0)
    @test_throws ArgumentError detect_onsets(FeatureTrack([1., 2], [0., 0], :spectral_flux))
    data = zeros(Float32, 8000)
    data[[2001, 4001, 6001]] .= 1
    detected = detect_onsets(AudioBuffer(data, 8000); window_size=128, hop_size=32)
    expected = EventAnnotations([0.25, 0.5, 0.75])
    @test evaluate_events(expected, detected; tolerance=0.016).f1 == 1
    @test metadata(detected).source_frames == 8000
    @test length(detect_onsets(silence(0))) == 0
    tempo = tempo_estimate(EventAnnotations(collect(0.:0.5:4.)))
    @test tempo.bpm ≈ 120
    @test tempo.confidence == 1
    @test all(t -> t.kind == :beat, [beat_positions(tempo)])
    @test times(beat_positions(tempo)) == collect(0.:0.5:4.)
    empty_tempo = tempo_estimate(EventAnnotations(Float64[]))
    @test empty_tempo.bpm == 0
    @test empty_tempo.confidence == 0
    @test isempty(beat_positions(empty_tempo))
end

@testset "MIR pipeline" begin
    # This testset follows the intended host workflow:
    # AudioBuffer -> shared frame config -> STFT/features -> events.
    audio = tone(1000, 0.128; samplerate=8000, amplitude=0.5)
    mktempdir() do dir
        path = joinpath(dir, "stereo.wav")
        original = join_channels(audio, gain(audio, 0.5))
        write_audio(path, original)
        loaded = read_audio(path)
        @test samplerate(loaded) == 8000
        @test size(loaded) == size(original)
        @test samples(loaded) ≈ samples(original) atol=4e-5
    end
    grid = FrameGrid(5; window_size=4, hop_size=2)
    @test frame(AudioBuffer(collect(1.0:5), 8), grid) == [1 3 5; 2 4 0; 3 5 0; 4 0 0]
    settings = AnalysisConfig(window_size=4, hop_size=2, nfft=8, pad=true)
    @test frame(AudioBuffer(collect(1.0:5), 8), settings) == frame(AudioBuffer(collect(1.0:5), 8), grid)
    @test collect(eachframe(AudioBuffer(collect(1.0:5), 8), grid)) ==
          [frame(AudioBuffer(collect(1.0:5), 8), grid)[:, i] for i in axes(frame(AudioBuffer(collect(1.0:5), 8), grid), 2)]
    @test frame_times(grid, 8) == [1.5, 3.5, 5.5] ./ 8
    @test length(FrameGrid(2; window_size=4, hop_size=2, pad=false)) == 0
    @test_throws ArgumentError FrameGrid(5; window_size=4, hop_size=5)
    @test_throws ArgumentError AnalysisConfig(window_size=0)
    @test_throws ArgumentError AnalysisConfig(window_size=4, hop_size=0)
    @test_throws ArgumentError AnalysisConfig(window_size=4, nfft=2)
    transform = stft(audio; window_size=256, hop_size=128, nfft=512, pad=false)
    reference = DSP.stft(channel(audio, 1), 256, 128; nfft=512, window=DSP.hann)
    @test coefficients(transform) ≈ reference rtol=1e-6
    @test size(coefficients(transform)) == (257, 7)
    spec = spectrogram(transform)
    @test frequencies(spec)[argmax(power(spec)[:, 1])] == 1000
    @test all(isapprox.(values(spectral_centroid(spec)), 1000; atol=1))
    @test all(isapprox.(values(rms(audio; window_size=256, hop_size=128, pad=false)), 0.5/sqrt(2); atol=1e-6))
    @test maximum(values(spectral_flux(spec))) < 1e-6
    @test config(transform) == AnalysisConfig(window_size=256, hop_size=128, nfft=512,
                                              pad=false)
    @test source_frames(transform) == nframes(audio)
    @test metadata(spec).layout == :frequency_bins_x_frames
    @test times(rms(audio, config(transform))) == times(spec)
    empty_spec = spectrogram(silence(0); window_size=256, hop_size=128)
    @test size(power(empty_spec)) == (129, 0)
    @test isempty(values(spectral_centroid(empty_spec)))
    silent = spectrogram(silence(0.128; samplerate=8000); window_size=256, hop_size=128)
    @test all(iszero, values(chroma(silent)))
    cepstra = values(mfcc(silent; nfilters=20, ncoeffs=8))
    @test all(isapprox.(cepstra[1, :], sqrt(20)*log(1e-10); atol=1e-10))
    @test maximum(abs, cepstra[2:end, :]) < 1e-10
    a = spectrogram(tone(440, 1; samplerate=8800); window_size=8800, hop_size=8800, window=nothing, pad=false)
    @test argmax(values(chroma(a))[:, 1]) == 10 # A, with C at row 1
    @test sum(values(chroma(a))) ≈ 1
    @test all(isfinite, values(spectral_bandwidth(spec)))
    @test values(spectral_rolloff(spec; fraction=0.5))[1] >= 0
    @test all(x -> 0 <= x <= 1, values(spectral_flatness(spec)))
    short_audio = AudioBuffer([-1., 1., -1., 1.], 4)
    @test values(zero_crossing_rate(short_audio; window_size=4, hop_size=4, pad=false)) == [1.]
    @test values(dc_offset(short_audio; window_size=4, hop_size=4, pad=false)) == [0.]
    @test values(crest_factor(AudioBuffer([1., -1., 0., 0.], 4);
                              window_size=4, hop_size=4, pad=false))[1] ≈ sqrt(2)
    @test values(amplitude_db(AudioBuffer(ones(4), 4);
                              window_size=4, hop_size=4, pad=false))[1] ≈ 0
    @test size(values(power_db(spec))) == size(power(spec))
    @test_throws ArgumentError stft(AudioBuffer([NaN], 1); window_size=1, hop_size=1)
    pitch_audio = tone(440, 1; samplerate=8000)
    pitch = pitch_track(pitch_audio; fmin=400, fmax=500,
                        window_size=1024, hop_size=512, pad=false)
    @test values(pitch)[cld(length(pitch), 2)] ≈ 440 atol=20
    @test confidence(pitch)[cld(length(pitch), 2)] > 0.8
    @test size(values(mfcc(spec))) == (13, 7)
    @test times(mfcc(spec)) == times(spec)
    @test_throws ArgumentError mfcc(spec; ncoeffs=41)
    @test_throws ArgumentError stft(audio; window_size=256, nfft=128)
end

@testset "AudioBuffer" begin
    # The audio model is channel-major and sample-rate preserving.
    audio = AudioBuffer(Float32[0, 0.5, -1, 0.25], 1_000)

    @test size(audio) == (1, 4)
    @test samples(audio) == reshape(Float32[0, 0.5, -1, 0.25], 1, 4)
    @test samplerate(audio) == 1_000
    @test nchannels(audio) == 1
    @test nframes(audio) == 4
    @test duration(audio) ≈ 0.004
    @test channel(audio, 1) == Float32[0, 0.5, -1, 0.25]

    stereo_audio = stereo(audio)
    @test size(stereo_audio) == (2, 4)
    @test stereo_audio[1, :] == stereo_audio[2, :]
    @test mono(stereo_audio).samples ≈ audio.samples
    @test join_channels(audio, audio).samples == stereo_audio.samples

    @test gain(audio, 2).samples ≈ 2 .* audio.samples
    @test maximum(abs, normalize(audio).samples) ≈ 1
    @test trim(audio, 0.001, 0.003).samples == reshape(Float32[0.5, -1], 1, 2)

    delayed = mix(audio, audio; offset=0.002)
    @test nframes(delayed) == 6
    @test delayed[1, :] == Float32[0, 0.5, -1, 0.75, -1, 0.25]
end

@testset "Music model" begin
    # Symbolic positions are measured in beats until a Tempo converts them to
    # seconds for rendering.
    middle_c = Note(:C, 4)
    @test midi(middle_c) == 60
    @test frequency(middle_c) ≈ 261.6255653005986

    tempo = Tempo(120)
    event = NoteEvent(middle_c, 0, 1; velocity=0.75)
    score = Score([event]; tempo=tempo)
    @test beats_to_seconds(1, tempo) ≈ 0.5
    @test duration_beats(event) == 1
    @test duration_beats(score) == 1
    @test length(score) == 1
end

@testset "Oscillators" begin
    sr = 1000
    dur = 0.5
    frames = 500

    # Sine matches tone
    s = oscillator(10.0, dur; samplerate=sr)
    t = tone(10.0, dur; samplerate=sr)
    @test samples(s) == samples(t)

    # Cosine is sine shifted by π/2
    c = oscillator(10.0, dur; samplerate=sr, shape=:cosine)
    @test c[1, 1] ≈ 1.0f0

    # Saw is bounded
    saw = oscillator(10.0, dur; samplerate=sr, shape=:saw)
    @test size(saw) == (1, frames)
    @test all(-1.01f0 .<= saw.samples .<= 1.01f0)

    # Square is ±1
    sq = oscillator(10.0, dur; samplerate=sr, shape=:square)
    vals = unique(sq.samples)
    @test all(v -> v ≈ -1.0f0 || v ≈ 1.0f0, vals)

    # Triangle is bounded and has zero at start (no phase)
    tri = oscillator(10.0, dur; samplerate=sr, shape=:triangle)
    @test all(-1.01f0 .<= tri.samples .<= 1.01f0)

    # Invalid shape
    @test_throws ArgumentError oscillator(10.0, dur; samplerate=sr, shape=:pulse)
end

@testset "White noise" begin
    n = noise(0.1; samplerate=1000)
    @test size(n) == (1, 100)
    @test nchannels(n) == 1
    # Should not be all zeros
    @test any(!iszero, n.samples)
end

@testset "Envelope ramps" begin
    sr = 100
    # Linear ramp
    lin = linear_ramp(0.0, 1.0, 0.1; samplerate=sr)
    @test size(lin) == (1, 10)
    @test lin[1, 1] ≈ 0.0f0 atol=1e-6
    @test lin[1, end] ≈ 1.0f0 atol=1e-6

    # Exponential ramp
    exp_r = exponential_ramp(1.0, 0.5, 0.1; samplerate=sr)
    @test size(exp_r) == (1, 10)
    @test exp_r[1, 1] ≈ 1.0f0 atol=1e-6
    @test exp_r[1, end] ≈ 0.5f0 atol=1e-6

    # Single-frame edge case
    lin1 = linear_ramp(0.0, 1.0, 0.0; samplerate=sr)
    @test size(lin1) == (1, 0)
end

@testset "ADSR envelope" begin
    sr = 1000
    dur = 0.1
    adsr = ADSR(0.01, 0.02, 0.5, 0.03)
    env = envelope(adsr, dur; samplerate=sr)
    @test size(env) == (1, 100)
    @test env[1, 1] ≈ 0.0f0 atol=1e-6  # starts at 0

    # Attack peak
    att_frame = round(Int, adsr.attack * sr)
    if att_frame >= 1 && att_frame <= 100
        @test env[1, att_frame] ≈ 1.0f0 atol=0.01f0
    end

    # Ends near 0 (release)
    @test env[1, end] ≈ 0.0f0 atol=0.05f0

    # Scaling when phases exceed duration
    long_adsr = ADSR(0.5, 0.5, 0.5, 0.5)
    env2 = envelope(long_adsr, 0.1; samplerate=sr)
    @test size(env2) == (1, 100)
    @test env2[1, 1] ≈ 0.0f0 atol=1e-6
    @test env2[1, end] ≈ 0.0f0 atol=1e-6
end

@testset "apply_envelope" begin
    sr = 100
    audio = oscillator(5.0, 0.1; samplerate=sr)
    env = linear_ramp(0.0, 1.0, 0.1; samplerate=sr)
    result = apply_envelope(audio, env)
    @test size(result) == size(audio)
    @test result[1, 1] ≈ 0.0f0 atol=1e-6
    @test_throws ArgumentError apply_envelope(audio, silence(0.05; samplerate=sr))
end

@testset "Note instrument" begin
    sr = 1000
    # Without envelope: same as oscillator
    n1 = note(440.0, 0.1; samplerate=sr, shape=:saw)
    n2 = oscillator(440.0, 0.1; samplerate=sr, shape=:saw)
    @test samples(n1) == samples(n2)

    # With envelope
    adsr = ADSR(0.01, 0.02, 0.5, 0.03)
    n3 = note(440.0, 0.1; samplerate=sr, shape=:sine, adsr=adsr)
    @test size(n3) == (1, 100)
    # Should be shaped: starts near 0, ends near 0
    @test abs(n3[1, 1]) < 0.1f0
    @test abs(n3[1, end]) < 0.1f0
    # Peak should be less than full amplitude (envelope scales it)
    @test maximum(abs, n3.samples) <= 1.0f0
end

@testset "Offline synthesis" begin
    audio = tone(440, 0.01; samplerate=48_000)
    @test size(audio) == (1, 480)
    @test audio[1, 1] == 0f0
    @test maximum(abs, audio.samples) > 0.9f0

    score = Score([
        NoteEvent(Note(:C, 4), 0, 1),
        NoteEvent(Note(:E, 4), 1, 1),
    ]; tempo=Tempo(120))
    rendered = render(score; samplerate=48_000)
    @test nchannels(rendered) == 1
    @test nframes(rendered) == 48_000
    @test maximum(abs, rendered.samples) > 0
end
