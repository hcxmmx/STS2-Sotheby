extends Node2D

const FullTempo=preload("res://Sotheby_Hcxmmx/FullTempo.gd")
var use_full_tempo:=true
var full_wall_time:=0.0

const FX = preload("res://Sotheby_Hcxmmx/Vfx/effect_player.gd")
const Controller = preload("res://Sotheby_Hcxmmx/Vfx/combo_controller.gd")
const Trail = preload("res://Sotheby_Hcxmmx/Vfx/potion_trail.gd")
const SOURCE_HIT := 2.166666666666667
const TARGET_SCALE := 1.5
const CONFIG_PATH := "user://sotheby_skin.cfg"
var actor
var controller
var mode := "combo"
var clock := 0.0
var full_start := -100.0
var active_body := false
var posture_entry_time := -1.0
var posture_entry_clock := -100.0
var enabled := true
var unit := 30.0
var origin := Vector2.ZERO
var facing := 1.0
var factor := 1.0
var meta: Dictionary
var calibration: Dictionary
var flights: Array = []
var impacts: Array = []
var circles: Dictionary = {}
var events: Array = []
var plans: Dictionary = {}
var cast
var field: SubViewport
var refraction: ColorRect
var copy: BackBufferCopy
var copy_region := Rect2()
var external_distortion_rect := Rect2()
var flight_cursor := 0
var impact_cursor := 0
var active_ticket := -1
var bottle_path := PackedVector2Array()
var initialization_ms := 0.0
var pool_growths := 0
var stats := {"attacks":0,"hits":0,"flights":0,"fallback_impacts":0,"reused_impacts":0}

func initialize(value) -> void:
	var init_start:=Time.get_ticks_usec()
	actor=value;top_level=true;global_transform=Transform2D.IDENTITY
	controller=Controller.new()
	var cfg:=ConfigFile.new()
	if cfg.load(CONFIG_PATH)==OK:mode=str(cfg.get_value("visuals","mode","combo"))
	if mode not in ["combo","full"]:mode="combo"
	meta=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Assets/fx/skill1/frames.json"))
	calibration=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Vfx/bottle_size_calibration.json"))
	field=SubViewport.new();field.transparent_bg=true;field.disable_3d=true
	field.size=Vector2i(get_viewport_rect().size);field.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(field)
	cast=_new_fx("cast")
	for i in range(1):flights.append({"fx":_new_fx("flight"),"trail":_new_trail(),"event":{}})
	for i in range(1):impacts.append({"fx":_new_fx("impact"),"start":-100.0,"target":{}})
	for frame in range(45,63):
		for entry in flights[0].fx.read_frame(frame):
			if int(entry.id)==14:bottle_path.append(entry.center);break
	bottle_path.append(Vector2(6,0))
	assert(bottle_path.size()==19)
	copy=BackBufferCopy.new();copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;copy.z_index=70;add_child(copy)
	refraction=ColorRect.new();refraction.mouse_filter=Control.MOUSE_FILTER_IGNORE;refraction.z_index=71
	var sm:=ShaderMaterial.new();sm.shader=load("res://Sotheby_Hcxmmx/Vfx/refraction.gdshader")
	sm.set_shader_parameter("distortion_field",field.get_texture());sm.set_shader_parameter("strength_pixels",4.0)
	refraction.material=sm;add_child(refraction);refraction.visible=false
	_refresh_mapping()
	initialization_ms=float(Time.get_ticks_usec()-init_start)/1000.0

func _new_fx(kind: String):
	var player=FX.new();player.field_target=field
	for i in meta.groups.size():
		var g: Dictionary=meta.groups[i]
		if (kind=="cast" and g.prefab=="cast") or (kind=="flight" and g.prefab=="flight" and absf(float(g.instance_start)-1.5)<.001) or (kind=="circle" and g.source_resource=="sufubi_skill1_03_fazhen") or (kind=="impact" and g.prefab=="target" and g.source_resource!="sufubi_skill1_03_fazhen"):
			player.allowed_groups[i]=true
	add_child(player);player.initialize("skill1");player.gain=.36 if kind=="impact" else .8
	player.local_geometry_scale=TARGET_SCALE
	_clear(player)
	return player

func _new_trail():
	var trail=Trail.new();add_child(trail);trail.visible=false;return trail

func _clear(player) -> void:
	for node in player.nodes:
		if node!=null:node.visible=false
	for glow in player.potion_glows.values():glow.visible=false

func _snapshot(input: Dictionary) -> Dictionary:
	var result: Dictionary=input.duplicate()
	if result.has("node"):
		var node=result.node
		if is_instance_valid(node):result.ref=weakref(node);result.anchor=node.global_position
		result.erase("node")
	return result

