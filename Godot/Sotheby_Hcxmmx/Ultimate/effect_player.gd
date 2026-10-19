extends Node2D

var meta: Dictionary
var stream: FileAccess
var nodes: Array[MeshInstance2D] = []
var shaders: Array[ShaderMaterial] = []
var frame_cache: Dictionary = {}
var last_frame := -1
var visible_kinds := {"cast": true, "flight": true, "target": true, "background":true,"foreground":true}
var gain := 0.8
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
var emission_cutoff := 10000.0
var interrupted_at := -1.0
var trees_enabled := true
var trails_enabled := true
var only_trees := false
var potion_glow_enabled := true
var potion_glows:Dictionary={}
var debris_enabled := true
var near_trees_enabled := true
var far_trees_enabled := true
var source_times:Dictionary={}
var source_cutoffs:Dictionary={}
var source_weights:Dictionary={}

func birth_shader(code: String) -> String:
	return code.replace("void vertex()", "uniform float emission_cutoff=10000.0;\nvarying float particle_birth;\nvoid vertex()").replace("void vertex() {", "void vertex() { particle_birth=CUSTOM1.x;").replace("void fragment() {", "void fragment() { if(particle_birth>emission_cutoff+0.0001) discard;")

func sync_transform() -> void:
	field_root.transform=global_transform

func set_advanced(value: bool, t: float) -> void:
	advanced_enabled=value
	show_time(t,true)

func _st(info: Dictionary) -> Vector4:
	return Vector4(info.scale.x,info.scale.y,info.offset.x,info.offset.y)

