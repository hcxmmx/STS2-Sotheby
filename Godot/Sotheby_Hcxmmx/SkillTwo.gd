extends Node2D

const FullTempo=preload("res://Sotheby_Hcxmmx/FullTempo.gd")
var use_full_tempo:=true
var full_wall_time:=0.0

const FX = preload("res://Sotheby_Hcxmmx/Vfx/effect_player.gd")
const Combo = preload("res://Sotheby_Hcxmmx/SkillTwoCombo.gd")
const BURST_DURATION := 1.84
var actor
var combat
var player
var clip: Control
var active := false
var body_active := false
var elapsed := 0.0
var source_time := 0.0
var mode := "combo"
var controller = Combo.new()
var clock := 0.0
var hand_player
var bursts: Array = []
var ground_time := 0.0
var ground_material_time := 0.0
var combo_started := 0.0
var last_burst := -100.0
var last_cycle := 0
var anchors: Array = []
var entry_animation := "idle"
var entry_time := 0.0
var entry_clock := 0.0
var stats := {"requests":0,"bursts":0,"peak_bursts":0}

func initialize(value, shared_combat) -> void:
	actor=value;combat=shared_combat
	top_level=true;global_transform=Transform2D.IDENTITY

func _ensure_player() -> void:
	if player!=null:return
	clip=Control.new();clip.clip_contents=true;clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(clip)
	player=FX.new();player.field_target=combat.field;clip.add_child(player)
	player.initialize("skill2")
	_clear()

func _new_combo_player(first: int, last: int):
	var fx=FX.new();fx.field_target=combat.field
	for i in range(first,last+1):fx.allowed_groups[i]=true
	clip.add_child(fx);fx.initialize("skill2");_hide(fx)
	return fx

func _ensure_combo() -> void:
	if hand_player!=null:return
	hand_player=_new_combo_player(33,38)
	anchors=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Vfx/bone_anchors.json")).animations.skill2.frames
	bursts.append({"fx":_new_combo_player(17,32),"start":-100.0})

func start(value: String) -> void:
	_ensure_player();stats.requests+=1
	if value=="full":
		full_wall_time=0.0
		_clear_combo();controller=Combo.new();mode=value;elapsed=0;source_time=0;active=true;body_active=true
		actor.manual_sampling=true;actor.sample("skill2",0);tick(0);return
	_ensure_combo()
	if not active or mode!="combo":
		_clear();_clear_combo();controller=Combo.new();ground_time=0;ground_material_time=0;combo_started=clock;last_burst=-100;last_cycle=0
	elif controller.phase=="idle":
		# Restart a finished ground fade at its stable sustain pose, preserving
		# the current field instead of clearing and re-expanding it.
		ground_time=minf(ground_time,2.3)
	mode="combo";active=true;body_active=true;actor.manual_sampling=true
	if controller.phase=="idle":
		entry_animation=actor.current_name();entry_clock=clock
		var track=actor.sprite.get_animation_state().get_current(0)
		entry_time=track.get_track_time() if track!=null else 0.0
	controller.request(clock);tick(0)

func _hide(fx) -> void:
	if fx==null:return
	for node in fx.nodes:
		if node!=null:node.visible=false

func _clear_combo() -> void:
	_hide(hand_player)
	for slot in bursts:slot.start=-100;_hide(slot.fx)

func interrupt(clear_effects: bool=false) -> void:
	var owned_body:=body_active
	body_active=false;controller=Combo.new();last_cycle=0
	if owned_body and actor!=null:actor.manual_sampling=false
	if player!=null:player.visible_kinds.cast=false
	_hide(hand_player)
	if clear_effects:
		active=false;_clear();_clear_combo();combat.external_distortion_rect=Rect2()

func _clear() -> void:
	if player==null:return
	for node in player.nodes:
		if node!=null:node.visible=false

func _burst() -> void:
	var selected: Dictionary={}
	for slot in bursts:
		if clock-float(slot.start)>=BURST_DURATION:selected=slot;break
	if selected.is_empty() and bursts.size()<3:
		selected={"fx":_new_combo_player(17,32),"start":-100.0};bursts.append(selected)
	assert(not selected.is_empty()) # Cycle >=0.62s; original late sparks end by 1.84s.
	selected.start=clock;last_burst=clock;stats.bursts+=1

