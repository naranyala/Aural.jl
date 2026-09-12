@testset "Audio edge cases and ownership" begin
    audio = AudioBuffer([1.0, -2.0], 4)
    duplicate = copy(audio)
    samples(duplicate)[1, 1] = 99
    @test audio[1, 1] == 1
    @test axes(audio) == (Base.OneTo(1), Base.OneTo(2))
    @test lastindex(audio) == 2
    @test lastindex(audio, 1) == 1
    @test lastindex(audio, 2) == 2
    @test eltype(audio) == Float64

    empty_audio = AudioBuffer(Float64[], 4)
    @test size(empty_audio) == (1, 0)
    @test duration(empty_audio) == 0
    @test size(copy(empty_audio)) == (1, 0)
    @test samples(mix(empty_audio, audio)) == samples(audio)
    @test samples(mix(audio, empty_audio; offset=0)) == samples(audio)

    multichannel = AudioBuffer([1.0 2.0; 3.0 4.0; 5.0 6.0], 8)
    downmixed = mono(multichannel)
    @test samples(downmixed) ≈ [3.0 4.0]
    @test samples(stereo(multichannel)) ≈ [3.0 4.0; 3.0 4.0]
    @test samples(stereo(AudioBuffer([2.0, 4.0], 8))) ≈ [2.0 4.0; 2.0 4.0]

    generated = silence(0.001; samplerate=1000, channels=2, T=Float64)
    @test size(generated) == (2, 1)
    @test eltype(samples(generated)) == Float64
    @test nframes(trim(empty_audio, 0, 1)) == 0
    @test nframes(trim(audio, 10, 11)) == 0
end

@testset "Analysis configuration and result contracts" begin
    stereo_input = AudioBuffer([1.0 2.0 3.0 4.0; 4.0 3.0 2.0 1.0], 8)
    custom = AnalysisConfig(window_size=4, hop_size=4, nfft=4, channel=2,
                            window=n -> fill(2.0, n), pad=false)
    transformed = stft(stereo_input, custom)
    @test coefficients(transformed)[:, 1] ≈ [20, 4 - 4im, 4]
    @test config(transformed) == custom
    @test samplerate(transformed) == 8
    @test source_frames(transformed) == 4
    @test metadata(transformed).channel == 2
    @test metadata(transformed).layout == :frequency_bins_x_frames

    vector_window = stft(AudioBuffer([1.0, 2.0, 3.0, 4.0], 8);
                         window_size=4, hop_size=4, nfft=4,
                         window=[1.0, 0.0, 0.0, 0.0], pad=false)
    @test coefficients(vector_window)[:, 1] ≈ fill(1.0, 3) .* [1, 1, 1]
    @test validate_audio(AudioBuffer([NaN], 1); finite=false) isa AudioBuffer
    @test_throws ArgumentError AnalysisConfig(channel=0)
    @test_throws ArgumentError stft(stereo_input; window_size=4, hop_size=4,
                                    window=n -> fill(NaN, n), pad=false)

    direct_stft = STFT(ComplexF64[1 2; 3 4], [0.0, 1.0], [0.0, 0.5], 8, 2, 1)
    @test size(coefficients(direct_stft)) == (2, 2)
    @test config(direct_stft).nfft == 2
    @test_throws ArgumentError STFT(zeros(ComplexF64, 2, 1), [0.0], [0.0], 8, 2, 1)
    @test_throws ArgumentError STFT(zeros(ComplexF64, 2, 1), [1.0, 0.0], [0.0], 8, 2, 1)

    @test_throws ArgumentError Spectrogram([-1.0;;], [0.0], [0.0], 8, 1, 1)
    @test_throws ArgumentError FeatureTrack([1.0, 2.0], [0.0, 0.0], :test)
    @test_throws ArgumentError FeatureTrack([1.0], [0.0], :test; confidence=[2.0])
    @test_throws ArgumentError FeatureMatrix([1.0 2.0], [0.0], :test)

    one_sample = AudioBuffer([1.0], 8)
    @test values(zero_crossing_rate(one_sample; window_size=1, hop_size=1, pad=false)) == [0.0]
    @test values(dc_offset(one_sample; window_size=1, hop_size=1, pad=false)) == [1.0]
    @test values(crest_factor(silence(0.001; samplerate=1000);
                             window_size=1, hop_size=1, pad=false)) == [0.0]
    @test values(amplitude_db(silence(0.001; samplerate=1000);
                              window_size=1, hop_size=1, pad=false))[1] ≈ -240
    @test_throws ArgumentError spectral_rolloff(Spectrogram([1.0;;], [0.0], [0.0], 8, 1, 1);
                                                 fraction=2)
    @test_throws ArgumentError spectral_flatness(Spectrogram([1.0;;], [0.0], [0.0], 8, 1, 1);
                                                  floor=0)
    @test_throws ArgumentError chroma(Spectrogram([1.0;;], [0.0], [0.0], 8, 1, 1);
                                       tuning=0)
