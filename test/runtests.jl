using Test
using Aural
import DSP

# Keep the runner small: each included file owns one test domain, while the
# regression and edge-case suites protect behavior across domains.
include("regressions.jl")
include("edge_cases.jl")
include("events.jl")
include("analysis.jl")
include("audio.jl")
include("music.jl")
include("synthesis.jl")