func _target_point(target: Dictionary, key: String) -> Vector2:
	var point: Vector2=target.get(key,Vector2.ZERO)
	if target.has("ref"):
		var node=target.ref.get_ref()
		if is_instance_valid(node):point+=node.global_position-Vector2(target.anchor)
	return point

func plan_attack(ticket: int, targets: Array, delay: float, fast: bool, random_visual: bool=false) -> void:
	var snapshots: Array=[]
	for target in targets:snapshots.append(_snapshot(target))
	plans[ticket]={"random_visual":random_visual,"confirmed_target_ids":{},"targets":snapshots,"delay":maxf(0,delay),"fast":fast,"started":false,"time":clock}
	# Expire stale plans, including aborted attacks; retain only a bounded history.
	for old in plans.keys():
		if clock-float(plans[old].time)>10:plans.erase(old)
	active_ticket=ticket

func start_attack() -> void:
	if not enabled:return
	if active_ticket<0 or not plans.has(active_ticket):
		active_ticket=-1;_start_body(false);return
	var plan: Dictionary=plans[active_ticket]
	if plan.started:return
	plan.started=true;plan.time=clock;_start_body(plan.fast)
	for target in plan.targets:
		var delay: float=plan.delay
		# Full mode preserves the original gesture and three-bottle timing.
		if mode=="full":
			for offset in [1.5,1.6,1.666666666666667]:_add_flight(active_ticket,target,offset,.6)
		else:
			var length:=minf(.12,delay*.7)
			if length>=.015:_add_flight(active_ticket,target,delay-length,length)
		if not plan.random_visual:_touch_circle(target,clock,clock+(2.1666667 if mode=="full" else delay))

func _start_body(fast: bool) -> void:
	stats.attacks+=1
	posture_entry_time=-1.0
	if actor.current_name()=="posture":
		var track=actor.sprite.get_animation_state().get_current(0)
		posture_entry_time=track.get_track_time() if track!=null else 0.0
		posture_entry_clock=clock
	full_wall_time=0.0
	actor.manual_sampling=true;active_body=true;full_start=clock
	actor.sample("skill1",0.0 if mode=="full" else Controller.READY,0.0,0.0)
	if mode=="full":
		# Repeated cards restart the original full performance by design.
		for event in events:
			if not event.hit:event.cancelled=true
	else:
		controller.prep_duration=.075 if fast else .10
		controller.advance(clock);controller.request_attack(clock)

func _add_flight(ticket: int, target: Dictionary, delay: float, duration: float) -> void:
	var slot_index: int=-1
	for i in flights.size():
		var previous: Dictionary=flights[i].event
		if previous.is_empty() or previous.cancelled or clock-float(previous.launch)>float(previous.duration)+.13:slot_index=i;break
	if slot_index<0 and flights.size()<24:
		slot_index=flights.size();flights.append({"fx":_new_fx("flight"),"trail":_new_trail(),"event":{}});pool_growths+=1
	if slot_index<0:slot_index=flight_cursor%flights.size()
	var slot: Dictionary=flights[slot_index];flight_cursor+=1
	if not slot.event.is_empty():slot.event.cancelled=true
	var event: Dictionary={"ticket":ticket,"target":target,"launch":clock+delay,"duration":duration,"hit":false,"cancelled":false,"start":Vector2.ZERO,"launched":false,"confirmed":false,"requires_hit_confirmation":bool(plans.get(ticket,{}).get("random_visual",false)),"slot_index":slot_index}
	slot.event=event;events.append(event);stats.flights+=1

func confirm_hit(ticket: int, raw_target: Dictionary) -> void:
	if not enabled:return
	stats.hits+=1
	var target:=_snapshot(raw_target)
	if plans.has(ticket) and not plans[ticket].started:
		active_ticket=ticket;start_attack()
	if plans.has(ticket) and plans[ticket].random_visual:
		var confirmed: Dictionary=plans[ticket].confirmed_target_ids
		if confirmed.has(target.id):return
		confirmed[target.id]=true
	_confirm_visual_target(ticket,target)

func _confirm_visual_target(ticket: int, target: Dictionary) -> void:
	if mode=="full":
		var had_flight:=false
		for event in events:
			if event.ticket==ticket and event.target.id==target.id and not event.cancelled:
				event.confirmed=true;had_flight=true
		if not had_flight:
			_add_flight(ticket,target,maxf(0,1.5-(clock-full_start)),.6)
			events.back().confirmed=true
		_touch_circle(target,full_start,full_start+SOURCE_HIT)
		return
	var matched:=false
	for event in events:
		if event.ticket==ticket and event.target.id==target.id and not event.confirmed and not event.cancelled:
			event.confirmed=true;event.hit=true;event.impact_time=clock;matched=true
			# Actual damage dispatch is authoritative. End a late predicted flight.
			if event.launched:event.duration=maxf(.001,clock-float(event.launch))
			break
	if not matched:stats.fallback_impacts+=1
	_spawn_impact(target)
	_touch_circle(target,clock,clock)