func _refined_material(mat: Dictionary, additive: bool) -> ShaderMaterial:
	var sm:=ShaderMaterial.new()
	var sh:=Shader.new()
	sh.code=birth_shader(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Ultimate/advanced_dissolve.gdshader").replace("render_mode blend_add", "render_mode blend_add" if additive else "render_mode blend_mix"))
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
		if meta.groups[i].prefab != "cast": continue
		var ratio := 1.0 if legacy_mode else caster_ratio
		nodes[i].scale = Vector2.ONE * ratio
		nodes[i].position = Vector2(-6, 0) * (1.0-ratio) + (Vector2.ZERO if legacy_mode else caster_shift)

func set_legacy(value: bool, t: float) -> void:
	legacy_mode = value
	_apply_caster_mapping()
	show_time(t, true)

func initialize(skill: String="skill1", progressive: bool=false) -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Assets/fx/"+skill+"/frames.json"))
	stream = FileAccess.open("res://Sotheby_Hcxmmx/Assets/fx/"+skill+"/frames.bin", FileAccess.READ)
	assert(stream != null)
	assert(int(meta.get("binary_version",0))==3)
	field_viewport=SubViewport.new();field_viewport.size=Vector2i(get_viewport_rect().size)
	field_viewport.transparent_bg=true;field_viewport.disable_3d=true
	field_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(field_viewport)
	field_root=Node2D.new();field_root.position=position;field_root.scale=scale;field_viewport.add_child(field_root)
	for g in meta.groups:
		# Menu warmup spreads material/node creation over rendered frames.
		if progressive and nodes.size()%4==0:await get_tree().process_frame
		var node := MeshInstance2D.new()
		var mat: Dictionary = g.material
		var info: Dictionary = mat.textures._MainTex
		node.texture = load("res://Sotheby_Hcxmmx/"+str(meta.textures[info.texture].path).replace("assets/","Assets/"))
		var additive := float(mat.floats.get("_DstBlend", 10)) == 1.0
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
render_mode BLEND;
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
    COLOR = vec4(light, clamp(alpha, 0.0, 1.0));
}
""".replace("BLEND", "blend_add" if additive else "blend_mix")
		shader.code=birth_shader(shader.code)
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("preview_tonemap",skill=="unique")
		if str(mat.name)=="object_267_hs_ab01":sm.set_shader_parameter("preview_tonemap",false)
		var main: Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1,"a":1})
		sm.set_shader_parameter("main_tint",Vector4(main.r,main.g,main.b,main.a))
		sm.set_shader_parameter("main_scale", Vector2(info.scale.x,info.scale.y))
		sm.set_shader_parameter("main_offset", Vector2(info.offset.x,info.offset.y))
		if mat.textures.has("_Mask"):
			var mask_info: Dictionary = mat.textures._Mask
			sm.set_shader_parameter("has_mask", true)
			sm.set_shader_parameter("mask_tex", load("res://Sotheby_Hcxmmx/"+str(meta.textures[mask_info.texture].path).replace("assets/","Assets/")))
			sm.set_shader_parameter("mask_uses_alpha", bool(meta.textures[mask_info.texture].get("has_alpha_mask",true)))
			sm.set_shader_parameter("mask_scale", Vector2(mask_info.scale.x,mask_info.scale.y))
			sm.set_shader_parameter("mask_offset", Vector2(mask_info.offset.x,mask_info.offset.y))
		if "dissolve" in str(mat.shader) and mat.textures.has("_Distortion"):
			var noise_info: Dictionary = mat.textures._Distortion
			sm.set_shader_parameter("has_noise", true)
			sm.set_shader_parameter("noise_tex", load("res://Sotheby_Hcxmmx/"+str(meta.textures[noise_info.texture].path).replace("assets/","Assets/")))
			sm.set_shader_parameter("noise_scale", Vector2(noise_info.scale.x,noise_info.scale.y))
			sm.set_shader_parameter("noise_offset", Vector2(noise_info.offset.x,noise_info.offset.y))
		var refined: ShaderMaterial
		var is_distortion: bool=mat.shader=="shenlan/effects/postprocess/mask"
		if is_distortion:
			sm=ShaderMaterial.new()
			var field_shader:=Shader.new();field_shader.code=birth_shader(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Ultimate/distortion_mask.gdshader"));sm.shader=field_shader
			sm.set_shader_parameter("mask_map",node.texture)
			sm.set_shader_parameter("main_st",_st(info))
			sm.set_shader_parameter("factor",float(mat.floats.get("_Factor",1)))
			distortion_group_count+=1
		elif mat.shader=="shenlan/effects/default/dissolve_particle":
			refined=_refined_material(mat,additive)
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
		if str(g.source_resource)=="sufubi_unique01" and str(mat.name)=="object_267_hs_ab01" and not bool(g.get("is_trail",false)):
			var glow:=MeshInstance2D.new();glow.texture=node.texture;glow.z_index=node.z_index+1
			var light:=ShaderMaterial.new();light.shader=load("res://Sotheby_Hcxmmx/Ultimate/potion_light.gdshader");glow.material=light
			add_child(glow);potion_glows[nodes.size()-1]=glow
	show_time(0.0)

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
	if frame_cache.has(frame): return frame_cache[frame]
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
		arrays[Mesh.ARRAY_CUSTOM1] = stream.get_buffer(nv*4).to_float32_array()
		arrays[Mesh.ARRAY_INDEX] = stream.get_buffer(ni*4).to_int32_array()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
		groups.append({"id": id,"mesh":mesh,"dissolve":dissolve})
	assert(stream.get_position() == int(info.offset) + int(info.bytes))
	if frame_cache.size() >= 12: frame_cache.erase(frame_cache.keys()[0])
	frame_cache[frame] = groups
	return groups

func show_time(t: float, force: bool = false) -> void:
	var frame := clampi(int(round(t * float(meta.fps))),0,meta.frames.size()-1)
	if frame == last_frame and not force: return
	last_frame = frame
	for node in nodes: node.visible = false
	for glow in potion_glows.values():glow.visible=false
	var shown := 0
	var requested:={};var distinct_frames:={}
	for id in meta.groups.size():
		var resource:String=meta.groups[id].source_resource
		var requested_frame:=clampi(int(round(float(source_times.get(resource,t))*float(meta.fps))),0,meta.frames.size()-1)
		requested[id]=requested_frame;distinct_frames[requested_frame]=true
	var selected_entries:Array=[]
	for source_frame in distinct_frames:
		for entry in read_frame(source_frame):
			if int(requested[entry.id])==int(source_frame):selected_entries.append(entry)
	for entry in selected_entries:
		var id := int(entry.id)
		if not visible_kinds.get(meta.groups[id].prefab, true): continue
		var group: Dictionary=meta.groups[id]
		var weight:float=float(source_weights.get(str(group.source_resource),1.0))
		if weight<=.0001:continue
		if only_trees and not "tree" in str(group.name):continue
		if not trees_enabled and "tree" in str(group.name):continue
		if "tree" in str(group.name):
			if group.prefab=="foreground" and not near_trees_enabled:continue
			if group.prefab=="background" and not far_trees_enabled:continue
		if not debris_enabled and str(group.source_resource)=="sufubi_unique02" and str(group.name) in ["l_object","l_object (1)"]:continue
		if not trails_enabled and bool(group.get("is_trail",false)):continue
		var is_distortion: bool=group.material.shader=="shenlan/effects/postprocess/mask"
		if is_distortion and (not distortion_enabled or legacy_mode):continue
		nodes[id].mesh = entry.mesh
		nodes[id].visible = true
		var fade: float=1.0
		if interrupted_at>=0:
			var released_potion:bool=str(group.source_resource)=="sufubi_unique01" and "l_pingzi (1)" in str(group.name)
			fade=1.0-smoothstep(interrupted_at,interrupted_at+.24,t) if group.prefab in ["background","foreground","cast"] and not released_potion else 1.0-smoothstep(interrupted_at+1.3,interrupted_at+1.7,t)
		fade*=weight
		nodes[id].modulate.a=fade
		var group_cutoff:float=float(source_cutoffs.get(str(group.source_resource),emission_cutoff))
		if potion_glows.has(id) and potion_glow_enabled:
			var glow:MeshInstance2D=potion_glows[id];glow.mesh=entry.mesh;glow.visible=true;glow.modulate.a=fade
			glow.material.set_shader_parameter("emission_cutoff",group_cutoff)
		shaders[id].set_shader_parameter("emission_cutoff",group_cutoff)
		nodes[id].material=refined_materials[id] if advanced_enabled and not legacy_mode and refined_materials[id]!=null else shaders[id]
		shaders[id].set_shader_parameter("gain",gain)
		shaders[id].set_shader_parameter("dissolve",entry.dissolve)
		shaders[id].set_shader_parameter("legacy",legacy_mode)
		var scroll: Dictionary=group.material.colors.get("_Speed",{})
		var effect_time: float=(float(requested[id])/float(meta.fps)-float(group.instance_start))*float(group.simulation_speed)
		shaders[id].set_shader_parameter("scroll_offset",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		if refined_materials[id]!=null:
			refined_materials[id].set_shader_parameter("emission_cutoff",group_cutoff)
			refined_materials[id].set_shader_parameter("gain",gain)
			refined_materials[id].set_shader_parameter("effect_time",effect_time)
			refined_materials[id].set_shader_parameter("baked_scroll",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		if is_distortion:
			shaders[id].set_shader_parameter("baked_scroll",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		shown += 1
	peak_visible = maxi(peak_visible, shown)
