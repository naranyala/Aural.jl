module Aural

# Keep the include order aligned with the dependency direction: core data types
# come first, followed by synthesis/I/O, then analysis and event utilities.
include("audio.jl")
include("music.jl")
include("synthesis.jl")
include("wav_io.jl")
include("analysis.jl")
include("events.jl")

# This export list is the package's stable integration boundary. Internal
# helpers remain available to implementation files without becoming API.
export AudioBuffer, samples, samplerate, nchannels, nframes, duration
export channel, mono, stereo, join_channels, silence, gain, normalize, trim, mix
export Pitch, Note, Tempo, NoteEvent, Score
export midi, frequency, beats_to_seconds, duration_beats
export oscillator, tone, noise
export linear_ramp, exponential_ramp, ADSR, envelope, apply_envelope
export note, render
export read_audio, write_audio
export AnalysisConfig, validate_audio, FrameGrid, frame, eachframe, frame_times
export STFT, Spectrogram, FeatureTrack, FeatureMatrix, TempoEstimate
export coefficients, power, frequencies, times, values, metadata, config
export source_frames, confidence
export stft, spectrogram, rms, spectral_centroid, spectral_flux
export spectral_bandwidth, spectral_rolloff, spectral_flatness
export zero_crossing_rate, crest_factor, dc_offset, amplitude_db, power_db
export pitch_track, chroma, mfcc
export EventAnnotations, EventScore, evaluate_events, timing_error
export strengths, event_strengths, detect_onsets, tempo_estimate, beat_positions

end
