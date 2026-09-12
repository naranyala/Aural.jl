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
