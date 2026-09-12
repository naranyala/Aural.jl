"""Point-event annotations, onset detection, and tempo primitives."""

# Keep event data, metrics, detection, and tempo estimation independently
# navigable while retaining this stable include path for the module entry point.
include("events/annotations.jl")
include("events/scoring.jl")
include("events/onsets.jl")
include("events/tempo.jl")
