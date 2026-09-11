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

"""Counts and micro-level metrics for a single event sequence comparison."""
struct EventScore
    true_positives::Int
    false_positives::Int
    false_negatives::Int
    precision::Float64
    recall::Float64
    f1::Float64
end

function _validated_event_times(events::EventAnnotations)
    data = Float64.(events.times)
    all(t -> isfinite(t) && t >= 0, data) ||
        throw(ArgumentError("event times must be finite and non-negative"))
    return sort!(data)
end

function _matched_event_pairs(reference::EventAnnotations, estimated::EventAnnotations,
                              tolerance::Real)
    isfinite(tolerance) && tolerance >= 0 || throw(ArgumentError("invalid tolerance"))
    reference.kind == estimated.kind || throw(ArgumentError("event kinds must match"))
    refs = _validated_event_times(reference)
    preds = _validated_event_times(estimated)
    # Both sequences are sorted, so the earliest compatible pair can be
    # consumed greedily. For a uniform tolerance this preserves maximum
    # cardinality while keeping the metric deterministic.
    pairs = Tuple{Int,Int}[]
    i = j = 1
    while i <= length(refs) && j <= length(preds)
        if abs(refs[i] - preds[j]) <= tolerance
            push!(pairs, (i, j))
            i += 1
            j += 1
        elseif preds[j] < refs[i]
            j += 1
        else
            i += 1
        end
    end
    return refs, preds, pairs
end

"""
    evaluate_events(reference, estimated; tolerance=0.05)

Maximum-cardinality, one-to-one matching within an inclusive tolerance in
seconds. Sorted events are matched earliest-first; this maximizes match count
for a uniform time tolerance, but does not minimize total timing error.
Duplicates cannot reuse a match. Empty-denominator metrics are zero, including
when both sequences are empty. Event kinds must agree. This is point-event F1,
not a beat-continuity metric or note-transcription metric.
"""
function evaluate_events(reference::EventAnnotations, estimated::EventAnnotations;
                         tolerance::Real=0.05)
    refs, preds, pairs = _matched_event_pairs(reference, estimated, tolerance)
    tp = length(pairs)
    fp, fn = length(preds) - tp, length(refs) - tp
    precision = isempty(preds) ? 0.0 : tp / length(preds)
    recall = isempty(refs) ? 0.0 : tp / length(refs)
    f1 = 2tp + fp + fn == 0 ? 0.0 : 2tp / (2tp + fp + fn)
    return EventScore(tp, fp, fn, precision, recall, f1)
end

"""
    timing_error(reference, estimated; tolerance=0.05)

Mean absolute timing error, in seconds, over matched event pairs. Unmatched
events are excluded because they are already represented by the precision and
recall terms from `evaluate_events`. Returns zero when no events are matched.
"""
function timing_error(reference::EventAnnotations, estimated::EventAnnotations;
                      tolerance::Real=0.05)
    refs, preds, pairs = _matched_event_pairs(reference, estimated, tolerance)
    isempty(pairs) && return 0.0
    return sum(abs(refs[i] - preds[j]) for (i, j) in pairs) / length(pairs)
end

