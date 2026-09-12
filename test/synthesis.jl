# Oscillators, noise, envelopes, instruments, and offline score rendering.
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
