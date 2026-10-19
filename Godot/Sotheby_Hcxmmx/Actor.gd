extends Node2D

static var cache := {}
var sprite
var data
var variant := ""
var valid := false
var manual_sampling := false

func initialize(kind: String) -> bool:
	variant = kind
	if not ClassDB.class_exists("SpineSprite"):
		push_error("[SothebySkin] Game Spine runtime is unavailable.")
		return false
	if not cache.has(kind):
		var stem := "300901_sufubi_p" if kind == "portrait" else "300901_sufubi"
		var base := "res://Sotheby_Hcxmmx/Assets/" + ("portrait/" if kind == "portrait" else "battle/")
		var file_name := stem + ".skel" if kind == "portrait" else stem + "_fight.skel"
		if not FileAccess.file_exists(base + file_name) or not ResourceLoader.exists(base + stem + ".png"):
			push_warning("[SothebySkin] Incomplete skeleton/texture package; keeping the official visuals.")
			return false
		# Resolve the imported texture before calling the native atlas loader.
		# That loader cannot recover safely from a missing texture.
		var texture = load(base + stem + ".png")
		if texture == null: return false
		var skeleton = ClassDB.instantiate("SpineSkeletonFileResource")
		skeleton.load_from_file(base + file_name)
		var atlas = ClassDB.instantiate("SpineAtlasResource")
		atlas.load_from_atlas_file(base + stem + ".atlas")
		var resource = ClassDB.instantiate("SpineSkeletonDataResource")
		resource.skeleton_file_res = skeleton
		resource.atlas_res = atlas
		resource.default_mix = 0.2
		if resource.get_animations().is_empty(): return false
		cache[kind] = resource
	data = cache[kind]
	sprite = ClassDB.instantiate("SpineSprite")
	sprite.set_skeleton_data_res(data)
	sprite.set_update_mode(2)
	add_child(sprite)
	valid = true
	play("b_idle" if kind == "portrait" else "idle", true, 0.0)
	if kind == "portrait":
		layer(1, "e_idle", true, 0.0)
	sprite.update_skeleton(0.01)
	return true

func has_animation(animation: String) -> bool:
	return valid and data.find_animation(animation) != null

func portrait_idle(mix: float = 0.5) -> void:
	if not valid or variant != "portrait": return
	play("b_idle", true, mix)
	layer(1, "e_idle", true, mix)
	# BaseSpine.playStory starts only body/face. The official voice stop
	# empties mouth/transition instead of holding bizui/zhengyan forever.
	sprite.get_animation_state().set_empty_animation(2, 0.0)
	sprite.get_animation_state().set_empty_animation(3, 0.0)

func face_transition(close_eyes: bool) -> void:
	layer(3, "h_biyan" if close_eyes else "h_zhengyan", false, 0.0)
	# SpineVoiceFace._stopTransition releases the overlay after one second.
	sprite.get_animation_state().add_empty_animation(3, 0.0, 1.0)

func play(animation: String, looped: bool, mix: float = 0.2) -> void:
	layer(0, animation, looped, mix)

func layer(track: int, animation: String, looped: bool, mix: float = 0.2) -> void:
	if not has_animation(animation): return
	var entry = sprite.get_animation_state().set_animation(animation, looped, track)
	if entry != null: entry.set_mix_duration(mix)

func once(animation: String, return_idle: bool = true) -> void:
	play(animation, false)
	if return_idle:
		sprite.get_animation_state().add_animation("b_idle" if variant == "portrait" else "idle", 0, true, 0)

func current_name() -> String:
	if not valid: return ""
	var entry = sprite.get_animation_state().get_current(0)
	return str(entry.get_animation().get_name()) if entry != null else ""

func bounds() -> Rect2:
	return sprite.get_skeleton().get_bounds() if valid else Rect2()

func _process(delta: float) -> void:
	if valid and not manual_sampling: sprite.update_skeleton(delta)

func sample(animation: String, at: float, blend_from: float=-1.0, blend_elapsed: float=.08, blend_animation: String="skill1", blend_duration: float=.08) -> void:
	if not valid:return
	var state=sprite.get_animation_state()
	state.clear_tracks();sprite.get_skeleton().set_to_setup_pose()
	if blend_from>=0 and blend_elapsed<blend_duration:
		var old=state.set_animation(blend_animation,blend_animation=="idle",0)
		old.set_mix_duration(0.0);old.set_track_time(blend_from);sprite.update_skeleton(0.0)
	var track=state.set_animation(animation,animation=="idle",0)
	track.set_track_time(at);track.set_mix_duration(blend_duration if blend_from>=0 and blend_elapsed<blend_duration else 0.0)
	if blend_from>=0 and blend_elapsed<blend_duration:track.set_mix_time(blend_elapsed)
	sprite.update_skeleton(0.0)
