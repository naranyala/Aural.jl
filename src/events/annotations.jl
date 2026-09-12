"""
    EventAnnotations(times; kind=:onset, strengths=nothing)

Point events in seconds, copied and sorted. Supports `:onset` and `:beat`.
Optional strengths are kept aligned with timestamps and are copied on input.
These annotations are independent of beat-based `NoteEvent`s.
"""
struct EventAnnotations
    times::Vector{Float64}
    kind::Symbol
    strengths::Union{Nothing,Vector{Float64}}
    metadata::NamedTuple

    function EventAnnotations(input::AbstractVector{<:Real}; kind::Symbol=:onset,
                              strengths=nothing, metadata=(;))
        kind in (:onset, :beat) || throw(ArgumentError("kind must be :onset or :beat"))
        metadata isa NamedTuple || throw(ArgumentError("metadata must be a NamedTuple"))
        data = Float64.(input)
        all(t -> isfinite(t) && t >= 0, data) ||
            throw(ArgumentError("event times must be finite and non-negative"))

        strength_data = if strengths === nothing
            nothing
        else
            values = Float64.(strengths)
            length(values) == length(data) ||
                throw(ArgumentError("event strengths must match event times"))
            all(isfinite, values) || throw(ArgumentError("event strengths must be finite"))
            values
        end

        # Sort timestamps and strengths with the same permutation so event
        # attributes remain attached to the event they describe.
        order = sortperm(data)
        sorted_times = data[order]
        sorted_strengths = strength_data === nothing ? nothing : strength_data[order]
        new(sorted_times, kind, sorted_strengths, metadata)
    end
end

times(events::EventAnnotations) = copy(events.times)
strengths(events::EventAnnotations) =
    events.strengths === nothing ? nothing : copy(events.strengths)
event_strengths(events::EventAnnotations) = strengths(events)
metadata(events::EventAnnotations) = events.metadata
Base.length(events::EventAnnotations) = length(events.times)
Base.isempty(events::EventAnnotations) = isempty(events.times)
