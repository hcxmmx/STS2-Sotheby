extends Node

const Settings=preload("res://Sotheby_Hcxmmx/Settings.gd")

static var catalog := {}
static var streams := {}
var player: AudioStreamPlayer
var record := {}
var clock := 0.0
var window := 0.0
var playing := false
var gain := 0.8
var voice_volume:=1.0
var muted_for_test := false
var mute_in_background := true
var clip_duration := 0.0
var combat_variant := false
var actor
var fade_remaining:=0.0
var fade_duration:=0.0
var body_done := {}
var last_face := ""
var last_mouth := ""
var face_start := 0.0
var last_clock := 0.0

signal started(id: String)
signal finished

func _ready() -> void:
	add_to_group("sotheby_voices")
	if catalog.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Catalog.json"))
		if parsed != null: catalog = parsed.records
	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_audio_finished)
	reload_settings()

func reload_settings()->void:
	voice_volume=float(Settings.read().voice_volume)
	if player!=null:_update_volume()

func set_gain(value: float) -> void:
	gain = clampf(value, 0, 1)

func play_voice(id: String, use_combat_variant: int = -1) -> bool:
	if not catalog.has(id): return false
	stop_voice()
	record = catalog[id]
	combat_variant = use_combat_variant >= 0 and not record.combat_audio.is_empty()
	var clip: Dictionary = record.combat_audio[use_combat_variant % record.combat_audio.size()] if combat_variant else record.audio
	var path := str(clip.file)
	if not streams.has(path): streams[path] = AudioStreamWAV.load_from_file(path)
	player.stream = streams[path]
	if player.stream == null: return false
	clip_duration = float(clip.duration)
	window = clip_duration if combat_variant or actor == null else maxf(clip_duration, float(record.window))
	clock = 0.0
	last_clock = 0.0
	body_done.clear()
	last_face = ""
	last_mouth = ""
	playing = true
	_update_volume()
	player.play()
	started.emit(id)
	return true

func stop_voice() -> void:
	fade_remaining=0.0
	if player != null: player.stop()
	playing = false
	if actor != null and actor.valid:
		actor.portrait_idle()

func _audio_finished() -> void:
	if playing and not player.playing: clock = maxf(clock, clip_duration)

func _update_volume() -> void:
	var focus_muted := mute_in_background and not DisplayServer.window_is_focused()
	var fade:=clampf(fade_remaining/fade_duration,0,1) if fade_remaining>0 and fade_duration>0 else 1.0
	player.volume_db = -80.0 if muted_for_test or focus_muted else linear_to_db(maxf(0.0001, gain*voice_volume*fade))

func fade_voice(duration:float)->void:
	if not playing:return
	fade_duration=maxf(.001,duration);fade_remaining=fade_duration

func _process(delta: float) -> void:
	if player == null: return
	if fade_remaining>0:
		fade_remaining=maxf(0,fade_remaining-delta)
		if fade_remaining<=0:stop_voice()
	_update_volume()
	if not playing: return
	if player.playing:
		var sound_clock := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		clock = maxf(last_clock, sound_clock)
	else:
		clock += delta
	clock = maxf(0, clock)
	last_clock = clock
	if actor != null and actor.valid and not combat_variant: _apply_layers()
	if clock >= window:
		stop_voice()
		finished.emit()

func _segment(kind: String) -> Dictionary:
	for segment in record[kind]:
		if segment.get("start_seconds") == null or segment.get("end_seconds") == null: continue
		if clock >= float(segment.start_seconds) and clock < float(segment.end_seconds): return segment
	return {}

func _apply_layers() -> void:
	for i in range(record.body.size()):
		var segment: Dictionary = record.body[i]
		if body_done.has(i) or segment.get("start_seconds") == null: continue
		if clock >= float(segment.start_seconds):
			body_done[i] = true
			var name_value := str(segment.animation_name)
			if actor.has_animation(name_value):
				actor.play(name_value, bool(segment.loop), 0.2 if segment.mix_seconds == null else float(segment.mix_seconds))
				if not bool(segment.loop): actor.sprite.get_animation_state().add_animation("b_idle", 0, true, 0)
	var face := _segment("face")
	var face_name := str(face.get("animation_name", "e_idle"))
	if face_name != last_face:
		actor.layer(1, face_name, bool(face.get("loop", true)), 0.3 if face_name.contains("_biyan") else 0.5)
		if not face_name.contains("_biyan") and (not face.is_empty() or not last_face.is_empty()):
			actor.face_transition(not last_face.contains("_biyan"))
		last_face = face_name
	var mouth := _segment("mouth")
	# An interval gap is not a configured closed-mouth pose. Official
	# SpineVoiceMouth force-clears between segments and releases the final
	# non-looping bizui via checkMouthEnd; this model's bizui duration is zero.
	# Keep explicit bizui segments, but let the face supply its own resting
	# mouth throughout unconfigured gaps/tails, independently of body/audio.
	var mouth_name := str(mouth.get("animation_name", ""))
	if mouth_name != last_mouth:
		if mouth_name.is_empty():
			actor.sprite.get_animation_state().set_empty_animation(2, 0.0)
		else:
			actor.layer(2, mouth_name, true, 0.12)
		last_mouth = mouth_name

func subtitle() -> String:
	if not playing or combat_variant or clock >= clip_duration: return ""
	var text := ""
	for segment in record.subtitles:
		if segment.start_seconds != null and clock >= float(segment.start_seconds): text = str(segment.text)
	return text
