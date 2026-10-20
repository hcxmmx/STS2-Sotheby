extends Node2D

const FX = preload("res://Sotheby_Hcxmmx/Vfx/effect_player.gd")
const VOICE_DELAY := 0.12
const VOICE_INTERVAL := 0.8
var battle
var actor
var voice
var effect
var ticket := 0
var card_id := ""
var upgraded := false
var age := 0.0
var fx_age := 0.0
var owns_body := false
var emphasis_started := false
var voice_attempted := false
var owns_voice := false
var voice_cooldown := 0.0
var last_voice := ""
var tint_owned := false
var old_tint := Color.WHITE

func initialize(owner_battle, field: SubViewport) -> void:
	battle = owner_battle; actor = battle.actor; voice = battle.voice
	top_level = true; global_transform = Transform2D.IDENTITY
	effect = FX.new(); effect.field_target = field; add_child(effect)
	effect.initialize("ready")
	# Small shared effect: preload its geometry once, without another viewport.
	for frame in effect.meta.frames.size(): effect.read_frame(frame)
	effect.visible = false

func begin(value: int, id: String, is_upgraded: bool) -> void:
	if value == ticket: return
	clear()
	ticket = value; card_id = id; upgraded = is_upgraded
	age = 0.0; fx_age = 0.0; emphasis_started = false; voice_attempted = false
	tick(0.0)

func finish(value: int, _committed: bool) -> void:
	if value == ticket: clear()

func _restore_tint() -> void:
	if tint_owned:
		actor.modulate = old_tint
		tint_owned = false

func release_voice() -> void:
	if owns_voice:
		voice.fade_voice(0.08)
		owns_voice = false

func suspend() -> void:
	# Keep a still-held next card valid while an earlier queued cast executes.
	# The action controller takes the body; existing flight/impact tails survive.
	owns_body = false; effect.visible = false; _restore_tint()
	voice_attempted = true; release_voice()

func clear() -> void:
	ticket = 0; effect.visible = false; _restore_tint(); release_voice()
	if owns_body and actor.current_name() == "posture":
		actor.manual_sampling = false; actor.play("idle", true, 0.16)
	owns_body = false

func _body_available() -> bool:
	if battle.dead or battle.victorious: return false
	if battle.ultimate != null and battle.ultimate.active: return false
	if battle.skill != null and battle.skill.active_body: return false
	if battle.skill_two != null and battle.skill_two.body_active: return false
	return actor.current_name() in ["idle", "sleep", "posture"]

func _voice_id() -> String:
	if battle.settings.ultimate_enabled and card_id == str(battle.settings.ultimate_card): return "1300924"
	if upgraded: return "1300923"
	return "1300922" if last_voice == "1300921" else "1300921"

func tick(delta: float) -> void:
	voice_cooldown = maxf(0, voice_cooldown - delta)
	if ticket == 0: return
	age += delta
	if emphasis_started: fx_age += delta
	if not _body_available():
		if owns_body: suspend()
		return
	if not owns_body:
		actor.manual_sampling = false; actor.play("posture", true, 0.16)
		owns_body = true
		if not emphasis_started:
			emphasis_started = true; fx_age = 0.0
			old_tint = actor.modulate; tint_owned = true
	if tint_owned:
		# Source RGB and .5s pulse; easing is a linear 2D adaptation.
		var pulse := maxf(0, 1.0 - absf(fx_age * 4.0 - 1.0)) if fx_age < 0.5 else 0.0
		actor.modulate = old_tint.lerp(Color(2.119, 1.353, 0.821, 1), pulse)
		if fx_age >= 0.5: _restore_tint()
	effect.visible = fx_age < 1.0
	if effect.visible:
		var bone = actor.sprite.get_skeleton().find_bone("mountbottom")
		effect.position = actor.to_global(Vector2(bone.get_world_x(), bone.get_world_y())) if bone != null else actor.global_position
		var factor: float = actor.global_transform.y.length() / 0.01
		var facing := 1.0 if actor.global_transform.x.x < 0 else -1.0
		effect.scale = Vector2(facing * factor, factor)
		effect.show_time(fx_age)
	if not voice_attempted and age >= VOICE_DELAY:
		voice_attempted = true
		if battle.local_voice and battle.settings.combat_voice and voice_cooldown <= 0 and not voice.playing:
			var id := _voice_id()
			if voice.play_voice(id):
				last_voice = id; owns_voice = true; voice_cooldown = VOICE_INTERVAL

func _exit_tree() -> void:
	_restore_tint()
