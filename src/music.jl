"""Small symbolic music types used by the initial offline renderer."""

# Music-domain positions are expressed in beats; conversion to seconds is
# deliberately deferred until rendering so a score can be retimed cheaply.

struct Pitch
    midi::Float64

    function Pitch(midi::Real)
        isfinite(midi) || throw(ArgumentError("pitch must be finite"))
        new(Float64(midi))
    end
end

midi(pitch::Pitch) = pitch.midi
frequency(pitch::Pitch; tuning::Real=440.0) = begin
    isfinite(tuning) && tuning > 0 || throw(ArgumentError("tuning must be positive and finite"))
    tuning * 2.0^((midi(pitch) - 69.0) / 12.0)
end

struct Note
    pitch::Pitch
end

Note(midi_number::Real) = Note(Pitch(midi_number))

const PITCH_CLASSES = Dict(
    :C => 0, :D => 2, :E => 4, :F => 5,
    :G => 7, :A => 9, :B => 11,
)

function Note(name::Symbol, octave::Integer; accidental::Integer=0)
    # MIDI's octave convention is used here: C4 is MIDI note 60.
    pitch_class = get(PITCH_CLASSES, name, nothing)
    pitch_class === nothing &&
        throw(ArgumentError("unknown note name: $name"))
    return Note(12 * (Int(octave) + 1) + pitch_class + accidental)
end

midi(note::Note) = midi(note.pitch)
frequency(note::Note; tuning::Real=440.0) = frequency(note.pitch; tuning=tuning)

struct Tempo
    bpm::Float64

    function Tempo(bpm::Real)
        isfinite(bpm) && bpm > 0 || throw(ArgumentError("tempo must be positive"))
        new(Float64(bpm))
    end
end

beats_to_seconds(beats::Real, tempo::Tempo) = Float64(beats) * 60.0 / tempo.bpm

struct NoteEvent
    note::Note
    start_beat::Float64
    duration_beats::Float64
    velocity::Float64
    channel::Int

    function NoteEvent(note::Note, start_beat::Real, duration_beats::Real;
                       velocity::Real=1.0, channel::Integer=1)
        # Validate at construction time so renderers can assume every event is
        # finite, audible, and addressable by a valid MIDI-style channel.
        isfinite(start_beat) && start_beat >= 0 ||
            throw(ArgumentError("start_beat must be non-negative and finite"))
        isfinite(duration_beats) && duration_beats > 0 ||
            throw(ArgumentError("duration_beats must be positive and finite"))
        0 <= velocity <= 1 || throw(ArgumentError("velocity must be in [0, 1]"))
        1 <= channel <= 16 || throw(ArgumentError("channel must be in 1:16"))
        new(note, Float64(start_beat), Float64(duration_beats),
            Float64(velocity), Int(channel))
    end
end

duration_beats(event::NoteEvent) = event.duration_beats

struct Score
    events::Vector{NoteEvent}
    tempo::Tempo
end

function Score(events::AbstractVector{<:NoteEvent}; tempo::Tempo=Tempo(120))
    # Store a sorted copy: callers may reuse or mutate their input collection
    # without changing the score's event order or ownership.
    ordered = sort!(collect(events), by=event -> event.start_beat)
    return Score(ordered, tempo)
end

Base.length(score::Score) = length(score.events)
Base.iterate(score::Score, state...) = iterate(score.events, state...)
duration_beats(score::Score) = isempty(score.events) ? 0.0 :
    maximum(event -> event.start_beat + duration_beats(event), score.events)
