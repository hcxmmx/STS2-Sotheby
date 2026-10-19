extends Node2D

var meta: Dictionary
var stream: FileAccess
var nodes: Array[MeshInstance2D] = []
var shaders: Array[ShaderMaterial] = []
var frame_cache: Dictionary = {}
var last_frame := -1
var visible_kinds := {"cast": true, "flight": true, "target": true, "background":true,"foreground":true}
var gain := 0.8
var local_geometry_scale := 1.0
var flight_geometry_scale := -1.0
var flight_offset_start := Vector2.ZERO
var flight_offset_end := Vector2.ZERO
var peak_visible := 0
var legacy_mode := false
var caster_ratio := 1.0
var caster_shift := Vector2.ZERO
var advanced_enabled := true
var distortion_enabled := true
var refined_materials: Array[ShaderMaterial] = []
var field_viewport: SubViewport
var field_root: Node2D
var distortion_group_count := 0
var allowed_groups: Dictionary = {}
var potion_enhanced := true
var potion_glows: Dictionary = {}
var field_target: SubViewport
static var shared_frames: Dictionary = {}
static var shared_metadata: Dictionary = {}
static var material_templates: Dictionary = {}
const GROUND_EMITTERS := {
	"sufubi_skill1_03_fazhen":["fazhen","fazhen_add"],
	"sufubi_skill2_fazhen":["l_fazhen_03","l_fazhen_add","l_fazhen_born","l_bo03","l_bo01 (1)","l_bo02 (1)","m_ch (1)","l_glow01da","l_glow03 (3)"]
}
var ground_root: Node2D
var ground_groups: Array[int] = []
var ground_original_z := {}
var ground_occlusion := true

func _ground_host() -> Node:
	var ancestor: Node=get_parent()
	var fallback: Node=get_parent()
	while ancestor!=null:
		var native=ancestor.get_node_or_null("BackCombatVfxContainer")
		if native is CanvasItem:return native
		if ancestor.has_meta("sotheby_floor_host"):fallback=ancestor
		ancestor=ancestor.get_parent()
	return fallback

func _add_ground(id: int) -> void:
	if ground_root==null:
		var host:=_ground_host()
		ground_root=Node2D.new();ground_root.name="SothebyGround_"+str(get_instance_id())
		# Keep inherited canvas ordering; top_level would promote the ground
		# back over ordinary creatures even when attached to the back container.
		host.add_child(ground_root)
		# Keep the native scene's backdrop / ground VFX / creatures order.
		# In a development battle put it before the actor at the same Z.
		if host.has_meta("sotheby_floor_host"):host.move_child(ground_root,0)
		visibility_changed.connect(_sync_ground)
	ground_groups.append(id);ground_original_z[id]=nodes[id].z_index

func _sort_ground() -> void:
	ground_groups.sort_custom(func(a,b):
		var left: int=meta.groups[a].order;var right: int=meta.groups[b].order
		return left<right if left!=right else a<b)
	set_ground_occlusion(ground_occlusion)

func set_ground_occlusion(value: bool) -> void:
	ground_occlusion=value
	if not is_instance_valid(ground_root):return
	for id in ground_groups:
		var target: Node=ground_root if value else self
		if nodes[id].get_parent()!=target:nodes[id].reparent(target,false)
		# Source order is kept by sibling order. Negative Z would sink below
		# the native backdrop; positive Z would cross back above creatures.
		nodes[id].z_index=0 if value else int(ground_original_z[id])
		if value:ground_root.move_child(nodes[id],ground_root.get_child_count()-1)
	_sync_ground()

func _sync_ground() -> void:
	if is_instance_valid(ground_root):
		ground_root.global_transform=global_transform
		ground_root.visible=ground_occlusion and is_visible_in_tree()

func set_advanced(value: bool, t: float) -> void:
	advanced_enabled=value
	show_time(t,true)

func _st(info: Dictionary) -> Vector4:
	return Vector4(info.scale.x,info.scale.y,info.offset.x,info.offset.y)

