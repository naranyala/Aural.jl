import WAV

@testset "Audio boundaries and ownership" begin
    data = [1.0, -2, 3, -4]
    audio = AudioBuffer(data, 4)
    @test samples(audio)[:] == data
    samples(copy(audio))[1] = 999
    channel(audio, 1)[1] = 999
    @test data == [1, -2, 3, -4]
    @test isempty(channel(silence(0), 1))
    @test_throws BoundsError channel(audio, 2)
    @test_throws ArgumentError AudioBuffer(zeros(0, 4), 4)
    @test_throws ArgumentError AudioBuffer(data, 0)
    @test samples(mono(join_channels(audio, gain(audio, -1)))) == zeros(1, 4)
    @test samples(normalize(audio; target=0.5)) == reshape(data ./ 8, 1, 4)
    @test samples(normalize(silence(1; samplerate=4))) == zeros(1, 4)
    @test size(normalize(silence(0))) == (1, 0)
    @test_throws ArgumentError normalize(audio; target=-1)
    @test samples(trim(audio, 0, 1)) == samples(audio)
    @test nframes(trim(audio, 0.125, 0.125)) == 0
    @test nframes(trim(audio, 2, 3)) == 0
    @test_throws ArgumentError trim(audio, 1, 0)
    @test_throws ArgumentError trim(audio, 0, Inf)
    @test samples(mix(audio, audio)) == 2 .* samples(audio)
    @test samples(mix(audio, gain(audio, -1))) == zeros(1, 4)
    @test samples(mix(audio, audio; offset=1.5)) == reshape([data; 0; 0; data], 1, 10)
    @test_throws ArgumentError mix(audio, stereo(audio))
    @test_throws ArgumentError mix(audio, AudioBuffer(data, 8))
    @test_throws ArgumentError mix(audio, audio; offset=-1)
    @test_throws ArgumentError join_channels(audio, silence(0; samplerate=4))
    @test_throws ArgumentError join_channels(audio, AudioBuffer(data, 8))
    for bad in (-1, Inf, NaN)
        @test_throws ArgumentError silence(bad)
        @test_throws ArgumentError tone(440, bad)
    end
    @test_throws ArgumentError silence(1; channels=0)
    @test_throws ArgumentError tone(440, 1; samplerate=0)
end

@testset "Music timing and synthesis contracts" begin
    @test midi(Note(:C, 4; accidental=1)) == midi(Note(:D, 4; accidental=-1))
    @test frequency(Note(:A, 4)) == 440
    @test frequency(Note(:A, 5)) == 880
    @test frequency(Note(:A, 4); tuning=432) == 432
    for bad in (-1, 0, Inf, NaN)
        @test_throws ArgumentError Tempo(bad)
        @test_throws ArgumentError frequency(Note(69); tuning=bad)
    end
    @test_throws ArgumentError Pitch(Inf)
    @test_throws ArgumentError Note(:H, 4)
    note = Note(69)
    @test_throws ArgumentError NoteEvent(note, -1, 1)
    @test_throws ArgumentError NoteEvent(note, 0, 0)
    @test_throws ArgumentError NoteEvent(note, 0, 1; velocity=NaN)
    @test_throws ArgumentError NoteEvent(note, 0, 1; channel=17)
    late = NoteEvent(note, 2, 0.5)
    @test duration_beats(late) == 0.5
    @test duration_beats(Score([late])) == 2.5
    @test nframes(render(Score(NoteEvent[]))) == 0
    events = [late, NoteEvent(note, 0, 1)]
    @test first(Score(events)).start_beat == 0
    @test events[1].start_beat == 2
    @test samples(tone(1, 1; samplerate=4)) ≈ reshape([0, 1, 0, -1], 1, 4) atol=1e-7
    single = render(Score([NoteEvent(note, 0, 1)]); samplerate=8000)
    double = render(Score([NoteEvent(note, 0, 1), NoteEvent(note, 0, 1)]); samplerate=8000)
    @test samples(double) ≈ 2 .* samples(single)
    @test all(iszero, samples(render(Score([NoteEvent(note, 0, 1; velocity=0)]))))
end