func _touch_circle(target: Dictionary, start: float, hit: float) -> void:
	var id: int=target.id
	if not circles.has(id):circles[id]={"fx":_new_fx("circle"),"target":target,"start":start,"hit":hit,"last":clock}
	var ring: Dictionary=circles[id]
	if clock-float(ring.last)>.4:ring.start=start;ring.hit=hit
	ring.target=target;ring.last=clock

func _spawn_impact(target: Dictionary) -> void:
	var slot_index: int=-1
	for i in impacts.size():
		if clock-float(impacts[i].start)>=1.5:slot_index=i;break
	if slot_index<0 and impacts.size()<24:
		slot_index=impacts.size();impacts.append({"fx":_new_fx("impact"),"start":-100.0,"target":{}});pool_growths+=1
	if slot_index<0:slot_index=impact_cursor%impacts.size()
	var slot: Dictionary=impacts[slot_index];impact_cursor+=1
	if clock-float(slot.start)<1.5:stats.reused_impacts+=1
	slot.target=target;slot.start=clock

func _refresh_mapping() -> void:
	factor=absf(actor.global_scale.y)
	unit=actor.bounds().size.y*factor/250.0*30.0 if not active_body else unit
	# Use the stable idle bounds supplied by Battle, not animated per-frame bounds.
	if actor.has_meta("idle_height"):unit=float(actor.get_meta("idle_height"))*factor/250.0*30.0
	unit=maxf(unit,1.0)
	# A reflected X scale decomposes into a rotation and negative Y in Godot.
	# Read the actual basis to keep the VFX reflection aligned with the skeleton.
	facing=1.0 if actor.global_transform.x.x<0 else -1.0
	origin=actor.global_position+Vector2(facing*6.0*unit,0)
	field.size=Vector2i(get_viewport_rect().size)
	field.canvas_transform=get_viewport().get_canvas_transform()
	var ratio:=factor/(.01*unit)
	for slot in flights:slot.trail.width_scale=ratio*float(calibration.flight_scale_per_caster_ratio)*unit/30.0

func _position_fx(player, point: Vector2) -> void:
	player.position=point;player.scale=Vector2(facing*unit,unit)
	player.field_root.position=point;player.field_root.scale=player.scale

func _hand() -> Vector2:
	var bone=actor.sprite.get_skeleton().find_bone("mountweapon")
	return actor.to_global(Vector2(bone.get_world_x(),bone.get_world_y())) if bone!=null else actor.global_position+Vector2(0,-unit*2)

func _render_flight(event: Dictionary) -> void:
	var player=flights[int(event.slot_index)].fx;var trail=flights[int(event.slot_index)].trail
	_clear(player);trail.visible=false
	if event.cancelled:return
	var age:=clock-float(event.launch)
	if age<0:return
	if not event.launched:event.launched=true;event.start=_hand()
	var q:=clampf(age/maxf(.001,event.duration),0,1)
	var end:=_target_point(event.target,"center")
	var source_start:=origin+Vector2(facing*-6,-2)*unit
	var source_end:=origin+Vector2(facing*6,0)*unit
	player.flight_geometry_scale=factor/(.01*unit)*float(calibration.flight_scale_per_caster_ratio)
	player.flight_offset_start=(Vector2(event.start)-source_start)/Vector2(facing*unit,unit)
	player.flight_offset_end=(end-source_end)/Vector2(facing*unit,unit)
	_position_fx(player,origin)
	if age<float(event.duration):player.show_time(1.5+q*.6,true)
	var tail_age: float=age-float(event.duration)
	if tail_age<.10:
		var points:=PackedVector2Array()
		for i in range(25):
			var u:=lerpf(maxf(0,q-.5),q,float(i)/24)
			# Recover the accepted baked path, including its arc, not a straight lerp.
			var sample_index:=clampf(u*18,0,18);var index:=int(sample_index)
			var center: Vector2=bottle_path[index].lerp(bottle_path[mini(index+1,18)],sample_index-index)
			points.append(origin+(center+player.flight_offset_start.lerp(player.flight_offset_end,u))*Vector2(facing*unit,unit))
		trail.show_path(points,1.0-clampf(tail_age/.10,0,1))
	if mode=="full" and age>=event.duration and not event.hit and (not event.requires_hit_confirmation or event.confirmed):
		event.hit=true;event.impact_time=clock;_spawn_impact(event.target)