func _refined_material(mat: Dictionary, additive: bool) -> ShaderMaterial:
	var sm:=ShaderMaterial.new()
	var sh:=Shader.new()
	sh.code=FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Vfx/advanced_dissolve.gdshader").replace("render_mode blend_add", "render_mode blend_add" if additive else "render_mode blend_mix")
	sm.shader=sh
	var main: Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1,"a":1})
	sm.set_shader_parameter("material_tint",Vector4(main.r,main.g,main.b,main.a))
	sm.set_shader_parameter("smoothness",float(mat.floats.get("_Smooth",1)))
	sm.set_shader_parameter("alpha_from_luminance","_BLENDALPHA_ON" in mat.raw.m_ValidKeywords)
	sm.set_shader_parameter("preview_tonemap",meta.skill=="unique")
	var speed: Dictionary=mat.colors.get("_Speed",{"r":0,"g":0,"b":0,"a":0})
	sm.set_shader_parameter("uv_speed",Vector4(speed.r,speed.g,speed.b,speed.a))
	for pair in [["_MainTex","main"],["_Distortion","noise"],["_Mask","mask"]]:
		if not mat.textures.has(pair[0]):continue
		var info: Dictionary=mat.textures[pair[0]]
		sm.set_shader_parameter(str(pair[1])+"_st",_st(info))
		sm.set_shader_parameter(str(pair[1])+"_map",load("res://Sotheby_Hcxmmx/"+str(meta.textures[info.texture].path).replace("assets/","Assets/")))
		if pair[1]!="main":sm.set_shader_parameter("has_"+str(pair[1]),true)
	return sm

func set_caster_mapping(pixel_scale: float, root_offset: Vector2, pixels_per_unit: float) -> void:
	# Original Unity SkeletonDataAsset uses 0.01 world units per Spine unit.
	caster_ratio = pixel_scale / (0.01 * pixels_per_unit)
	caster_shift = root_offset / pixels_per_unit
	_apply_caster_mapping()

func _apply_caster_mapping() -> void:
	for i in nodes.size():
		if nodes[i]==null:continue
		if meta.groups[i].prefab != "cast": continue
		var ratio := 1.0 if legacy_mode else caster_ratio
		nodes[i].scale = Vector2.ONE * ratio
		nodes[i].position = Vector2(-6, 0) * (1.0-ratio) + (Vector2.ZERO if legacy_mode else caster_shift)

func set_legacy(value: bool, t: float) -> void:
	legacy_mode = value
	_apply_caster_mapping()
	show_time(t, true)

