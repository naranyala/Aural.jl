"""
    EventAnnotations(times; kind=:onset)

Point events in seconds, copied and sorted. Supports `:onset` and `:beat`.
Duplicate timestamps represent distinct events. Values must be finite and
non-negative. These annotations are independent of beat-based `NoteEvent`s.
"""
struct EventAnnotations
    times::Vector{Float64}
    kind::Symbol
    function EventAnnotations(input::AbstractVector{<:Real}; kind::Symbol=:onset)
        kind in (:onset, :beat) || throw(ArgumentError("kind must be :onset or :beat"))
        data = Float64.(input)
        all(t -> isfinite(t) && t >= 0, data) ||
            throw(ArgumentError("event times must be finite and non-negative"))
        new(sort!(data), kind)
    end
end
times(events::EventAnnotations) = copy(events.times)
Base.length(events::EventAnnotations) = length(events.times)

"""Counts and micro-level metrics for a single event sequence comparison."""
struct EventScore
    true_positives::Int
    false_positives::Int
    false_negatives::Int
    precision::Float64
    recall::Float64
    f1::Float64
end

"""
    evaluate_events(reference, estimated; tolerance=0.05)

Maximum-cardinality, one-to-one matching within an inclusive tolerance in
seconds. Sorted events are matched earliest-first; this maximizes match count
for a uniform time tolerance, but does not minimize total timing error.
Duplicates cannot reuse a match. Empty-denominator metrics are zero, including
when both sequences are empty. Event kinds must agree. This is point-event
F1, not a beat-continuity metric or note-transcription metric.
"""
function evaluate_events(reference::EventAnnotations, estimated::EventAnnotations;
                         tolerance::Real=0.05)
    isfinite(tolerance) && tolerance >= 0 || throw(ArgumentError("invalid tolerance"))
    reference.kind == estimated.kind || throw(ArgumentError("event kinds must match"))
    # Revalidate and sort, even if a caller has mutated the stored vectors.
    refs = EventAnnotations(reference.times; kind=reference.kind).times
    preds = EventAnnotations(estimated.times; kind=estimated.kind).times
    i = j = 1
    tp = 0
    while i <= length(refs) && j <= length(preds)
        if abs(refs[i] - preds[j]) <= tolerance
            tp += 1
            i += 1
            j += 1
        elseif preds[j] < refs[i]
            j += 1
        else
            i += 1
        end
    end
    fp, fn = length(preds) - tp, length(refs) - tp
    precision = isempty(preds) ? 0.0 : tp / length(preds)
    recall = isempty(refs) ? 0.0 : tp / length(refs)
    f1 = 2tp + fp + fn == 0 ? 0.0 : 2tp / (2tp + fp + fn)
    return EventScore(tp, fp, fn, precision, recall, f1)
end

"""
    detect_onsets(flux::FeatureTrack; threshold=0.2, min_interval=0.05)

Baseline local-peak picking on non-negative spectral flux. Threshold is a
fraction of the global maximum (0–1); peaks must be strictly above it.
The first bin of a plateau wins. Nearby peaks retain the strongest, with
earliest timestamps breaking ties. Frame timestamps are returned unchanged.
"""
function detect_onsets(flux::FeatureTrack; threshold::Real=0.2,
                       min_interval::Real=0.05)
    flux.name == :spectral_flux || throw(ArgumentError("expected spectral flux"))
    isfinite(threshold) && 0 <= threshold <= 1 || throw(ArgumentError("invalid threshold"))
    isfinite(min_interval) && min_interval >= 0 || throw(ArgumentError("invalid min_interval"))
    x, t = values(flux), times(flux)
    length(x) == length(t) || throw(ArgumentError("mismatched feature lengths"))
    all(v -> isfinite(v) && v >= 0, x) || throw(ArgumentError("invalid flux values"))
    all(v -> isfinite(v) && v >= 0, t) && all(diff(t) .> 0) ||
        throw(ArgumentError("timestamps must be non-negative and strictly increasing"))
    isempty(x) && return EventAnnotations(Float64[])
    cutoff = threshold * maximum(x)
    candidates = [i for i in eachindex(x) if x[i] > cutoff &&
                  (i == 1 || x[i] > x[i - 1]) &&
                  (i == length(x) || x[i] >= x[i + 1])]
    sort!(candidates; by=i -> (-x[i], t[i]))
    selected = Int[]
    for i in candidates
        all(j -> abs(t[i] - t[j]) >= min_interval, selected) && push!(selected, i)
    end
    return EventAnnotations(t[selected])
end

"""
    detect_onsets(audio; threshold=0.2, min_interval=0.05, kwargs...)

Compute STFT spectral flux then pick peaks. Remaining keywords are passed to
`stft`; `pad=false` is the default. Returns window-center times within the
recording. This offline baseline may miss an attack in the first frame and
does not compensate for window latency or estimate sub-frame timing.
"""
function detect_onsets(audio::AudioBuffer; threshold::Real=0.2,
                       min_interval::Real=0.05, pad::Bool=false, kwargs...)
    flux = spectral_flux(spectrogram(audio; pad=pad, kwargs...))
    events = detect_onsets(flux; threshold=threshold, min_interval=min_interval)
    return EventAnnotations(filter(t -> t < duration(audio), times(events)))
end
