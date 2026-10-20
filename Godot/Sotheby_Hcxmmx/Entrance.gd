extends Node2D

const FX = preload("res://Sotheby_Hcxmmx/Vfx/effect_player.gd")
# FightWorkEntityBornLegacy: friendly fade at .7s, reveal over .1s,
# then release born; buff_chuchang lasts 1.5s. Visual time only.
const REVEAL_START := 0.7
const REVEAL_DURATION := 0.1
const EFFECT_DURATION := 1.5
var actor
var effect
var active := false
var started_once := false
var frozen := false
var age := 0.0
var original_alpha := 1.0

func initialize(body, field: SubViewport) -> void:
	actor = body
	top_level = true; global_transform = Transform2D.IDENTITY
	effect = FX.new(); effect.field_target = field; add_child(effect)
	effect.initialize("entry")
	# Retain the source renderer's front/back order around the actor at Z=0.
	for i in effect.nodes.size(): effect.nodes[i].z_index = int(effect.meta.groups[i].order)
	for frame in effect.meta.frames.size(): effect.read_frame(frame)
	effect.visible = false

func start() -> void:
	# Configure and the native Intro notification can both fire in one room.
	if started_once: return
	started_once = true; active = true; age = 0.0
	original_alpha = actor.modulate.a
	actor.manual_sampling = true; frozen = true
	actor.sample("born", 0.0)
	actor.modulate.a = 0.0
	effect.visible = true
	tick(0.0)

func tick(delta: float) -> void:
	if not active: return
	age += delta
	if age >= EFFECT_DURATION:
		cancel()
		return
	actor.modulate.a = original_alpha * clampf((age - REVEAL_START) / REVEAL_DURATION, 0.0, 1.0)
	if frozen and age >= REVEAL_START + REVEAL_DURATION:
		frozen = false; actor.manual_sampling = false
		actor.once("born")
	# Empty source hang point means entity root, not mountbottom.
	effect.position = actor.global_position
	var factor: float = actor.global_transform.y.length() / 0.01
	var facing := 1.0 if actor.global_transform.x.x < 0 else -1.0
	effect.scale = Vector2(facing * factor, factor)
	effect.show_time(age)

func cancel() -> void:
	if not active: return
	active = false; effect.visible = false
	actor.modulate.a = original_alpha
	# Release only our freeze, before the next action takes manual sampling.
	if frozen:
		frozen = false; actor.manual_sampling = false
		actor.once("born")
	# Leave the next pose to the action controller; no gameplay wait/queue.

func _exit_tree() -> void:
	if is_instance_valid(actor): cancel()
