module Aural

include("audio.jl")
include("music.jl")
include("synthesis.jl")
include("io.jl")
include("analysis.jl")
include("events.jl")

export AudioBuffer, samples, samplerate, nchannels, nframes, duration
export channel, mono, stereo, join_channels, silence, gain, normalize, trim, mix
export Pitch, Note, Tempo, NoteEvent, Score
export midi, frequency, beats_to_seconds, duration_beats
export oscillator, tone, noise
export linear_ramp, exponential_ramp, ADSR, envelope, apply_envelope
export note, render
export read_audio, write_audio
export FrameGrid, frame, frame_times
export STFT, Spectrogram, FeatureTrack
export coefficients, power, frequencies, times, values
export stft, spectrogram, rms, spectral_centroid, spectral_flux
export FeatureMatrix, chroma, mfcc
export EventAnnotations, EventScore, evaluate_events, detect_onsets

end
