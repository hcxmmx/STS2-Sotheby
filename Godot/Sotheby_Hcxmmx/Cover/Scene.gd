extends Control

const Actor=preload("res://Sotheby_Hcxmmx/Actor.gd")
const ROOT_PATH:="/characterdatatitleview"
var data:Dictionary
var nodes:Dictionary={}
var specs:Dictionary={}
var sizes:Dictionary={}
var images:Dictionary={}
var labels:Dictionary={}
var text_heights:Dictionary={}
var stage:Control
var canvas:Node2D
var root:Node2D
var actor
var actor_mount:Node2D
var last_layout_size:=Vector2.ZERO
var character_base_position:=Vector2.ZERO
var layout_updates:=0
var guide:Node2D
var status:Label
var font:Font
var aspect:=Vector2(1920,1080)
var show_details:=true
var show_columns:=false
var show_guides:=false
var paused:=false
var clock:=0.0
var interaction_time:=0.0
var qt:=false
var voice
var subtitle
var selected_voice := "1300905"

func _ready()->void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Cover/layout.json"))
	font=load("res://Sotheby_Hcxmmx/Cover/fonts/hwzs.ttf")
	var theme_value:=Theme.new();theme_value.default_font_size=22;theme=theme_value
	stage=Control.new();stage.size=Vector2(1920,1080);stage.clip_contents=true;stage.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(stage)
	canvas=Node2D.new();stage.add_child(canvas)
	for row in data.nodes:
		var path:String=row.path;var node:=Node2D.new();node.name=path.get_file().replace("#","");specs[path]=row;nodes[path]=node
		if path==ROOT_PATH:canvas.add_child(node);root=node
		else:nodes[path.get_base_dir()].add_child(node)
		node.visible=bool(row.active);node.modulate.a=float(row.alpha)
		var list:Array=[]
		for info in row.images:
			var image:Control
			if info.get("solid",false):image=ColorRect.new()
			else:
				var texture:=TextureRect.new();texture.texture=load("res://"+str(info.file));texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;texture.stretch_mode=TextureRect.STRETCH_SCALE;image=texture
			image.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var color:Dictionary=info.color;image.modulate=Color(color.r,color.g,color.b,color.a);node.add_child(image);list.append(image)
		images[path]=list
		if not row.texts.is_empty():
			var text_info:Dictionary=row.texts[0];var label:=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE
			label.text=_text(path,str(text_info.get("m_text",text_info.get("m_Text",""))))
			label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",int(text_info.get("m_fontSize",28)))
			label.add_theme_color_override("font_color",Color("e7e4d9"));label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			label.vertical_alignment=VERTICAL_ALIGNMENT_TOP;node.add_child(label);labels[path]=label
		# Keep archive-only controls out of this simplified page.
		if any_in(path,["/ui_character_mask","/zhizhuloop_uicanvas","/rain_image_uicanvas","/#go_handbook","/#btn_skinswitch","/#pifu","/fetter"]):node.visible=false
	actor_mount=nodes[ROOT_PATH+"/content/character/charactericoncontainer/#go_spine"]
	actor=Actor.new();actor_mount.add_child(actor)
	if not actor.initialize("portrait"):
		push_error("[SothebySkin] Cover portrait initialization failed.")
		return
	actor.scale=Vector2.ONE*float(data.portrait_pixel_scale)
	actor.position=Vector2(float(data.portrait_offset[0]),-float(data.portrait_offset[1]))
	resized.connect(_layout)
	_layout()

func any_in(path:String,values:Array)->bool:
	for value in values:
		if str(value) in path:return true
	return false

func _text(path:String,fallback:String)->String:
	var key:=path.get_file()
	var map:={"#txt_name":"苏芙比","#txt_introduce":data.profile.introduction,"#txt_medium":"祖母绿","#txt_inspiration":"惜木的协奏[木] 魔药炼制","#txt_aroma":"花香调 依兰 雏菊 香草","#txt_size":"64 9/16×28 7/10×27 9/16in.","mediumTitle":"介质","inspirationTitle":"灵感","aromaTitle":"香调","sizeTitle":"尺寸"}
	return str(map.get(key,fallback))