func tick(delta: float) -> void:
	if not enabled:return
	if mode=="full" and use_full_tempo:
		var previous:=FullTempo.sample("skill1",full_wall_time)
		full_wall_time+=delta
		delta=FullTempo.sample("skill1",full_wall_time)-previous
	clock+=delta;_refresh_mapping()
	if active_body:
		var source_time:=clock-full_start
		if mode=="combo":
			controller.advance(clock)
			var pose: Dictionary=controller.pose();source_time=pose.time
			actor.sample(pose.animation,pose.time,pose.from,pose.mix)
			if controller.phase=="idle":active_body=false;actor.manual_sampling=false;actor.play("idle",true,.08)
		else:
			actor.sample("skill1",source_time)
			if source_time>=2.3:active_body=false;actor.manual_sampling=false;actor.play("idle",true,.08)
		_position_fx(cast,origin)
		if posture_entry_time>=0 and clock-posture_entry_clock<.10:
			actor.sample("skill1",source_time,posture_entry_time,clock-posture_entry_clock,"posture",.10)
		var caster_shift: Vector2=actor.global_position-(origin+Vector2(-6*facing*unit,0))
		cast.set_caster_mapping(factor,Vector2(caster_shift.x/facing,caster_shift.y),unit)
		cast.show_time(source_time,true)
	else:_clear(cast)
	for event in events:_render_flight(event)
	events=events.filter(func(event):return not event.cancelled and clock-float(event.launch)<float(event.duration)+.13)
	var bounds:=external_distortion_rect;var has_distortion:=external_distortion_rect.has_area()
	for slot in impacts:
		var age: float=clock-float(slot.start)
		if age>=1.5:_clear(slot.fx);continue
		var ground:=_target_point(slot.target,"ground")
		_position_fx(slot.fx,ground-Vector2(facing*6*unit,0));slot.fx.show_time(SOURCE_HIT+age,true)
		var rect:=Rect2(ground-Vector2(unit*7,unit*9),Vector2(unit*14,unit*12))
		bounds=rect if not has_distortion else bounds.merge(rect);has_distortion=true
	for id in circles.keys():
		var ring: Dictionary=circles[id]
		var start: float=ring.start;var hit: float=ring.hit
		var material_time:=SOURCE_HIT*clampf((clock-start)/maxf(.001,hit-start),0,1)
		var source_time:=material_time
		if clock>=hit:material_time=SOURCE_HIT+clock-hit;source_time=minf(2.9,material_time)
		var release_at:=maxf(float(ring.last)+.4,hit+2.9-SOURCE_HIT)
		if clock>=release_at:source_time=2.9+clock-release_at
		if source_time>=3.6666667:
			_clear(ring.fx)
			if clock-float(ring.last)>10:ring.fx.queue_free();circles.erase(id)
			continue
		_position_fx(ring.fx,_target_point(ring.target,"ground")-Vector2(facing*6*unit,0))
		ring.fx.show_time(source_time,true)
		for i in ring.fx.refined_materials.size():
			if ring.fx.refined_materials[i]!=null:ring.fx.refined_materials[i].set_shader_parameter("effect_time",material_time*float(meta.groups[i].simulation_speed))
	refraction.visible=has_distortion
	if has_distortion:
		# Limit screen sampling to combat-world effect bounds, never the hand/HUD.
		var viewport_size:=get_viewport_rect().size
		var protected_stage:=Rect2(0,viewport_size.y*.12,viewport_size.x,viewport_size.y*.62)
		bounds=bounds.intersection(protected_stage)
		copy.rect=bounds;refraction.position=bounds.position;refraction.size=bounds.size
		refraction.material.set_shader_parameter("stage_rect",Vector4(bounds.position.x/viewport_size.x,bounds.position.y/viewport_size.y,bounds.end.x/viewport_size.x,bounds.end.y/viewport_size.y))

func interrupt(clear_effects: bool=false) -> void:
	active_body=false;actor.manual_sampling=false;controller=Controller.new();_clear(cast)
	if clear_effects:
		events.clear();plans.clear()
		for slot in flights:_clear(slot.fx);slot.trail.visible=false
		for slot in impacts:slot.start=-100;_clear(slot.fx)
		for ring in circles.values():ring.last=-100;ring.start=-100;ring.hit=-100;_clear(ring.fx)
		refraction.visible=false

func set_mode(value: String, persist: bool=false) -> void:
	if value not in ["combo","full"]:return
	interrupt(true);actor.play("idle",true,.08);mode=value
	if persist:
		var cfg:=ConfigFile.new();cfg.load(CONFIG_PATH);cfg.set_value("visuals","mode",mode);cfg.save(CONFIG_PATH)
	print("[SothebySkin] Skill1 mode=",mode)
