extends CanvasLayer

const FullTempo=preload("res://Sotheby_Hcxmmx/FullTempo.gd")
var use_full_tempo:=true
var full_wall_time:=0.0

const EffectPlayer=preload("res://Sotheby_Hcxmmx/Ultimate/effect_player.gd")
const Rhythm=preload("res://Sotheby_Hcxmmx/Ultimate/rhythm_clock.gd")
const UNIT:=76.0
const ORIGIN:=Vector2(692,446)
const STAGE_RECT:=Rect2(28,202,1384,558)
const DURATION:=10.2
var world:Node2D
var mapping:Node2D
var clip:Control
var fx
var actor
var temporary
var actor_data
var backdrop:Backdrop
var post:ColorRect
var live_actor
var progressive_loading:=false
var prepared:=false
var active:=false
var elapsed:=0.0
var rhythm:=true
var camera_enabled:=true
var post_enabled:=true
var shake_enabled:=true
var interrupt_at:=-1.0
var interrupt_transform:=Transform2D.IDENTITY
var return_transform:=Transform2D.IDENTITY
var camera_clips:Array=[]
var stage:=Rect2()
var targets:Array=[]
var target_shift:=Vector2.ZERO
var stats:={"starts":0,"interrupts":0,"finishes":0}

func _ready()->void:
	layer=2
	camera_clips=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Ultimate/camera_decoded.json")).clips
	var root:=Control.new();root.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(root)
	clip=Control.new();clip.clip_contents=true;clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(clip)
	mapping=Node2D.new();clip.add_child(mapping)
	world=Node2D.new();mapping.add_child(world)
	# Preview-only opaque stage paint must never cover the live enemies.
	backdrop=Backdrop.new();backdrop.z_index=-100;backdrop.visible=false;world.add_child(backdrop)
	fx=EffectPlayer.new();fx.position=ORIGIN;fx.scale=Vector2.ONE*UNIT;world.add_child(fx)
	await fx.initialize("unique",progressive_loading)
	fx.gain=.82
	_load_actor()
	var copy:=BackBufferCopy.new();copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;copy.z_index=90;root.add_child(copy)
	post=ColorRect.new();post.z_index=91;post.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material:=ShaderMaterial.new();material.shader=load("res://Sotheby_Hcxmmx/Ultimate/ultimate_post.gdshader");material.set_shader_parameter("distortion_field",fx.field_viewport.get_texture());post.material=material;root.add_child(post)
	visible=false;prepared=true

func start(value,options:Dictionary,snapshots:Array=[])->void:
	live_actor=value;rhythm=options.ultimate_mode=="rhythm";camera_enabled=options.ultimate_camera;post_enabled=options.ultimate_post;shake_enabled=options.ultimate_shake
	targets.clear()
	for snapshot in snapshots:
		var node=snapshot.get("node")
		if is_instance_valid(node):targets.append({"ref":weakref(node),"ground":node.to_local(Vector2(snapshot.ground))})
	full_wall_time=0.0
	interrupt_at=-1.;elapsed=0.;active=true;visible=true;stats.starts+=1
	fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	_update_layout();live_actor.visible=false;seek(0.)

func _duration()->float:
	return Rhythm.LENGTH if rhythm else DURATION

