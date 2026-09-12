# AudioBuffer representation and channel/sample operations.
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