func tick(delta: float) -> void:
	if active and mode=="full" and use_full_tempo:
		var previous:=FullTempo.sample("skill2",full_wall_time)
		full_wall_time+=delta
		delta=FullTempo.sample("skill2",full_wall_time)-previous
	clock+=delta
	if not active:return
	elapsed+=delta
	if mode=="full":
		source_time=elapsed
		if source_time>=4.3:
			active=false;_clear();combat.external_distortion_rect=Rect2()
			if body_active:actor.manual_sampling=false;actor.play("idle",true,.08);body_active=false
			return
		if body_active:
			if source_time<3.3333333:actor.sample("skill2",source_time)
			else:actor.manual_sampling=false;actor.play("idle",true,.08);body_active=false
	else:
		if body_active:
			controller.advance(clock)
			var pose: Dictionary=controller.pose();source_time=pose.time
			if controller.cycles>last_cycle:_burst();last_cycle=controller.cycles
			if controller.phase=="idle":
				body_active=false;actor.manual_sampling=false;actor.play("idle",true,.10)
			elif controller.phase=="prepare":actor.sample("skill2",pose.time,entry_time,clock-entry_clock,entry_animation,Combo.MIX)
			else:actor.sample("skill2",pose.time,pose.from,pose.mix,"skill2",Combo.MIX)
		ground_material_time=_compressed(clock-combo_started)
		if ground_time<2.3:ground_time=minf(ground_material_time,2.3)
		elif clock>=maxf(controller.last_request+.4,last_burst+.8):ground_time+=delta
		if ground_time>=4.3 and not body_active and bursts.all(func(slot):return clock-float(slot.start)>=BURST_DURATION):
			active=false;_clear();_clear_combo();combat.external_distortion_rect=Rect2();return

	var factor: float=actor.global_transform.y.length()
	var direction: float=1.0 if actor.global_transform.x.x<0 else -1.0
	var height: float=float(actor.get_meta("idle_height"))*factor
	# Preserve the accepted complete preview: 54 pixels/world unit at 300px
	# idle height, with ground effects rooted at the idle feet, not Spine origin.
	var unit: float=height*54.0/300.0
	var ground: Vector2=actor.to_global(Vector2(float(actor.get_meta("idle_center_x")),float(actor.get_meta("idle_bottom"))))
	var origin: Vector2=ground+Vector2(direction*6*unit,0)
	var root_offset:=Vector2((actor.global_position.x-ground.x)/direction,actor.global_position.y-ground.y)
	clip.position=ground-Vector2(height*3.0,height*1.7)
	clip.size=Vector2(height*6.0,height*2.02)
	_map(player,origin,unit,direction,factor,root_offset)
	if mode=="full":
		player.visible_kinds.cast=body_active;player.show_time(source_time,true)
	else:
		player.visible_kinds.cast=false;player.show_time(minf(ground_time,4.3),true)
		for i in range(17):
			if player.refined_materials[i]!=null:player.refined_materials[i].set_shader_parameter("effect_time",ground_material_time*float(player.meta.groups[i].simulation_speed))
		if body_active:
			# Follow the actually mixed hand pose through a rejoin, rather than
			# snapping its glow to the unblended destination frame.
			var bone=actor.sprite.get_skeleton().find_bone("mountweapon")
			var frame:=clampf(source_time*30,0,anchors.size()-1)
			var left: Array=anchors[int(frame)].mountweapon
			var right: Array=anchors[mini(int(frame)+1,anchors.size()-1)].mountweapon
			var expected: Vector2=actor.to_global(Vector2(lerpf(left[0],right[0],frame-floorf(frame)),lerpf(left[1],right[1],frame-floorf(frame))))
			var shift: Vector2=actor.to_global(Vector2(bone.get_world_x(),bone.get_world_y()))-expected
			_map(hand_player,origin,unit,direction,factor,root_offset+Vector2(shift.x/direction,shift.y))
			hand_player.show_time(source_time,true)
		else:_hide(hand_player)
		var live:=0
		for slot in bursts:
			var age: float=clock-float(slot.start)
			if age>=BURST_DURATION:_hide(slot.fx);continue
			live+=1;_map(slot.fx,origin,unit,direction,factor,root_offset);slot.fx.show_time(1.6+age,true)
		stats.peak_bursts=maxi(stats.peak_bursts,live)
	# Reuse the combat refraction compositor; keep sampling behind HUD/hand.
	combat.external_distortion_rect=Rect2(actor.global_position-Vector2(unit*7,unit*10),Vector2(unit*14,unit*13))

func _compressed(time: float) -> float:
	return time/.12*1.1 if time<.12 else 1.1+time-.12

func _map(fx, origin: Vector2, unit: float, direction: float, factor: float, root_offset: Vector2) -> void:
	fx.position=origin-clip.position;fx.scale=Vector2(direction*unit,unit)
	fx.field_root.position=origin;fx.field_root.scale=fx.scale
	fx.set_caster_mapping(factor,root_offset,unit)
