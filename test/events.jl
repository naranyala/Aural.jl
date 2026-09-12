# Event annotations, point-event metrics, and MIR event workflows.
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
