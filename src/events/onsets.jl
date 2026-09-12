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
