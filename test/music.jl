# Symbolic music types, timing, and score structure.
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
