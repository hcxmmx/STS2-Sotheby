extends Control

const CoverScript = preload("res://Sotheby_Hcxmmx/Cover/Scene.gd")
const VoiceScript = preload("res://Sotheby_Hcxmmx/Voice.gd")
const SubtitleScript = preload("res://Sotheby_Hcxmmx/Cover/Subtitle.gd")
const Settings = preload("res://Sotheby_Hcxmmx/Settings.gd")
var cover
var actor
var voice
var subtitle
var touch: Control
var rng := RandomNumberGenerator.new()
var ready_ok := false
var active := false
var since_touch := 0.0
var idle_cooldown := 300.0
var interaction_cooldown := 0.0
var last_id := ""
var test_mode := false
var native_screen: Control
var native_states: Dictionary = {}
var custom_ui: Control
var ui_font: Font
var gameplay: Dictionary = {}
var popup: Control
var bilingual: CheckBox
var home_settings:Dictionary
var exiting_tree:=false

func _enter_tree()->void:
	exiting_tree=false

func _ready() -> void:
	add_to_group("sotheby_portraits")
	home_settings=Settings.read()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	rng.randomize()
	cover = CoverScript.new()
	add_child(cover)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actor = cover.actor
	ready_ok = actor != null and actor.valid
	if not ready_ok: return
	voice = VoiceScript.new(); add_child(voice); voice.actor = actor
	subtitle = SubtitleScript.new(); cover.canvas.add_child(subtitle); subtitle.voice = voice
	touch = Control.new(); touch.mouse_filter = Control.MOUSE_FILTER_STOP
	touch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	touch.tooltip_text = "点击互动 · 右键闲谈"
	touch.gui_input.connect(_on_touch); add_child(touch)
	ui_font = load("res://Sotheby_Hcxmmx/Cover/fonts/hwzs.ttf")
	resized.connect(_layout)
	visibility_changed.connect(func():
		if voice != null and not is_visible_in_tree(): voice.stop_voice())
	_layout.call_deferred()

func is_ready() -> bool:
	return ready_ok

func configure(screen: Control, details: Dictionary) -> void:
	native_screen = screen; gameplay = details
	if custom_ui != null: custom_ui.hide(); custom_ui.queue_free()
	custom_ui = Control.new(); custom_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_ui.theme = Theme.new(); custom_ui.theme.default_font = ui_font
	custom_ui.theme.default_font_size = 25
	add_child(custom_ui)
	_label("启程 / DEPARTURE", Vector2(75,90), Vector2(500,60), 32, Color("c7bca5"))
	_label("生命  %s    ·    金币  %s" % [str(details.get("hp","70/70")),str(details.get("gold","99"))], Vector2(75,300), Vector2(440,48),28)
	_label("初始遗物", Vector2(75,365), Vector2(380,40),24,Color("c7bca5"))
	var icon := TextureRect.new(); icon.texture = details.get("relic_icon"); icon.position=Vector2(75,415);icon.size=Vector2(64,64)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;custom_ui.add_child(icon)
	_label(str(details.get("relic_title","")),Vector2(155,414),Vector2(330,40),28)
	var description:=RichTextLabel.new();description.position=Vector2(155,461);description.size=Vector2(330,102);description.bbcode_enabled=true
	description.text=str(details.get("relic_description",""));description.scroll_active=false;description.mouse_filter=Control.MOUSE_FILTER_IGNORE
	description.add_theme_color_override("default_color",Color("c7c2b8"));description.add_theme_font_size_override("normal_font_size",23);custom_ui.add_child(description)
	bilingual=CheckBox.new();bilingual.text="中英双语字幕";bilingual.position=Vector2(75,655);bilingual.button_pressed=bool(Settings.read().bilingual_subtitles)
	bilingual.toggled.connect(func(value:bool):Settings.write("bilingual_subtitles",value);subtitle.english_only=not value)
	custom_ui.add_child(bilingual);subtitle.english_only=not bilingual.button_pressed
	set_active(true)

func _label(value:String,at:Vector2,extent:Vector2,font_size:int,color:=Color("e7e4d9"))->Label:
	var label:=Label.new();label.text=value;label.position=at;label.size=extent;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color);custom_ui.add_child(label);return label

func _style_button(button:Button)->void:
	for state in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("282a25") if state=="normal" else Color("484034")
		style.border_color=Color("7e715d");style.set_border_width_all(1);style.content_margin_left=18;style.content_margin_right=18
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_color",Color("e7e4d9"))

func _show_deck()->void:
	if is_instance_valid(popup): return
	voice.stop_voice()
	popup=Control.new();popup.name="SothebyStartingDeck";popup.mouse_filter=Control.MOUSE_FILTER_STOP
	native_screen.add_child(popup);popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim:=ColorRect.new();dim.color=Color(0,0,0,.7);dim.mouse_filter=Control.MOUSE_FILTER_STOP;popup.add_child(dim);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(560,420);popup.add_child(panel)
	panel.position=(native_screen.size-panel.custom_minimum_size)*.5
	panel.theme=custom_ui.theme
	var style:=StyleBoxFlat.new();style.bg_color=Color("23251f");style.border_color=Color("8f7c58");style.set_border_width_all(1);style.set_content_margin_all(32);panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);panel.add_child(column)
	var heading:=HBoxContainer.new();column.add_child(heading)
	var title:=Label.new();title.text="初始牌组";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	var close:=Button.new();close.text="×";_style_button(close);close.pressed.connect(_close_deck);heading.add_child(close)
	for card in gameplay.get("cards",[]):
		var line:=Label.new();line.text=str(card);line.add_theme_color_override("font_color",Color("e7e4d9"));column.add_child(line)
	close.grab_focus()