func _update_layout()->void:
	var size:=get_viewport().get_visible_rect().size
	stage=Rect2(size*Vector2(.02,.12),size*Vector2(.96,.62))
	clip.position=stage.position;clip.size=stage.size;mapping.scale=stage.size/STAGE_RECT.size
	post.position=stage.position;post.size=stage.size
	post.material.set_shader_parameter("stage_rect",Vector4(stage.position.x/size.x,stage.position.y/size.y,stage.end.x/size.x,stage.end.y/size.y))
	fx.field_viewport.size=Vector2i(size)
	if is_instance_valid(live_actor):
		var anchor:Vector2=live_actor.sprite.get_global_transform_with_canvas().origin
		var ratio:float=live_actor.sprite.get_global_transform_with_canvas().y.length()/(UNIT*.01*mapping.scale.y)
		return_transform=Transform2D(0,Vector2.ONE*ratio,0,(anchor-stage.position)/mapping.scale-(ORIGIN-Vector2(6*UNIT,0))*ratio)
	target_shift=Vector2.ZERO
	var target_center:=Vector2.ZERO;var count:=0
	for target in targets:
		var node=target.ref.get_ref()
		if is_instance_valid(node):target_center+=node.get_global_transform_with_canvas()*Vector2(target.ground);count+=1
	if count>0:
		target_center/=float(count)
		target_shift=(return_transform.affine_inverse()*((target_center-stage.position)/mapping.scale)-(ORIGIN+Vector2(6*UNIT,0)))/UNIT

func tick(delta:float)->void:
	if not active:return
	if not rhythm and use_full_tempo:
		var previous:=FullTempo.sample("unique",full_wall_time)
		full_wall_time+=delta
		delta=FullTempo.sample("unique",full_wall_time)-previous
	_update_layout();elapsed+=delta;seek(elapsed)
	var end_time:=minf(_duration(),interrupt_at+1.8) if interrupt_at>=0 else _duration()
	if elapsed>=end_time:cancel()

func interrupt()->void:
	if not active or interrupt_at>=0:return
	interrupt_at=elapsed;interrupt_transform=world.transform;stats.interrupts+=1
	actor.visible=false;temporary.visible=false
	if is_instance_valid(live_actor):live_actor.visible=true
	seek(elapsed)

func cancel()->void:
	if not active:return
	active=false;visible=false;stats.finishes+=1
	fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if is_instance_valid(live_actor):live_actor.visible=true

func seek(t:float)->void:
	_actor_pose(t);_camera(t)
	if rhythm:
		var clocks:=Rhythm.clocks(t,fx.meta.groups,interrupt_at)
		fx.source_times=clocks.times;fx.source_cutoffs=clocks.cutoffs;fx.source_weights=clocks.weights
	else:fx.source_times={};fx.source_cutoffs={};fx.source_weights={}
	fx.emission_cutoff=interrupt_at if interrupt_at>=0 else 10000.;fx.interrupted_at=interrupt_at;fx.show_time(t,true);_post(t)
	# Preserve the accepted cinematic composition, then align released target
	# effects to actual surviving targets while handing the view back to battle.
	var rejoin:=1.0 if not camera_enabled else (smoothstep(interrupt_at,interrupt_at+.25,t) if interrupt_at>=0 else (smoothstep(2.02,2.38,t) if rhythm else smoothstep(9.,9.5,t)))
	for i in fx.nodes.size():
		if fx.meta.groups[i].prefab=="target":fx.nodes[i].position=target_shift*rejoin
	var end_fade:=1.-smoothstep(2.02,2.70,t) if rhythm else 1.-smoothstep(8.5,9.5,t)
	backdrop.modulate.a=(1.-smoothstep(interrupt_at,interrupt_at+.25,t)) if interrupt_at>=0 else end_fade
	backdrop.film=smoothstep(0.,.6,t);backdrop.queue_redraw()

func _actor_pose(t:float)->void:
	actor.position=ORIGIN+Vector2(-6*UNIT,0);actor.modulate.a=1.
	if interrupt_at>=0:actor.visible=false;temporary.visible=false;return
	if rhythm:
		var source:=Rhythm.sample(t,"ride")
		_sample(actor,"unique",source)
		if source>=1.4:actor.position.x+=3.1*UNIT
		actor.visible=t<1.32;actor.modulate.a=1.-smoothstep(1.20,1.32,t);temporary.visible=false
		if is_instance_valid(live_actor):live_actor.visible=t>=2.02
		return
	_sample(actor,"unique",t)
	if t>=1.4:actor.position.x+=3.1*UNIT
	actor.visible=t<5.566667
	temporary.visible=t>=5.566667 and t<9.166667
	if temporary.visible:
		_sample(temporary,"unique_1",t-5.566667);temporary.position=ORIGIN+Vector2(-6*UNIT,.96*UNIT)
	if is_instance_valid(live_actor):live_actor.visible=t>=8.5

