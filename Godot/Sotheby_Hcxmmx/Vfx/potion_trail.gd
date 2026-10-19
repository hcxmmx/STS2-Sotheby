extends MeshInstance2D

var width_scale := 1.0

# Deterministic ribbon adaptation: original noise_095_hs and green HDR hue,
# actual baked bottle path, no persistent history that would break reverse seek.
func _ready() -> void:
	texture=load("res://Sotheby_Hcxmmx/Assets/fx/textures/-5397137554924966264.png")
	texture_repeat=CanvasItem.TEXTURE_REPEAT_DISABLED
	var mat:=ShaderMaterial.new();mat.shader=load("res://Sotheby_Hcxmmx/Vfx/potion_trail.gdshader");material=mat
	z_index=10

func show_path(points: PackedVector2Array, fade: float) -> void:
	visible=points.size()>1 and fade>0.001
	if not visible:return
	var vertices:=PackedVector2Array();var uv:=PackedVector2Array()
	var colors:=PackedColorArray();var indices:=PackedInt32Array()
	for i in points.size():
		var u:=float(i)/float(points.size()-1)
		var tangent: Vector2=points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
		var normal:=tangent.normalized().orthogonal()
		# Pixel width is independent of bottle geometry. Tail tapers to zero.
		var width:=lerpf(0.15,3.0,pow(u,0.65))*width_scale
		for side in [-1.0,1.0]:
			vertices.append(points[i]+normal*width*side)
			uv.append(Vector2(u,(side+1)*0.5))
			colors.append(Color(1,1,1,fade*pow(u,0.7)))
		if i>0:
			var k:=i*2;indices.append_array(PackedInt32Array([k-2,k-1,k,k-1,k+1,k]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var ribbon:=ArrayMesh.new();ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh=ribbon
