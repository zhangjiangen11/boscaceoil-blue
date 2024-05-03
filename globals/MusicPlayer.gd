###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2024 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## Music player component responsible for producing sounds using SiON and
## composition data.
class_name MusicPlayer extends Object

const BEATS_PER_NOTE := 0.0625 # Beat is split into 16 intervals.
const NOTE_LENGTH := 4.0 # In 1/16ths of a beat.
const NOTE_SWING_THRESHOLD := 0.2 # In percent of NOTE_LENGTH.

const NOTE_SWING_MIN := NOTE_SWING_THRESHOLD * NOTE_LENGTH
const NOTE_SWING_MAX := 2 * NOTE_LENGTH - NOTE_SWING_THRESHOLD * NOTE_LENGTH

signal playback_started()
signal playback_tick()
signal playback_paused()
signal playback_stopped()

var _driver: SiONDriver = null
var _music_playing: bool = false
var _swing_active: bool = false

## Playback step of current patterns within the active timeline bar, in notes.
## Caps a current song's pattern size.
var _pattern_time: int = -1

## Driver's buffer size.
var buffer_size: int = 2048


func _init(controller: Node) -> void:
	_driver = SiONDriver.create(buffer_size)
	controller.add_child(_driver)


# Initialization.

func initialize() -> void:
	_driver.set_beat_callback_interval(1) # In 1/16ths of a beat, can only be one of: 1, 2, 4, 8, 16.
	_driver.set_timer_interval(NOTE_LENGTH)
	print("Driver initialized.")


func reset_driver() -> void:
	# SiONDriver.play enables endless streaming. We use the timer callback (a.k.a. a metronome)
	# to supply the stream with new notes to play based on the composition of the current song.
	
	_driver.stop()

	update_driver_bpm()
	_driver.play(null, false)
	print("Driver streaming started.")


func update_driver_bpm() -> void:
	if Controller.current_song:
		_driver.set_bpm(Controller.current_song.bpm)


# Output and streaming control.

func _play_note(pattern: Pattern, instrument: Instrument, note_data: Vector3i, current_time: int) -> void:
	if note_data.x < 0 || note_data.y < 0 || note_data.y != current_time || note_data.z < 1:
		# X — note number is invalid.
		# Y — note position in the pattern is invalid or doesn't match current time.
		# Z — note length is shorter than 1 unit of length.
		return
	if not instrument.is_note_valid(note_data):
		return # Custom validation for different instrument types failed.

	# Update the filter.
	instrument.update_filter()

	# If pattern uses recorded filter values, set them directly.
	if pattern.record_filter_enabled:
		instrument.change_filter_to(pattern.cutoff_graph[current_time], pattern.resonance_graph[current_time], pattern.volume_graph[current_time])

	var note_value := instrument.get_note_value(note_data.x)
	var note_voice := instrument.get_note_voice(note_data.x)
	_driver.note_on(note_value, note_voice, note_data.z * NOTE_LENGTH)


## Called automatically by the driver's timer.
func _playback_step() -> void:
	if not _driver || not _music_playing:
		return

	var song := Controller.current_song
	if not song || song.instruments.is_empty() || song.patterns.is_empty() || not song.arrangement:
		return

	# Prepare the next timeline bar in the arrangement.
	if _pattern_time >= song.pattern_size:
		_pattern_time = 0
		_update_swing()

		song.arrangement.progress_loop()
		song.reset_playing_patterns()

	# Play everything in the current timeline bar.
	var current_bar := song.get_current_arrangement_bar()
	for channel_idx in Arrangement.CHANNEL_NUMBER:
		var pattern_idx := current_bar[channel_idx]
		if pattern_idx < 0:
			continue # No pattern set.

		var pattern := song.patterns[pattern_idx]
		pattern.is_playing = true

		var active_instrument := song.instruments[pattern.instrument_idx]
		for note_idx in pattern.note_amount:
			_play_note(pattern, active_instrument, pattern.notes[note_idx], _pattern_time)

	# Finalize the step
	_pattern_time += 1
	_update_swing()
	playback_tick.emit()


func _update_swing() -> void:
	if not _driver:
		return

	if Controller.current_song.swing == 0:
		if _swing_active:
			_driver.set_timer_interval(NOTE_LENGTH)
			_swing_active = false
		return

	_swing_active = true

	# Swing goes from -10 to 10, F-Swing goes from 0.2 to 1.8
	var fswing: float = NOTE_SWING_MIN + (Controller.current_song.swing + 10.0) * (NOTE_SWING_MAX - NOTE_SWING_MIN) / 20.0
	if _pattern_time % 2 == 0:
		_driver.set_timer_interval(fswing)
	else:
		_driver.set_timer_interval(2 - fswing)


func is_playing() -> bool:
	return _music_playing


func get_pattern_time() -> int:
	return _pattern_time


func get_note_time_length() -> float:
	if not Controller.current_song:
		return 0.0
	
	var beat_length_in_sec := 60.0 / Controller.current_song.bpm
	return beat_length_in_sec * NOTE_LENGTH * BEATS_PER_NOTE


func start_playback() -> void:
	if _music_playing:
		return

	if _pattern_time == -1:
		_pattern_time = 0
	_music_playing = true

	_driver.timer_interval.connect(_playback_step)
	playback_started.emit()


func pause_playback() -> void:
	if not _music_playing:
		return

	_music_playing = false
	_driver.timer_interval.disconnect(_playback_step)
	playback_paused.emit()


func stop_playback() -> void:
	if _music_playing:
		_music_playing = false
		_driver.timer_interval.disconnect(_playback_step)
	
	_pattern_time = -1
	playback_stopped.emit()


func play_note(pattern: Pattern, note_data: Vector3i) -> void:
	var song := Controller.current_song
	if not song || song.instruments.is_empty() || song.patterns.is_empty():
		return
	
	var active_instrument := song.instruments[pattern.instrument_idx]
	_play_note(pattern, active_instrument, note_data, note_data.y)
