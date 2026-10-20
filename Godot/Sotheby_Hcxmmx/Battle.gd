extends Node2D

const ActorScript = preload("res://Sotheby_Hcxmmx/Actor.gd")
const SkillScript = preload("res://Sotheby_Hcxmmx/SkillOne.gd")
const SkillTwoScript = preload("res://Sotheby_Hcxmmx/SkillTwo.gd")
const VoiceScript = preload("res://Sotheby_Hcxmmx/Voice.gd")
const Settings=preload("res://Sotheby_Hcxmmx/Settings.gd")
const SelectionScript=preload("res://Sotheby_Hcxmmx/CardSelection.gd")
var selection
var settings:Dictionary
var ultimate
var ultimate_cache
var bound_card_active:=false
var actor
var skill
var skill_two
var mode_label: Label
var mode_label_time := 0.0
var voice
var original_visible := true
var original_color := Color.WHITE
var original_body: Node2D
var ready_ok := false
var local_voice := true
var dead := false
var victorious := false
var configured := false
var voice_cooldown := 0.0
var visual_cooldown := 0.0
var rng := RandomNumberGenerator.new()
var cached_bounds := Rect2()
var desired_center := 0.0
var last_voice := ""

func _ready() -> void:
	add_to_group("sotheby_battles")
	settings=Settings.read()
	set_meta("sotheby_floor_host",true)
	rng.randomize()
	actor = ActorScript.new()
	add_child(actor)
	ready_ok = actor.initialize("fight")
	if not ready_ok: return
	voice = VoiceScript.new()
	add_child(voice)
	cached_bounds = actor.bounds()

func is_ready() -> bool:
	return ready_ok

func configure(body: Node2D, bounds_position: Vector2, bounds_size: Vector2, audible: bool) -> bool:
	if not ready_ok or bounds_size.x <= 0 or bounds_size.y <= 0: return false
	original_body = body
	original_visible=body.visible;original_color=body.modulate
	local_voice = audible
	var desired := Rect2(bounds_position, bounds_size)
	desired_center=desired.get_center().x
	var factor := minf(desired.size.x * 0.95 / cached_bounds.size.x, desired.size.y / cached_bounds.size.y)
	actor.scale = Vector2(-factor,factor)
	actor.position = Vector2(desired.get_center().x - cached_bounds.get_center().x * actor.scale.x, desired.end.y - cached_bounds.end.y * factor)
	actor.set_meta("idle_height",cached_bounds.size.y)
	actor.set_meta("idle_center_x",cached_bounds.get_center().x)
	actor.set_meta("idle_bottom",cached_bounds.end.y)
	skill=SkillScript.new();add_child(skill);skill.initialize(actor)
	skill_two=SkillTwoScript.new();add_child(skill_two);skill_two.initialize(actor,skill)
	selection=SelectionScript.new();add_child(selection);selection.initialize(self,skill.field)
	configured = true
	# Native hurt/death tweens may restore alpha after our _process. Enforce
	# transparency immediately before drawing, without hiding/reparenting Spine.
	RenderingServer.frame_pre_draw.connect(_hide_original)
	_hide_original()
	actor.once("born")
	_speak(["1300920"], true)
	return true

func _speak(ids: Array, priority: bool = false, hit: bool = false) -> void:
	if selection!=null:selection.release_voice()
	if not local_voice or not settings.combat_voice or (voice_cooldown > 0 and not priority): return
	var options := ids.duplicate()
	if options.size() > 1: options.erase(last_voice)
	var id := str(options[rng.randi_range(0, options.size() - 1)])
	last_voice = id
	if hit:
		# The original bank also has a silence branch. This first skin build
		# uses the verified audible alternatives with a local cooldown.
		voice.play_voice(id, rng.randi_range(0, 1))
	else:
		voice.play_voice(id)
	voice_cooldown = float(settings.combat_voice_interval)

func handle_trigger(trigger: String) -> void:
	if not ready_ok or dead or victorious: return
	if bound_card_active and trigger in ["Attack","AttackSingle","AttackTriple","Shiv","Cast","PowerUp","Idle"]:return
	if selection!=null and trigger!="Idle":
		if trigger in ["Dead","Die","Death"]:selection.clear()
		else:selection.suspend()
	if ultimate!=null and trigger in ["Dead","Die","Death","Hit"]:
		if trigger=="Hit":ultimate.interrupt()
		else:ultimate.cancel()
	match trigger:
		"Dead", "Die", "Death":
			dead = true
			if skill_two!=null:skill_two.interrupt(true)
			if skill!=null:skill.interrupt(true);skill.enabled=false
			voice.stop_voice()
			actor.once("die", false)
		"Attack", "AttackSingle", "AttackTriple", "Shiv":
			if skill_two!=null:skill_two.interrupt()
			if skill!=null:skill.start_attack()
			else:actor.once("skill1")
			_speak(["1300925", "1300926"])
		"Cast", "PowerUp":
			if skill!=null:skill.interrupt()
			if skill_two!=null:skill_two.start(skill.mode)
			else:actor.once("skill2")
			_speak(["1300927", "1300928"])
		"Hit":
			if skill_two!=null:skill_two.interrupt()
			if skill!=null:skill.interrupt()
			actor.once("hit")
			_speak(["1300930", "1300931"], false, true)
		"Intro":
			actor.once("born")
		"Relaxed":
			actor.once("idle_special1")
		"Idle":
			# Keep local one-shots independent of the original animation duration.
			if actor.current_name() in ["idle", "sleep"]: actor.play("idle", true)

