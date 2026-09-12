"""A tempo estimate with confidence, beat positions, and provenance."""
struct TempoEstimate
    bpm::Float64
    confidence::Float64
    beats::EventAnnotations
    metadata::NamedTuple

    function TempoEstimate(bpm::Real, confidence::Real, beats::EventAnnotations;
                           metadata=(;))
        isfinite(bpm) && bpm >= 0 || throw(ArgumentError("bpm must be finite and non-negative"))
        isfinite(confidence) && 0 <= confidence <= 1 ||
            throw(ArgumentError("confidence must be finite and in [0, 1]"))
        beats.kind == :beat || throw(ArgumentError("tempo beats must have kind=:beat"))
        metadata isa NamedTuple || throw(ArgumentError("metadata must be a NamedTuple"))
        new(Float64(bpm), Float64(confidence), beats, metadata)
    end
end

confidence(estimate::TempoEstimate) = estimate.confidence
metadata(estimate::TempoEstimate) = estimate.metadata
beat_positions(estimate::TempoEstimate) =
    EventAnnotations(times(estimate.beats); kind=:beat, metadata=metadata(estimate.beats))

function _median(values::AbstractVector{<:Real})
    ordered = sort(Float64.(values))
    middle = (length(ordered) + 1) ÷ 2
    return isodd(length(ordered)) ? ordered[middle] :
        (ordered[middle] + ordered[middle + 1]) / 2
end

function _beat_positions(start_time::Float64, stop_time::Float64, period::Float64)
    beats = Float64[]
    current = start_time
    limit = stop_time + 1e-9 * max(1.0, abs(stop_time))
    while current <= limit
        push!(beats, current)
        current += period
    end
    return EventAnnotations(beats; kind=:beat)
end

function _tempo_from_events(events::EventAnnotations; min_bpm::Real=40.0,
                            max_bpm::Real=240.0, stop_time=nothing)
    isfinite(min_bpm) && 0 < min_bpm || throw(ArgumentError("min_bpm must be positive"))
    isfinite(max_bpm) && min_bpm < max_bpm ||
        throw(ArgumentError("max_bpm must be greater than min_bpm"))
    event_times = _validated_event_times(events)
    intervals = [delta for delta in diff(event_times) if delta > 0]
    metadata_values = (; analysis_version=1, min_bpm=Float64(min_bpm),
                       max_bpm=Float64(max_bpm),
                       source_events=length(event_times), source_kind=events.kind,
                       source_metadata=metadata(events), method=:median_event_interval)
    isempty(intervals) &&
        return TempoEstimate(0.0, 0.0,
                             EventAnnotations(Float64[]; kind=:beat,
                                               metadata=metadata_values);
                             metadata=metadata_values)

    # The median interval is robust to an occasional missed or extra event.
    # Octave normalization then maps the raw estimate into the requested BPM
    # range without changing the underlying event timing.
    interval = _median(intervals)
    raw_bpm = 60 / interval
    bpm = raw_bpm
    while bpm < min_bpm
        bpm *= 2
    end
    while bpm > max_bpm
        bpm /= 2
    end
    # Confidence measures interval regularity; it is intentionally separate
    # from the BPM value so callers can reject uncertain estimates.
    mean_interval = sum(intervals) / length(intervals)
    spread = sqrt(sum((value - mean_interval)^2 for value in intervals) / length(intervals))
    estimate_confidence = clamp(1 - spread / mean_interval, 0.0, 1.0)
    first_time = first(event_times)
    final_time = stop_time === nothing ? last(event_times) : Float64(stop_time)
    isfinite(final_time) && final_time >= first_time ||
        throw(ArgumentError("stop_time must be finite and at or after the first event"))
    beats = _beat_positions(first_time, final_time, 60 / bpm)
    beats = EventAnnotations(times(beats); kind=:beat, metadata=metadata_values)
    return TempoEstimate(bpm, estimate_confidence, beats; metadata=metadata_values)
end

function tempo_estimate(events::EventAnnotations; min_bpm::Real=40.0,
                        max_bpm::Real=240.0, stop_time=nothing)
    return _tempo_from_events(events; min_bpm=min_bpm, max_bpm=max_bpm,
                              stop_time=stop_time)
end

function tempo_estimate(audio::AudioBuffer; threshold::Real=0.2,
                        min_interval::Real=0.05, min_bpm::Real=40.0,
                        max_bpm::Real=240.0, kwargs...)
    onsets = detect_onsets(audio; threshold=threshold, min_interval=min_interval, kwargs...)
    return tempo_estimate(onsets; min_bpm=min_bpm, max_bpm=max_bpm,
                          stop_time=duration(audio))
end