func initialize(skill: String="skill1") -> void:
	if not shared_metadata.has(skill):shared_metadata[skill]=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Assets/fx/"+skill+"/frames.json"))
	meta = shared_metadata[skill]
	stream = FileAccess.open("res://Sotheby_Hcxmmx/Assets/fx/"+skill+"/frames.bin", FileAccess.READ)
	assert(stream != null)
	assert(int(meta.get("binary_version",0))==2)
	field_viewport=field_target
	if field_viewport==null:
		field_viewport=SubViewport.new();field_viewport.size=Vector2i(1600,1000)
		field_viewport.transparent_bg=true;field_viewport.disable_3d=true
		field_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		add_child(field_viewport)
	field_root=Node2D.new();field_root.position=position;field_root.scale=scale;field_viewport.add_child(field_root)
	for g in meta.groups:
		if not allowed_groups.is_empty() and not allowed_groups.has(nodes.size()):
			nodes.append(null);shaders.append(null);refined_materials.append(null);continue
		var node := MeshInstance2D.new()
		var mat: Dictionary = g.material
		var info: Dictionary = mat.textures._MainTex
		node.texture = load("res://Sotheby_Hcxmmx/" + str(meta.textures[info.texture].path).replace("assets/","Assets/"))
		var key:=skill+":"+str(nodes.size())
		var sm: ShaderMaterial
		var refined: ShaderMaterial
		var is_distortion: bool=mat.shader=="shenlan/effects/postprocess/mask"
		if material_templates.has(key):
			sm=material_templates[key].base.duplicate(false)
			if material_templates[key].refined!=null:refined=material_templates[key].refined.duplicate(false)
		else:
			var additive := float(mat.floats.get("_DstBlend", 10)) == 1.0
			var shader := Shader.new()
			shader.code = """shader_type canvas_item;
	render_mode BLEND;
	uniform bool potion_enhanced = false;
	uniform float gain = 0.8;
	uniform float dissolve = 0.0;
	uniform vec4 main_tint = vec4(1.0);
	uniform bool legacy = false;
	uniform bool preview_tonemap = false;
	uniform vec2 main_scale = vec2(1.0);
	uniform vec2 main_offset = vec2(0.0);
	uniform vec2 scroll_offset = vec2(0.0);
	uniform vec2 mask_scale = vec2(1.0);
	uniform vec2 mask_offset = vec2(0.0);
	uniform vec2 noise_scale = vec2(1.0);
	uniform vec2 noise_offset = vec2(0.0);
	uniform bool has_mask = false;
	uniform bool has_noise = false;
	uniform bool mask_uses_alpha = true;
	uniform sampler2D mask_tex : repeat_enable, filter_linear;
	uniform sampler2D noise_tex : repeat_enable, filter_linear;
	varying vec4 vertex_tint;
	void vertex() { vertex_tint = COLOR; }
	void fragment() {
	    vec4 tex = texture(TEXTURE, UV);
	    vec2 base_uv = (UV - main_offset - scroll_offset) / main_scale;
	    vec2 mask_uv = legacy ? UV : base_uv * mask_scale + mask_offset;
	    vec2 noise_uv = legacy ? UV : base_uv * noise_scale + noise_offset + scroll_offset;
	    vec4 tint = vertex_tint * main_tint;
	    if (legacy) { tint = clamp(tint,vec4(0.0),vec4(1.0)); }
	    float alpha = tex.a * tint.a;
	    if (has_mask) {
	        vec4 mask_value = texture(mask_tex, mask_uv);
	        alpha *= mask_uses_alpha ? mask_value.a : mask_value.r;
	    }
	    // Approximation: original custom shader stream bindings are not yet recovered.
	    if (has_noise) {
	        float n = texture(noise_tex, noise_uv).r;
	        alpha *= smoothstep(dissolve - 0.18, dissolve + 0.18, n);
	    } else {
	        alpha *= 1.0 - smoothstep(0.45, 1.45, dissolve);
	    }
	    vec3 light = tex.rgb * tint.rgb * gain;
	    if (preview_tonemap) { light /= 1.0 + max(light.r,max(light.g,light.b)); }
	    if (legacy) {
	        light = light / (vec3(1.0) + light) * 0.65;
	    }
	    if (potion_enhanced) {
	        // Chroma selects the painted green liquid; neck, cork and glass stay intact.
	        float liquid = smoothstep(0.045, 0.24, tex.g-tex.b)
	                     * smoothstep(-0.02, 0.16, tex.g-tex.r)
	                     * smoothstep(0.39,0.44,UV.y) * tex.a;
	        light += vec3(0.65, 0.95, 0.065) * liquid * 0.95;
	    }
	    COLOR = vec4(light, clamp(alpha, 0.0, 1.0));
	}
	""".replace("BLEND", "blend_add" if additive else "blend_mix")
			sm = ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("preview_tonemap",skill=="unique")
			var main: Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1,"a":1})
			sm.set_shader_parameter("main_tint",Vector4(main.r,main.g,main.b,main.a))
			sm.set_shader_parameter("main_scale", Vector2(info.scale.x,info.scale.y))
			sm.set_shader_parameter("main_offset", Vector2(info.offset.x,info.offset.y))
			if mat.textures.has("_Mask"):
				var mask_info: Dictionary = mat.textures._Mask
				sm.set_shader_parameter("has_mask", true)
				sm.set_shader_parameter("mask_tex", load("res://Sotheby_Hcxmmx/" + str(meta.textures[mask_info.texture].path).replace("assets/","Assets/")))
				sm.set_shader_parameter("mask_uses_alpha", bool(meta.textures[mask_info.texture].get("has_alpha_mask",true)))
				sm.set_shader_parameter("mask_scale", Vector2(mask_info.scale.x,mask_info.scale.y))
				sm.set_shader_parameter("mask_offset", Vector2(mask_info.offset.x,mask_info.offset.y))
			if "dissolve" in str(mat.shader) and mat.textures.has("_Distortion"):
				var noise_info: Dictionary = mat.textures._Distortion
				sm.set_shader_parameter("has_noise", true)
				sm.set_shader_parameter("noise_tex", load("res://Sotheby_Hcxmmx/" + str(meta.textures[noise_info.texture].path).replace("assets/","Assets/")))
				sm.set_shader_parameter("noise_scale", Vector2(noise_info.scale.x,noise_info.scale.y))
				sm.set_shader_parameter("noise_offset", Vector2(noise_info.offset.x,noise_info.offset.y))
			if is_distortion:
				sm=ShaderMaterial.new();sm.shader=load("res://Sotheby_Hcxmmx/Vfx/distortion_mask.gdshader")
				sm.set_shader_parameter("mask_map",node.texture)
				sm.set_shader_parameter("main_st",_st(info))
				sm.set_shader_parameter("factor",float(mat.floats.get("_Factor",1)))
			elif mat.shader=="shenlan/effects/default/dissolve_particle":
				refined=_refined_material(mat,additive)
			material_templates[key]={"base":sm,"refined":refined}
			# Templates are never assigned directly to live nodes.
			sm=sm.duplicate(false)
			if refined!=null:refined=refined.duplicate(false)
		if is_distortion:distortion_group_count+=1
		node.material = refined if refined!=null else sm
		node.z_index = 10 + clampi(int(g.order), -5, 20)
		if skill!="skill1":
			# Preserve sorting distinctions rather than clamping every foreground
			# emitter into the same bucket. Scene layers remain below UI/refraction.
			if g.prefab=="background":node.z_index=-70+clampi(int(g.order),-20,30)
			elif g.prefab=="foreground":node.z_index=65+clampi(int(g.order),-5,12)
			else:node.z_index=12+clampi(int(g.order),-20,45)
		node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		if is_distortion:field_root.add_child(node)
		else:add_child(node)
		nodes.append(node)
		shaders.append(sm)
		refined_materials.append(refined)
		if str(g.source_resource) in GROUND_EMITTERS and str(g.name) in GROUND_EMITTERS[str(g.source_resource)]:_add_ground(nodes.size()-1)
		if g.source_resource=="sufubi_skill1_02" and g.name=="pingzi01":
			var glow:=MeshInstance2D.new();glow.texture=node.texture
			var glow_mat:=ShaderMaterial.new();glow_mat.shader=load("res://Sotheby_Hcxmmx/Vfx/potion_glow.gdshader")
			glow.material=glow_mat;glow.z_index=node.z_index+2;add_child(glow)
			potion_glows[nodes.size()-1]=glow
	_sort_ground();show_time(0.0)