func request_victory() -> void:
	if not ready_ok or dead or victorious: return
	victorious = true
	if selection!=null:selection.clear()
	if ultimate!=null:ultimate.cancel()
	if skill_two!=null:skill_two.interrupt(true)
	if skill!=null:skill.interrupt(true);skill.enabled=false
	actor.once("victory", false)
	_speak(["1300932"], true)

func set_audio_policy(gain: float, background_mute: bool) -> void:
	if voice != null:
		voice.set_gain(gain)
		voice.mute_in_background = background_mute

func _process(delta: float) -> void:
	voice_cooldown = maxf(0, voice_cooldown - delta)
	visual_cooldown = maxf(0, visual_cooldown - delta)
	if configured and is_instance_valid(original_body):
		_hide_original()
		actor.scale.x = absf(actor.scale.x) * (1.0 if original_body.scale.x < 0 else -1.0)
		actor.position.x=cached_desired_center()-cached_bounds.get_center().x*actor.scale.x
	if skill_two!=null:skill_two.tick(delta)
	if skill!=null:skill.tick(delta)
	if ultimate!=null:ultimate.tick(delta)
	if selection!=null:selection.tick(delta)
	if mode_label_time>0:
		mode_label_time-=delta
		if mode_label_time<=0 and is_instance_valid(mode_label):mode_label.visible=false

func cached_desired_center() -> float:
	return desired_center

func plan_attack(ticket: int, targets: Array, delay: float, fast: bool, random_visual: bool=false) -> void:
	if skill!=null and not dead and not victorious and not bound_card_active:skill.plan_attack(ticket,targets,delay,fast,random_visual)

func confirm_hit(ticket: int, target: Dictionary) -> void:
	if skill!=null and not dead and not victorious and not bound_card_active:skill.confirm_hit(ticket,target)

func card_played(card_id:String,targets:Array=[])->void:
	if not configured or dead or victorious:return
	if selection!=null:selection.suspend()
	bound_card_active=bool(settings.ultimate_enabled) and card_id==str(settings.ultimate_card)
	if not bound_card_active:
		if ultimate!=null and ultimate.active:
			ultimate.interrupt();voice.fade_voice(.15)
		return
	if skill_two!=null:skill_two.interrupt(true)
	if skill!=null:skill.interrupt(true)
	actor.manual_sampling=false;actor.play("idle",true,.08)
	if ultimate==null:
		ultimate_cache=get_tree().get_first_node_in_group("sotheby_ultimate_cache")
		if ultimate_cache!=null:ultimate=ultimate_cache.acquire()
		if ultimate==null:
			ultimate_cache=null
			ultimate=load("res://Sotheby_Hcxmmx/Ultimate.gd").new();add_child(ultimate)
	ultimate.start(actor,settings,targets)
	_speak(["1300929"],true)

func card_selection_begin(ticket:int,card_id:String,upgraded:bool)->void:
	if configured and local_voice and not dead and not victorious:
		selection.begin(ticket,card_id,upgraded)

func card_selection_end(ticket:int,committed:bool)->void:
	if selection!=null:selection.finish(ticket,committed)

func reload_settings()->void:
	var previous:Dictionary=settings
	settings=Settings.read()
	var changed_performance:=false
	for key in ["mode","ultimate_enabled","ultimate_mode","ultimate_card","ultimate_camera","ultimate_post","ultimate_shake"]:
		if previous.get(key)!=settings.get(key):changed_performance=true
	if ultimate!=null and ultimate.active and changed_performance:ultimate.cancel()
	voice_cooldown=minf(voice_cooldown,float(settings.combat_voice_interval))
	if skill!=null and skill.mode!=settings.mode:
		if skill_two!=null:skill_two.interrupt(true)
		skill.set_mode(settings.mode)
	if not settings.combat_voice and voice!=null:voice.stop_voice()

func _unhandled_key_input(event: InputEvent) -> void:
	if not local_voice or skill==null:return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8:
		if ultimate!=null:ultimate.cancel()
		if skill_two!=null:skill_two.interrupt(true)
		skill.set_mode("full" if skill.mode=="combo" else "combo",true)
		settings=Settings.read()
		if mode_label==null:
			var canvas:=CanvasLayer.new();canvas.layer=50;add_child(canvas)
			mode_label=Label.new();mode_label.position=Vector2(32,135);mode_label.add_theme_font_size_override("font_size",24);canvas.add_child(mode_label)
		mode_label.text="苏芙比 · "+("动作接续" if skill.mode=="combo" else "完整演出")+"  [F8]"
		mode_label.visible=true;mode_label_time=2.5

func _hide_original() -> void:
	if not is_instance_valid(original_body):return
	# Native form VFX still read this Spine's world-bone transforms. Hide()
	# can leave its follower at world origin; retain bone updates transparently.
	original_body.show()
	original_body.modulate=Color(original_body.modulate,0.0)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_hide_original):RenderingServer.frame_pre_draw.disconnect(_hide_original)
	if selection!=null:selection.clear()
	if is_instance_valid(ultimate):ultimate.cancel()
	if is_instance_valid(ultimate_cache):ultimate_cache.release(ultimate)
	if configured and is_instance_valid(original_body):
		original_body.visible=original_visible
		original_body.modulate=original_color