func v(value:Dictionary)->Vector2:
	return Vector2(float(value.get("x",0)),float(value.get("y",0)))

func _layout()->void:
	if size.x<1. or size.y<1.:return
	if size==last_layout_size:return
	last_layout_size=size;layout_updates+=1
	aspect=size;stage.size=size
	# CanvasScaler ScaleWithScreenSize, MatchWidthOrHeight=0.5.
	var source_scale:=sqrt((aspect.x/1920.)*(aspect.y/1080.))
	var logical:=aspect/source_scale
	var fit:=1.0
	canvas.scale=Vector2.ONE*source_scale*fit;canvas.position=(stage.size-aspect*fit)*.5
	if subtitle!=null:subtitle.logical_size=logical
	for row in data.nodes:
		var path:String=row.path;var node:Node2D=nodes[path];var layout:Dictionary=row.layout
		var pivot:=v(layout.get("m_Pivot",{"x":.5,"y":.5}))
		var size_value:=logical
		if path==ROOT_PATH:node.position=logical*.5
		else:
			var parent_path:=path.get_base_dir();var parent_size:Vector2=sizes[parent_path];var pp:=v(specs[parent_path].layout.get("m_Pivot",{"x":.5,"y":.5}))
			var amin:=v(layout.get("m_AnchorMin",{"x":.5,"y":.5}));var amax:=v(layout.get("m_AnchorMax",{"x":.5,"y":.5}))
			size_value=parent_size*(amax-amin)+v(layout.get("m_SizeDelta",{}))
			var anchor:=parent_size*(amin*(Vector2.ONE-pivot)+amax*pivot-pp)+v(layout.get("m_AnchoredPosition",{}))
			node.position=Vector2(anchor.x,-anchor.y)
		sizes[path]=size_value
		var scale_info:Dictionary=layout.get("m_LocalScale",{"x":1,"y":1,"z":1});node.scale=v(scale_info)
		var q:Dictionary=layout.get("m_LocalRotation",{"x":0,"y":0,"z":0,"w":1})
		node.rotation=-2.*atan2(float(q.z),float(q.w))
		var top_left:=Vector2(-pivot.x*size_value.x,-(1.-pivot.y)*size_value.y)
		for image in images[path]:image.position=top_left;image.size=size_value.abs()
		if labels.has(path):
			var label:Label=labels[path];var fs:int=label.get_theme_font_size("font_size")
			var width:=size_value.x if size_value.x>1. else 300.
			var height:=maxf(size_value.y,font.get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,width,fs).y+4.)
			text_heights[path]=height
			label.position=Vector2(-pivot.x*width,-(1.-pivot.y)*height);label.size=Vector2(width,height)
	character_base_position=nodes[ROOT_PATH+"/content/character"].position
	_info_group()
	nodes[ROOT_PATH+"/content/intro/introduce2"].visible=show_details

func actor_mount_path()->String:
	return ROOT_PATH+"/content/character/charactericoncontainer/#go_spine"

func _info_group()->void:
	var group_path:=ROOT_PATH+"/content/intro/introduce2/InfoLayoutGroup"
	# Source ContentSizeFitter uses PreferredSize, pivot.y=0 (bottom);
	# the VerticalLayoutGroup grows upward as its text acquires height.
	var total:=0.
	for row in data.nodes:
		var path:String=row.path
		if path.get_base_dir()!=group_path:continue
		if labels.has(path):total+=float(text_heights[path])
		elif path.get_file()=="Blank":total+=8.
	var offset:=-total
	for row in data.nodes:
		var path:String=row.path
		if path.get_base_dir()!=group_path:continue
		var node:Node2D=nodes[path]
		if labels.has(path):
			var label:Label=labels[path];var height:float=text_heights[path];node.position=Vector2(0,offset+height*.5);label.position.y=-height*.5;offset+=height
		elif path.get_file()=="Blank":node.position=Vector2(0,offset);offset+=8.