end

@testset "Synthesis parameter boundaries" begin
    @test size(oscillator(0, 0; samplerate=8)) == (1, 0)
    @test oscillator(0, 0.001; samplerate=1000, phase=pi / 2)[1, 1] ≈ 1f0
    @test oscillator(2, 0.001; samplerate=1000, amplitude=0.25)[1, 1] == 0f0
    @test size(linear_ramp(2, 3, 0.001; samplerate=1000)) == (1, 1)
    @test size(exponential_ramp(2, 3, 0.001; samplerate=1000)) == (1, 1)
    zero_phase = ADSR(0, 0, 0.25, 0)
    @test all(==(0.25f0), samples(envelope(zero_phase, 0.01; samplerate=1000)))

    for bad in (-1, NaN, Inf)
        @test_throws ArgumentError oscillator(bad, 0.1)
        @test_throws ArgumentError noise(bad)
        @test_throws ArgumentError linear_ramp(0, 1, bad)
    end
    @test_throws ArgumentError oscillator(440, 1; amplitude=NaN)
    @test_throws ArgumentError oscillator(440, 1; phase=Inf)
    @test_throws ArgumentError exponential_ramp(0, 1, 1)
    @test_throws ArgumentError exponential_ramp(1, -1, 1)
    @test_throws ArgumentError ADSR(-1, 0, 0.5, 0)
    @test_throws ArgumentError ADSR(0, 0, 2, 0)
end

@testset "Pitch, onset, and tempo edge cases" begin
    short = AudioBuffer([1.0, -1.0], 8)
    short_pitch = pitch_track(short; fmin=1, fmax=4, window_size=2, hop_size=2, pad=false)
    @test values(short_pitch) == [0.0]
    @test confidence(short_pitch) == [0.0]
    @test isempty(values(pitch_track(silence(0); window_size=2, hop_size=1, pad=false)))
    @test_throws ArgumentError pitch_track(short; fmin=0)
    @test_throws ArgumentError pitch_track(short; fmin=5, fmax=4)
    @test_throws ArgumentError pitch_track(short; confidence_threshold=2)

    edge_flux = FeatureTrack([2.0, 0.0, 3.0], [0.0, 1.0, 2.0], :spectral_flux)
    edge_events = detect_onsets(edge_flux; threshold=0.2, return_strengths=true)
    @test times(edge_events) == [0.0, 2.0]
    @test strengths(edge_events) == [2.0, 3.0]
    @test metadata(edge_events).result == :onset_events
    @test timing_error(EventAnnotations([1.0]), EventAnnotations([3.0])) == 0
    @test_throws ArgumentError timing_error(EventAnnotations([1.0]), EventAnnotations([1.0]);
                                            tolerance=-1)

    normalized_tempo = tempo_estimate(EventAnnotations([0.0, 1.0, 2.0]);
                                      min_bpm=100, max_bpm=200, stop_time=2.0)
    @test normalized_tempo.bpm == 120
    @test times(beat_positions(normalized_tempo)) ≈ [0.0, 0.5, 1.0, 1.5, 2.0]
    @test tempo_estimate(EventAnnotations([1.0, 1.0])).bpm == 0
    @test_throws ArgumentError tempo_estimate(EventAnnotations([0.0, 1.0]); min_bpm=0)
    @test_throws ArgumentError tempo_estimate(EventAnnotations([0.0, 1.0]); max_bpm=40)
    @test_throws ArgumentError tempo_estimate(EventAnnotations([0.0, 1.0]); stop_time=-1)
end