func _exit_tree()->void:
	cancel()

class Backdrop extends Node2D:
	var film:=0.0
	func _draw()->void:
		draw_rect(Rect2(-8000,-5000,16000,10000),Color("#0d1916").lerp(Color("#283b1a"),film))
		for i in range(20,0,-1):
			draw_circle(Vector2(500,220),float(i)*65,Color(.35,.43,.16,.008+film*.007))
		draw_rect(Rect2(-8000,446,16000,3000),Color(.025,.045,.03,.3))
		for x in range(-1500,3500,120):draw_line(Vector2(x,446),Vector2(x+250,800),Color(.3,.38,.23,.09),1,true)


func _load_actor()->void:
	assert(ClassDB.class_exists("SpineSprite"))
	load("res://Sotheby_Hcxmmx/Assets/battle/300901_sufubi.png")
	var skel=ClassDB.instantiate("SpineSkeletonFileResource");skel.load_from_file("res://Sotheby_Hcxmmx/Assets/battle/300901_sufubi_fight.skel")
	var atlas=ClassDB.instantiate("SpineAtlasResource");atlas.load_from_atlas_file("res://Sotheby_Hcxmmx/Assets/battle/300901_sufubi.atlas")
	actor_data=ClassDB.instantiate("SpineSkeletonDataResource");actor_data.skeleton_file_res=skel;actor_data.atlas_res=atlas;actor_data.default_mix=.12
	actor=_new_actor(5);temporary=_new_actor(6)

func _new_actor(z:int):
	var a=ClassDB.instantiate("SpineSprite");a.set_skeleton_data_res(actor_data);a.set_update_mode(2);a.scale=Vector2(-UNIT*.01,UNIT*.01);a.z_index=z;world.add_child(a);return a

func _sample(a,animation:String,at:float)->void:
	a.get_animation_state().clear_tracks();a.get_skeleton().set_to_setup_pose()
	var track=a.get_animation_state().set_animation(animation,animation=="idle",0);track.set_mix_duration(0.0);track.set_track_time(maxf(0,at));a.update_skeleton(0.0)

func _mix_keys(t:float,keys:Array)->Vector3:
	if t<=keys[0][0]:return Vector3(keys[0][1],keys[0][2],keys[0][3])
	for i in range(1,keys.size()):
		if t<=keys[i][0]:
			var a:Array=keys[i-1];var b:Array=keys[i];var u:=smoothstep(float(a[0]),float(b[0]),t)
			return Vector3(a[1],a[2],a[3]).lerp(Vector3(b[1],b[2],b[3]),u)
	var k:Array=keys[-1];return Vector3(k[1],k[2],k[3])

func _full_cinematic(t:float)->Transform2D:
	# 2D equivalent composition. Key times follow recovered camera01; focus and
	# zoom are preview calibration, not raw Cinemachine transforms.
	var keys:Array=[[0.,6.,1.8,1.25],[.33,6.,1.8,1.42],[1.,6.,1.8,1.42],[1.4,6.,5.8,2.4],[1.667,6.,5.8,2.4],[2.333,6.,1.8,1.3],[2.867,5.5,1.8,1.4],[3.167,5.5,1.8,1.4],[3.7,1.5,1.8,1.12],[4.5,-5.,1.8,.96],[5.2,-10.,1.8,.86],[5.5,-11.5,1.8,.86]]
	var p:=_mix_keys(t,keys)
	if t<2.4:p.y=1.8+_camera_curve(1,"main/VirtualCameras/set1/vcam1","localPosition",t,1)*(.95238095)
	if t>=5.566667:p=_mix_keys(t,[[5.566667,-1.,2.2,.92],[6.233334,-3.,2.1,1.06],[8.166667,-3.,2.1,1.06],[9.166667,0.,2.2,1.0]])
	var z:=p.z;var focus:=ORIGIN+Vector2(-p.x*UNIT,-p.y*UNIT)
	return Transform2D(0,Vector2.ONE*z,0,STAGE_RECT.size*.5-focus*z)