func _vec2_array(raw: PackedByteArray) -> PackedVector2Array:
	var floats := raw.to_float32_array()
	var result := PackedVector2Array()
	result.resize(floats.size() / 2)
	for i in result.size(): result[i] = Vector2(floats[i*2], floats[i*2+1])
	return result

func _color_array(raw: PackedByteArray) -> PackedColorArray:
	var floats := raw.to_float32_array()
	var result := PackedColorArray()
	result.resize(floats.size() / 4)
	for i in result.size(): result[i] = Color(floats[i*4],floats[i*4+1],floats[i*4+2],floats[i*4+3])
	return result

func read_frame(frame: int) -> Array:
	var cache_key:=str(meta.skill)+":"+str(frame)
	if shared_frames.has(cache_key): return shared_frames[cache_key]
	var info: Dictionary = meta.frames[frame]
	stream.seek(int(info.offset))
	var count := stream.get_32()
	var groups: Array = []
	for n in count:
		var id := stream.get_32()
		var nv := stream.get_32()
		var ni := stream.get_32()
		var dissolve := stream.get_float()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vec2_array(stream.get_buffer(nv*8))
		arrays[Mesh.ARRAY_TEX_UV] = _vec2_array(stream.get_buffer(nv*8))
		arrays[Mesh.ARRAY_COLOR] = _color_array(stream.get_buffer(nv*16))
		arrays[Mesh.ARRAY_CUSTOM0] = stream.get_buffer(nv*16).to_float32_array()
		arrays[Mesh.ARRAY_INDEX] = stream.get_buffer(ni*4).to_int32_array()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var center:=Vector2.ZERO
		if meta.groups[id].prefab=="flight" and meta.groups[id].name=="pingzi01":
			for vertex in arrays[Mesh.ARRAY_VERTEX]:center+=vertex
			center/=float(nv)
		groups.append({"id": id,"mesh":mesh,"dissolve":dissolve,"center":center})
	assert(stream.get_position() == int(info.offset) + int(info.bytes))
	if shared_frames.size() >= 96:shared_frames.erase(shared_frames.keys()[0])
	shared_frames[cache_key] = groups
	return groups