func _close_deck()->void:
	if is_instance_valid(popup):popup.queue_free()
	popup=null

func _remember(path:String)->Control:
	if not is_instance_valid(native_screen):return null
	var node:=native_screen.get_node_or_null(path) as Control
	if node!=null and not native_states.has(path):
		native_states[path]={"node":node,"position":node.position,"scale":node.scale,"visible":node.visible,"modulate":node.modulate}
	return node

func _layout()->void:
	if not ready_ok or size.x<1. or size.y<1.:return
	cover._layout()
	subtitle.logical_size=cover.aspect/cover.canvas.scale.x
	var transform_value:Transform2D=get_global_transform().affine_inverse()*actor.get_global_transform()
	var bounds:Rect2=actor.bounds()
	touch.position=transform_value*bounds.position
	touch.size=bounds.size*Vector2(transform_value.x.length(),transform_value.y.length())
	var factor:float=cover.canvas.scale.x
	if custom_ui!=null:custom_ui.scale=Vector2.ONE*factor;custom_ui.size=size/factor
	if not active:return
	var info:=_remember("InfoPanel")
	if info:info.hide()
	var buttons:=_remember("CharSelectButtons/ButtonContainer")
	if buttons:
		var width:=maxf(buttons.size.x,buttons.get_combined_minimum_size().x)
		buttons.scale=Vector2.ONE*factor*minf(.85,500./maxf(1.,width))
		buttons.global_position=native_screen.get_global_transform()*Vector2(75,170)*factor
	var ascension:=_remember("AscensionPanel")
	if ascension:
		# Only X/scale change. Vanilla retains ownership of its Y entrance tween.
		ascension.scale=Vector2.ONE*factor*.61
		var global_value:=ascension.global_position
		global_value.x=(native_screen.get_global_transform()*Vector2(30,0)*factor).x
		ascension.global_position=global_value

func set_active(value:bool)->void:
	active=value;visible=value
	if not exiting_tree and is_inside_tree():process_mode=Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if value:
		actor.portrait_idle(0.0)
		_layout();_layout.call_deferred();_greet.call_deferred()
	else:
		if voice!=null:voice.stop_voice()
		_close_deck()
		for path in native_states:
			var saved:Dictionary=native_states[path];var node:Control=saved.node
			if not is_instance_valid(node):continue
			if path=="InfoPanel":node.visible=saved.visible
			else:
				node.scale=saved.scale
				if path=="AscensionPanel":node.position.x=saved.position.x
				else:node.position=saved.position
		native_states.clear()

func prepare_selection()->void:
	set_active(false)

func _exit_tree()->void:
	exiting_tree=true
	set_active(false)

func _greet() -> void:
	if not active or not is_visible_in_tree() or not ready_ok: return
	if not bool(home_settings.auto_greeting):return
	var hour := int(Time.get_time_dict_from_system().hour)
	var choices: Array = ["1300905"]
	if rng.randf() < 0.3:
		if hour >= 6 and hour < 12: choices = ["1300906", "1300907"]
		elif hour >= 18 or hour < 5: choices = ["1300908", "1300909"]
	play_line(str(choices[rng.randi_range(0, choices.size() - 1)]))

func _on_touch(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT: return
	touch.accept_event()
	since_touch = 0.0
	if interaction_cooldown > 0: return
	var normalized: Vector2 = event.position / touch.size
	var special := ""
	# Calibrated on the rendered silhouette; original Unity hotspot coordinates
	# are retained in research data, not treated as Godot pixels.
	if normalized.y < 0.31: special = "1300910"
	elif normalized.y >= 0.34 and normalized.y < 0.53: special = "1300911"
	elif normalized.y >= 0.62 and normalized.y < 0.90: special = "1300912"
	if event.button_index == MOUSE_BUTTON_LEFT and special != "" and special != last_id and rng.randf() > 0.5:
		play_line(special)
	else:
		play_line(_normal_line())
	interaction_cooldown = float(home_settings.home_touch_interval)

func reload_settings()->void:
	home_settings=Settings.read()
	interaction_cooldown=minf(interaction_cooldown,float(home_settings.home_touch_interval))
	if subtitle!=null:subtitle.english_only=not bool(home_settings.bilingual_subtitles)
	if bilingual!=null:bilingual.set_pressed_no_signal(bool(home_settings.bilingual_subtitles))

func _normal_line() -> String:
	var options: Array = []
	var total := 0.0
	for id in voice.catalog:
		var record: Dictionary = voice.catalog[id]
		if record.type == "MainViewNormalTouch" and id != last_id:
			var weight := maxf(0.0, float(record.weight))
			total += weight
			options.append([id, total])
	var chosen := rng.randf() * total
	for option in options:
		if chosen <= option[1]: return str(option[0])
	return "1300916"

func play_line(id: String) -> bool:
	if not ready_ok or not active: return false
	last_id = id
	return voice.play_voice(id)

func set_audio_policy(gain: float, background_mute: bool) -> void:
	if voice != null:
		voice.set_gain(gain)
		voice.mute_in_background = background_mute

func _process(delta: float) -> void:
	if not ready_ok: return
	interaction_cooldown = maxf(0, interaction_cooldown - delta)
	if not active or not is_visible_in_tree():
		if voice.playing: voice.stop_voice()
		return
	since_touch += delta
	idle_cooldown += delta
	if since_touch >= 60 and idle_cooldown >= 300 and not voice.playing:
		play_line("1300904")
		since_touch = 0
		idle_cooldown = 0