func _camera_curve(part:int,path:String,property:String,t:float,axis:int=0)->float:
	for clip in camera_clips:
		if str(clip.name)!="300901_sufubi_unique_0%d_r_3_1"%part:continue
		for binding in clip.bindings:
			if binding.path!=path or binding.property!=property:continue
			var a:Dictionary=binding.axes[axis]
			if a.constant!=null:return float(a.constant)
			var last:Dictionary={}
			for key in a["keys"]:
				if float(key.time)<-.001 or float(key.time)>float(clip.duration)+.001:continue
				if last.is_empty():last=key
				if float(key.time)>t:break
				last=key
			if last.is_empty():return 0.
			var dt:=maxf(0,t-float(last.time));var c:Array=last.coefficients
			return ((float(c[0])*dt+float(c[1]))*dt+float(c[2]))*dt+float(c[3])
	return 0.

func _cinematic(t:float)->Transform2D:
	if not rhythm:return _full_cinematic(t)
	var ride:=_full_cinematic(Rhythm.sample(t,"ride"))
	var impact:=_full_cinematic(Rhythm.sample(t,"impact"))
	var tr:=ride.interpolate_with(impact,smoothstep(1.20,1.32,t))
	return tr.interpolate_with(return_transform,smoothstep(2.02,2.38,t))

func _camera(t:float)->void:
	var tr:=_cinematic(t) if camera_enabled else return_transform
	if interrupt_at>=0:tr=interrupt_transform.interpolate_with(return_transform,smoothstep(interrupt_at,interrupt_at+.25,t))
	elif not rhythm and t>9.0:tr=tr.interpolate_with(return_transform,smoothstep(9.,9.5,t))
	if shake_enabled and interrupt_at<0:
		var mag:=0.0
		var impulses:Array=[[.90,.25,.65],[1.20,.18,1.4],[1.25,.25,.55],[1.70,.45,3.2]] if rhythm else [[3.25,.5,1.1],[4.,1.5,.5],[5.566667,.65,.8],[6.216667,.5,1.4],[6.616667,.75,.55],[7.466667,.6,3.2]]
		for k in impulses:
			if t>=k[0] and t<k[0]+k[1]:mag+=float(k[2])*(1.0-smoothstep(float(k[0]),float(k[0]+k[1]),t))
		tr.origin+=Vector2(sin(t*113),cos(t*137))*mag
	world.transform=tr;fx.sync_transform()

func _post(t:float)->void:
	post.visible=post_enabled
	var sm:ShaderMaterial=post.material
	var fade:=1.0-smoothstep(interrupt_at,interrupt_at+.15,t) if interrupt_at>=0 else 1.0
	var blur:=0.0;var split:=0.0;var flash:=0.0
	var impulses:Array=[[1.20,.18,1.1],[1.60,.45,.8]] if rhythm else [[6.216667,.35,1.1],[7.366667,.45,.8]]
	for k in impulses:
		var age:=t-float(k[0]);var envelope:=exp(-maxf(age,0)*11.) if age>=0 and age<k[1] else 0.0
		blur+=envelope*float(k[2]);split+=envelope*2.6;flash+=envelope*.24
	sm.set_shader_parameter("radial_blur",blur*fade);sm.set_shader_parameter("split_pixels",split*fade);sm.set_shader_parameter("flash",flash*fade)
	sm.set_shader_parameter("dissolve_flash",flash*fade);sm.set_shader_parameter("distort_pixels",7.0*fade)
	var burst:Vector2=fx.to_global(Vector2(4.8,-1.))
	sm.set_shader_parameter("burst_center",burst/get_viewport().get_visible_rect().size)