func show_time(t: float, force: bool = false) -> void:
	_sync_ground()
	var frame := clampi(int(round(t * float(meta.fps))),0,meta.frames.size()-1)
	if frame == last_frame and not force: return
	last_frame = frame
	for glow in potion_glows.values():glow.visible=false
	for node in nodes:
		if node!=null:node.visible = false
	var entries:=read_frame(frame)
	var flight_centers: Dictionary={}
	for entry in entries:
		var group: Dictionary=meta.groups[int(entry.id)]
		if group.prefab=="flight" and group.name=="pingzi01":flight_centers[float(group.instance_start)]=entry.center
	var shown := 0
	for entry in entries:
		var id := int(entry.id)
		if nodes[id]==null:continue
		if not visible_kinds.get(meta.groups[id].prefab, true): continue
		var group: Dictionary=meta.groups[id]
		var is_distortion: bool=group.material.shader=="shenlan/effects/postprocess/mask"
		if is_distortion and (not distortion_enabled or legacy_mode):continue
		if group.prefab in ["flight","target"]:
			var origin: Array=group.instance.origin
			var pivot:=Vector2(-float(origin[0]),-float(origin[1])-float(origin[2])*.32)
			if group.prefab=="flight":pivot=flight_centers.get(float(group.instance_start),Vector2(6,0))
			var size_value: float=flight_geometry_scale if group.prefab=="flight" and flight_geometry_scale>0 else local_geometry_scale
			nodes[id].scale=Vector2.ONE*size_value
			nodes[id].position=pivot*(1.0-size_value)
			if group.prefab=="flight":nodes[id].position+=flight_offset_start.lerp(flight_offset_end,clampf((pivot.x+6.0)/12.0,0,1))
		nodes[id].mesh = entry.mesh
		nodes[id].visible = true
		nodes[id].material=refined_materials[id] if advanced_enabled and not legacy_mode and refined_materials[id]!=null else shaders[id]
		var is_bottle: bool=group.source_resource=="sufubi_skill1_02" and group.name=="pingzi01"
		shaders[id].set_shader_parameter("potion_enhanced",potion_enhanced and is_bottle)
		if is_bottle:
			# Both source bottle layers have order=1; the larger dark auxiliary
			# quad otherwise obscures the detailed primary in our flat 2D sorting.
			nodes[id].z_index=12 if potion_enhanced else 11
		if potion_glows.has(id):
			potion_glows[id].mesh=entry.mesh;potion_glows[id].visible=potion_enhanced
			potion_glows[id].transform=nodes[id].transform
		shaders[id].set_shader_parameter("gain",gain)
		shaders[id].set_shader_parameter("dissolve",entry.dissolve)
		shaders[id].set_shader_parameter("legacy",legacy_mode)
		var scroll: Dictionary=group.material.colors.get("_Speed",{})
		var effect_time: float=(float(frame)/float(meta.fps)-float(group.instance_start))*float(group.simulation_speed)
		shaders[id].set_shader_parameter("scroll_offset",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		if refined_materials[id]!=null:
			refined_materials[id].set_shader_parameter("gain",gain)
			refined_materials[id].set_shader_parameter("effect_time",effect_time)
			refined_materials[id].set_shader_parameter("baked_scroll",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		if is_distortion:
			shaders[id].set_shader_parameter("baked_scroll",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		shown += 1
	peak_visible = maxi(peak_visible, shown)

func _exit_tree() -> void:
	if field_target!=null and is_instance_valid(field_root):field_root.queue_free()
	if is_instance_valid(ground_root):ground_root.queue_free()