"""
    detect_onsets(flux::FeatureTrack; threshold=0.2, min_interval=0.05,
                  threshold_mode=:global, local_window=3,
                  latency_compensation=0, return_strengths=false)

Local-peak picking on non-negative spectral flux. The default threshold is a
fraction of the global maximum. `threshold_mode=:local` compares each peak to
the maximum in its local neighbourhood, which is useful when transient levels
change over a recording. Peaks can be shifted earlier with
`latency_compensation`, and their flux values can be returned as strengths.
"""
function detect_onsets(flux::FeatureTrack; threshold::Real=0.2,
                       min_interval::Real=0.05, threshold_mode::Symbol=:global,
                       local_window::Integer=3, latency_compensation::Real=0,
                       return_strengths::Bool=false)
    flux.name == :spectral_flux || throw(ArgumentError("expected spectral flux"))
    isfinite(threshold) && 0 <= threshold <= 1 || throw(ArgumentError("invalid threshold"))
    isfinite(min_interval) && min_interval >= 0 || throw(ArgumentError("invalid min_interval"))
    threshold_mode in (:global, :local) ||
        throw(ArgumentError("threshold_mode must be :global or :local"))
    local_window > 0 || throw(ArgumentError("local_window must be positive"))
    isfinite(latency_compensation) && latency_compensation >= 0 ||
        throw(ArgumentError("latency_compensation must be finite and non-negative"))

    x, t = values(flux), times(flux)
    length(x) == length(t) || throw(ArgumentError("mismatched feature lengths"))
    all(v -> isfinite(v) && v >= 0, x) || throw(ArgumentError("invalid flux values"))
    all(v -> isfinite(v) && v >= 0, t) &&
        (length(t) < 2 || all(diff(t) .> 0)) ||
        throw(ArgumentError("timestamps must be non-negative and strictly increasing"))
    event_metadata = merge(metadata(flux), (; result=:onset_events))
    isempty(x) && return EventAnnotations(Float64[];
                                          strengths=return_strengths ? Float64[] : nothing,
                                          metadata=event_metadata)

    # Peak picking happens on the feature's time grid; source provenance is
    # carried forward so downstream code can relate events to the recording.
    global_cutoff = threshold * maximum(x)
    candidates = Int[]
    for i in eachindex(x)
        cutoff = if threshold_mode === :global
            global_cutoff
        else
            left = max(firstindex(x), i - local_window)
            right = min(lastindex(x), i + local_window)
            threshold * maximum(@view x[left:right])
        end
        if x[i] > cutoff && (i == firstindex(x) || x[i] > x[i - 1]) &&
           (i == lastindex(x) || x[i] >= x[i + 1])
            push!(candidates, i)
        end
    end

    # Consider the strongest peaks first, then reject nearby peaks. This makes
    # min_interval a non-maximum-suppression rule rather than an order artifact.
    sort!(candidates; by=i -> (-x[i], t[i]))
    selected = Int[]
    for i in candidates
        all(j -> abs(t[i] - t[j]) >= min_interval, selected) && push!(selected, i)
    end

    # STFT-derived events are centered on analysis frames; compensation lets a
    # host align detections with the likely transient onset time.
    shifted_times = [max(0.0, t[i] - latency_compensation) for i in selected]
    selected_strengths = return_strengths ? [x[i] for i in selected] : nothing
    return EventAnnotations(shifted_times; strengths=selected_strengths,
                            metadata=event_metadata)
end

"""
    detect_onsets(audio; threshold=0.2, min_interval=0.05, kwargs...)

Compute STFT spectral flux then pick peaks. Remaining keywords are passed to
`stft`; `pad=false` is the default. Returned events are constrained to the
recording and retain optional onset strengths.
"""
function detect_onsets(audio::AudioBuffer; threshold::Real=0.2,
                       min_interval::Real=0.05, threshold_mode::Symbol=:global,
                       local_window::Integer=3, latency_compensation::Real=0,
                       return_strengths::Bool=false, pad::Bool=false, kwargs...)
    flux = spectral_flux(spectrogram(audio; pad=pad, kwargs...))
    events = detect_onsets(flux; threshold=threshold, min_interval=min_interval,
                           threshold_mode=threshold_mode, local_window=local_window,
                           latency_compensation=latency_compensation,
                           return_strengths=return_strengths)
    # A padded STFT can place a frame center after the recording. Clip those
    # synthetic-tail detections at the audio boundary before returning them.
    event_times = times(events)
    keep = [t < duration(audio) for t in event_times]
    event_strength_values = strengths(events)
    filtered_strengths = event_strength_values === nothing ? nothing : event_strength_values[keep]
    return EventAnnotations(event_times[keep]; strengths=filtered_strengths,
                            metadata=metadata(events))
end

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
