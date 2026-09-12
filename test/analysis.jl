# Analysis framing, transforms, features, and end-to-end MIR pipeline tests.
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