@testset "Independent spectral references" begin
    # Direct DFT oracle, independent of FFTW and DSP, including odd FFT lengths.
    for nfft in (5, 8), window in (nothing, [0.2, 0.6, 0.8, 0.4])
        x = [0.25, -1, 0.75, 0.5]
        w = window === nothing ? ones(4) : window
        audio = AudioBuffer(vcat(reshape(x, 1, 4), zeros(1, 4)), 16)
        result = stft(audio; window_size=4, hop_size=4, nfft=nfft, window=window, pad=false)
        expected = [sum(x[j+1]*w[j+1]*cis(-2pi*k*j/nfft) for j in 0:3) for k in 0:fld(nfft, 2)]
        @test coefficients(result)[:, 1] ≈ expected atol=1e-12
        @test frequencies(result) ≈ collect(0:fld(nfft, 2)) .* (16/nfft)
        @test times(result) == [1.5/16]
        @test all(iszero, coefficients(stft(audio; window_size=4, hop_size=4, channel=2)))
    end
    @test values(rms(AudioBuffer(Int16[30000, -30000], 4); window_size=2, hop_size=2, pad=false)) == [30000]
    @test values(rms(AudioBuffer([2.], 4); window_size=4, hop_size=4)) == [1]
    audio = AudioBuffer(ones(4), 4)
    @test_throws ArgumentError frame(audio, FrameGrid(5; window_size=4, hop_size=4))
    @test_throws ArgumentError frame(audio, FrameGrid(4; window_size=4, hop_size=4); channel=0)
    for window in (:unknown, ones(3), [1, NaN, 1, 1])
        @test_throws ArgumentError stft(audio; window_size=4, hop_size=4, window=window)
    end
    for kwargs in ((window_size=0,), (hop_size=0,), (hop_size=-1,))
        @test_throws ArgumentError FrameGrid(4; kwargs...)
    end
    @test_throws ArgumentError frame_times(FrameGrid(4; window_size=4, hop_size=4), 0)
    @test_throws ArgumentError FeatureTrack([1.], [0., 1], :rms)
    spec = Spectrogram([1. 4 1; 9 4 0], [100., 300.], [0., 1, 2], 1000, 4, 4)
    @test values(spectral_centroid(spec)) ≈ [280, 200, 100]
    @test values(spectral_flux(spec)) == [0, 1, 0]
    scaled = Spectrogram(4 .* power(spec), frequencies(spec), times(spec), 1000, 4, 4)
    @test values(spectral_centroid(scaled)) ≈ values(spectral_centroid(spec))
    @test values(chroma(scaled)) ≈ values(chroma(spec))
    for kwargs in ((floor=0,), (fmin=-1,), (fmax=501,), (nfilters=0,))
        @test_throws ArgumentError mfcc(spec; kwargs...)
    end
    # Exactly two mel filter centers: known unit responses, and a two-point DCT.
    centers = [700*(2^(1/3)-1), 700*(2^(2/3)-1)]
    mel_spec = Spectrogram(reshape([exp(2), exp(4)], 2, 1), centers, [0.], 1400, 4, 4)
    @test values(mfcc(mel_spec; nfilters=2, ncoeffs=2))[:, 1] ≈ [6/sqrt(2), -sqrt(2)] atol=1e-12
end

# Exhaustive bipartite assignment oracle, without chronological assumptions.
function brute_matches(refs, preds, tolerance)
    isempty(refs) && return 0
    best = brute_matches(refs[2:end], preds, tolerance)
    for j in eachindex(preds)
        if abs(refs[1] - preds[j]) <= tolerance
            best = max(best, 1 + brute_matches(refs[2:end], preds[eachindex(preds) .!= j], tolerance))
        end
    end
    return best
end

@testset "Event matching exhaustive oracle" begin
    sequences = [Float64[], [0.], [0.5], [1.], [0., 0.], [0., 0.5], [0.5, 1.], [1., 0.]]
    for refs in sequences, preds in sequences, tolerance in (0., 0.25, 0.5)
        result = evaluate_events(EventAnnotations(refs), EventAnnotations(preds); tolerance=tolerance)
        @test result.true_positives == brute_matches(refs, preds, tolerance)
        @test result.true_positives + result.false_positives == length(preds)
        @test result.true_positives + result.false_negatives == length(refs)
    end
    flux = FeatureTrack([0., 2, 0, 2, 0], [0., 0.25, 0.5, 0.75, 1.], :spectral_flux)
    @test times(detect_onsets(flux; min_interval=0.5)) == [0.25, 0.75]
    @test times(detect_onsets(flux; min_interval=0.6)) == [0.25]
    @test isempty(times(detect_onsets(flux; threshold=1)))
    @test_throws ArgumentError detect_onsets(FeatureTrack([-1.], [0.], :spectral_flux))
    @test_throws ArgumentError detect_onsets(FeatureTrack([1.], [0.], :rms))
end

@testset "External WAV fixtures" begin
    mktempdir() do dir
        path = joinpath(dir, "pcm.wav")
        # Written directly by WAV.jl: this catches reciprocal Aural adapter errors.
        expected = [0.25 -0.5; -0.25 0.5; 0. 0.125]
        WAV.wavwrite(expected, path; Fs=22050, nbits=16, compression=WAV.WAVE_FORMAT_PCM)
        loaded = read_audio(path; T=Float64)
        @test samplerate(loaded) == 22050
        @test eltype(samples(loaded)) == Float64
        @test samples(loaded) ≈ permutedims(expected) atol=4e-5
        mono_path = joinpath(dir, "mono.wav")
        write_audio(mono_path, AudioBuffer([0.25, -0.5, 0.], 8000))
        raw, rate = WAV.wavread(mono_path)
        @test rate == 8000
        @test vec(raw) ≈ [0.25, -0.5, 0] atol=4e-5
        @test_throws SystemError read_audio(joinpath(dir, "absent.wav"))
        # WAV.jl owns malformed-file exception types; assert rejection, not its wording.
        broken = joinpath(dir, "truncated.wav")
        open(broken, "w") do io
            write(io, "RIFF")
        end
        @test_throws Exception read_audio(broken)
    end
end
