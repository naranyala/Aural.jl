"""Time-frequency representations and baseline MIR features."""

import DSP
import FFTW

# Keep the analysis implementation grouped by responsibility while retaining
# this stable include path for the package entry point and repository docs.
include("analysis/config.jl")
include("analysis/results.jl")
include("analysis/transforms.jl")
include("analysis/features.jl")
include("analysis/pitch.jl")
