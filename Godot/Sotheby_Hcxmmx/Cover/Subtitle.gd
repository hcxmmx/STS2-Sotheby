extends Node2D

var source: Dictionary
var specs: Dictionary = {}
var chinese: Label
var english: Label
var backdrop: TextureRect
var layout_row: Dictionary
var padding_bottom := 53.0
var logical_size := Vector2(1920, 1080)
var voice
var english_only := false
var warming:=false
var last_english:="\u0001"
var last_chinese:="\u0001"
var last_english_only:=false
var last_extent:=Vector2.ZERO
var layout_updates:=0

func _ready() -> void:
	source = JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Cover/subtitles.json"))
	for row in source.nodes: specs[str(row.path).get_file()] = row
	layout_row = specs.layout
	for component in layout_row.components:
		if component.data.has("m_Padding"): padding_bottom = float(component.data.m_Padding.m_Bottom)
	backdrop = TextureRect.new()
	backdrop.texture = load("res://Sotheby_Hcxmmx/Cover/images/subtitle_backdrop.png")
	var material_value := ShaderMaterial.new()
	material_value.shader = load("res://Sotheby_Hcxmmx/Cover/subtitle_mask.gdshader")
	backdrop.material = material_value
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: Dictionary = specs["#simage_voicebg"]
	backdrop.size = Vector2(bg.layout.m_SizeDelta.x, bg.layout.m_SizeDelta.y)
	var content: Dictionary = specs.content.layout
	backdrop.position = Vector2(content.m_AnchoredPosition.x-content.m_SizeDelta.x*.5+bg.layout.m_AnchoredPosition.x,
		-content.m_AnchoredPosition.y+content.m_SizeDelta.y*.5-bg.layout.m_AnchoredPosition.y)-backdrop.size*.5
	for component in bg.components:
		if component.data.has("m_Color"):
			var color: Dictionary = component.data.m_Color
			backdrop.modulate = Color(color.r, color.g, color.b, color.a)
	add_child(backdrop)
	chinese = _label(specs["#txt_voicecontent"], "res://Sotheby_Hcxmmx/Cover/fonts/hwzs.ttf")
	english = _label(specs["#txt_voiceengcontent"], "res://Sotheby_Hcxmmx/Cover/fonts/subtitle_en.ttf")
	visible = false

func _label(row: Dictionary, font_path: String) -> Label:
	var result := Label.new()
	for component in row.components:
		var info: Dictionary = component.data
		if not info.has("m_fontSize"): continue
		result.add_theme_font_size_override("font_size", int(info.m_fontSize))
		var color: Dictionary = info.m_fontColor
		result.add_theme_color_override("font_color", Color(color.r,color.g,color.b,color.a))
	result.add_theme_font_override("font", load("res://"+str(row.exported_font) if row.has("exported_font") else font_path))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func _process(_delta: float) -> void:
	if warming or voice == null: return
	var en: String = voice.subtitle()
	var zh := ""
	if not en.is_empty():
		for segment in voice.record.get("subtitles_zh", []):
			if segment.start_seconds != null and voice.clock >= float(segment.start_seconds): zh = str(segment.text)
	_show_subtitles(en,zh)

func _show_subtitles(en:String,zh:String)->void:
	visible = not en.is_empty() or not zh.is_empty()
	if not visible: return
	en=en.strip_edges();zh=zh.strip_edges()
	if en==last_english and zh==last_chinese and english_only==last_english_only and logical_size==last_extent:return
	last_english=en;last_chinese=zh;last_english_only=english_only;last_extent=logical_size
	layout_updates+=1
	chinese.visible = not english_only
	chinese.text = zh
	english.text = en
	position = logical_size*.5
	var content: Dictionary = specs.content.layout
	var layout: Dictionary = layout_row.layout
	var width := float(content.m_SizeDelta.x+layout.m_SizeDelta.x)-100.0
	var bottom := -float(content.m_AnchoredPosition.y)+float(content.m_SizeDelta.y)*.5-float(layout.m_AnchoredPosition.y)+float(layout.m_SizeDelta.y)*.5-padding_bottom
	for label in [english, chinese]:
		if not label.visible: continue
		var fs: int = label.get_theme_font_size("font_size")
		var height: float = label.get_theme_font("font").get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, width, fs).y
		label.position = Vector2(-width*.5, bottom-height)
		label.size = Vector2(width, height)
		bottom -= height

func warm_catalog(records:Dictionary)->void:
	# Font file loading alone does not rasterize subtitle glyphs. Draw the
	# actual home text offscreen once, yielding between each record.
	warming=true
	var original_english_only:=english_only
	english_only=false
	for row in records.values():
		if row.scope!="home":continue
		_show_subtitles(str(row.text),str(row.text_zh))
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	english_only=original_english_only;visible=false;warming=false
