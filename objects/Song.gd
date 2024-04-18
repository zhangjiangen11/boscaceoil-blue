###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2024 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## A container for all composition and playback details of an individual
## Bosca Ceoil song.
class_name Song extends Resource

const FILE_FORMAT := 3

# Metadata.

## File format version.
@export var format_version: int = FILE_FORMAT
## Song's title.
@export var name: String = ""
## File name on disk, if available.
@export var filename: String = ""

# Base settings.

## Length of each pattern in notes.
@export var pattern_size: int = 16:
	set(value): pattern_size = ValueValidator.range(value, 1, 32)
## Length of a bar in notes, purely visual.
@export var bar_size: int = 4:
	set(value): bar_size = ValueValidator.range(value, 1, 32)
## Beats per minute.
@export var bpm: int = 120:
	set(value): bpm = ValueValidator.range(value, 10, 220)

# Advanced settings.

## Swing's direction and power.
@export var swing: int = 0:
	set(value): swing = ValueValidator.range(value, -10, 10)
## Index of the globally applied effect.
@export var global_effect: int = 0:
	set(value): global_effect = ValueValidator.posizero(value) # Max value is limited by the number of implemented effects.
## Power/intensity of the globally applied effect.
@export var global_effect_power: int = 0:
	set(value): global_effect_power = ValueValidator.range(value, 0, 100)

# Composition.

## Instruments used by the song.
@export var instruments: Array[Instrument] = []
## Note patterns defined for the song.
@export var patterns: Array[Pattern] = []
## Arrangement of the song.
@export var arrangement: Arrangement = Arrangement.new()


static func create_default_song() -> Song:
	var song := Song.new()
	
	# Create the default instrument, which is hard set to be MIDI Grand Piano.
	var voice_data := Controller.voice_manager.get_voice_data("MIDI", "Grand Piano")
	var default_instrument := SingleVoiceInstrument.new(voice_data)
	song.instruments.push_back(default_instrument)

	# There must be at least one pattern in the song.
	var default_pattern := Pattern.new()
	default_pattern.instrument_idx = 0
	song.patterns.push_back(default_pattern)
	
	# By default make the first pattern active on the timeline.
	song.arrangement.set_pattern(0, 0, 0)
	
	return song


# Composition.

func progress_arrangement() -> bool:
	var next_bar := arrangement.current_bar_idx + 1
	if next_bar >= arrangement.loop_end:
		arrangement.current_bar_idx = arrangement.loop_start
		return true # Looped.
	else:
		arrangement.current_bar_idx = next_bar
		return false # Didn't loop.


func reset_arrangement() -> void:
	arrangement.current_bar_idx = arrangement.loop_start


func get_current_arrangement_bar() -> PackedInt32Array:
	return arrangement.get_current_bar()


func reset_playing_patterns() -> void:
	for pattern in patterns:
		pattern.is_playing = false
