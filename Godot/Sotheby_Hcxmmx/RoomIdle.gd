extends Node2D

const ActorScript = preload("res://Sotheby_Hcxmmx/Actor.gd")
var actor
var sources: Array = []
var saved: Array = []
var source_bounds := Rect2()
var idle_bounds := Rect2()
var configured := false
var ready_ok := false
var room_kind := ""
var reference_height := 0.0

func _ready() -> void:
	actor=ActorScript.new();add_child(actor)
	ready_ok=actor.initialize("fight")
	if ready_ok:idle_bounds=actor.bounds();actor.play("idle",true,0)
	visible=false

func configure(originals: Array, kind: String) -> bool:
	if configured:return true
	if not ready_ok or originals.is_empty():return false
	room_kind=kind
	for original in originals:
		if not is_instance_valid(original):continue
		sources.append(weakref(original))
		saved.append({"visible":original.visible,"color":original.modulate})
	if sources.is_empty():return false
	var first=sources[0].get_ref()
	if first.has_method("get_skeleton"):
		var skeleton=first.get_skeleton()
		if skeleton!=null:source_bounds=skeleton.get_bounds()
	if source_bounds.size.y<=0:return false
	reference_height=source_bounds.size.y*absf(first.scale.y)
	# Retain the native feet/seat anchor and this room variant's native height.
	configured=true;visible=true;_sync()
	print("[SothebySkin] ",kind," idle attached; native local height=",reference_height)
	return true

func _sync() -> void:
	if not configured or sources.is_empty():return
	var first=sources[0].get_ref()
	if not is_instance_valid(first):return
	for ref in sources:
		var original=ref.get_ref()
		if is_instance_valid(original):original.hide();original.modulate=Color(original.modulate,0)
	# Match this room's native visible skeleton, including its own scene scale.
	# Ancestor scales then affect the original and replacement identically.
	var factor:=reference_height/maxf(1,idle_bounds.size.y)
	var direction: float=1.0 if first.scale.x<0 else -1.0
	actor.scale=Vector2(direction*factor,factor)
	var ground: Vector2=first.position+Vector2(source_bounds.get_center().x*first.scale.x,source_bounds.end.y*first.scale.y)
	actor.position=ground-Vector2(idle_bounds.get_center().x*actor.scale.x,idle_bounds.end.y*factor)

func _process(_delta: float) -> void:
	_sync()

func _exit_tree() -> void:
	for i in sources.size():
		var original=sources[i].get_ref()
		if is_instance_valid(original):original.visible=saved[i].visible;original.modulate=saved[i].color
