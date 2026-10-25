extends "res://Sotheby_Hcxmmx/PortraitBase.gd"

const ROOT_PATH := "/characterdatatitleview"
var panels:Dictionary={}
var tabs:Array=[]
var page:=0
var clean_mode:=false
var eye:Button
var basic:Label
var original_visibility:Dictionary={}
var native_ui_paths:=["CharSelectButtons","ConfirmButton","BackButton"]
var lift:=0.0
var current_voice:Label
var voice_sections:Dictionary={}
var voice_scope_buttons:Dictionary={}
var subtitle_overlay:CanvasLayer
signal ascension_requested(direction:int)
signal open_settings_requested
var ascension_label:Label
var ascension_description:RichTextLabel
var ascension_buttons:Array=[]

class EyeButton extends Button:
	func _draw()->void:
		var c:=Color("e7e4d9");var center:=size*.5
		var points:=PackedVector2Array()
		for i in range(33):
			var t:=float(i)/32.;points.append(center+Vector2((t-.5)*40.,-sin(t*PI)*12.))
		for i in range(33):
			var t:=1.-float(i)/32.;points.append(center+Vector2((t-.5)*40.,sin(t*PI)*12.))
		draw_polyline(points,c,1.5,true);draw_circle(center,5.,c)
		if button_pressed:draw_line(center+Vector2(-21,17),center+Vector2(21,-17),Color("ce763e"),2.,true)

func configure(screen:Control,details:Dictionary)->void:
	native_screen=screen;gameplay=details
	if custom_ui!=null:
		for child in panels[4].get_children():panels[4].remove_child(child);child.queue_free()
		ascension_buttons.clear();_build_departure(panels[4])
		update_ascension(details.get("ascension_state",{}));set_active(true);_select_page(page)
		return
	prepare_pages()
	update_ascension(details.get("ascension_state",{}));set_active(true);_select_page(0)

func prepare_pages()->void:
	if custom_ui!=null:return
	custom_ui=Control.new();custom_ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;custom_ui.theme=Theme.new()
	custom_ui.theme.default_font=ui_font;custom_ui.theme.default_font_size=26;add_child(custom_ui)
	var titles:=["封面","语音","单品","文化","启程"]
	var english_titles:=["COVER","VOICE","ITEM","STORY","DEPARTURE"]
	var menu_data:Array=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Cover/Pages/menu.json"))
	for i in range(5):
		var button:=Button.new();button.position=Vector2(54,212+i*104);button.size=Vector2(235,100);button.flat=true
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;button.pressed.connect(_select_page.bind(i));custom_ui.add_child(button)
		var cn:=Label.new();cn.text=titles[i];cn.position=Vector2(82,18);cn.add_theme_font_size_override("font_size",34);cn.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(cn)
		var en:=Label.new();en.text=english_titles[i];en.position=Vector2(86,56);en.add_theme_font_size_override("font_size",14);en.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(en)
		var active_icon:=Control.new();active_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(active_icon)
		var idle_icon:=Control.new();idle_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(idle_icon)
		for row in menu_data:
			if row.images.is_empty():continue
			var is_selected:bool="/#go_selected/" in str(row.path)
			if not (str(row.path).ends_with("/itemicon1") or str(row.path).ends_with("/xin") or str(row.path).ends_with("/kuang")):continue
			var image:=TextureRect.new();image.texture=load("res://"+str(row.images[0].file));image.mouse_filter=Control.MOUSE_FILTER_IGNORE
			image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			var extent:=Vector2(44,44) if not is_selected else Vector2(row.layout.m_SizeDelta.x,row.layout.m_SizeDelta.y)
			image.size=extent;image.position=Vector2(34,45)-extent*.5
			(active_icon if is_selected else idle_icon).add_child(image)
		tabs.append({"button":button,"cn":cn,"en":en,"on":active_icon,"off":idle_icon})
	for i in range(1,5):
		var panel:=Control.new();panel.position=Vector2(1258,278);panel.size=Vector2(560,540);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;custom_ui.add_child(panel);panels[i]=panel
	_build_voice(panels[1]);_build_items(panels[2]);_build_stories(panels[3]);_build_departure(panels[4])
	basic=Label.new();basic.add_theme_font_override("font",ui_font);basic.add_theme_font_size_override("font_size",22);basic.add_theme_color_override("font_color",Color("bdb7a7"));basic.mouse_filter=Control.MOUSE_FILTER_IGNORE;cover.canvas.add_child(basic)
	_refresh_basic()
	eye=EyeButton.new();eye.toggle_mode=true;eye.tooltip_text="隐藏 / 显示尖塔操作区";eye.flat=true;eye.size=Vector2(72,56);eye.toggled.connect(_toggle_clean);add_child(eye)
	# A separate visual layer places subtitles above native UI without taking input.
	subtitle_overlay=CanvasLayer.new();subtitle_overlay.layer=4;add_child(subtitle_overlay)
	subtitle.queue_free();subtitle=load("res://Sotheby_Hcxmmx/Cover/ScreenSubtitle.gd").new();subtitle.voice=voice;subtitle_overlay.add_child(subtitle)
	voice.started.connect(func(_id:String):
		if current_voice:current_voice.text="正在播放 · "+str(voice.record.title))
	voice.finished.connect(func():
		if current_voice:current_voice.text="英文配音 · 点击台词播放")
	_select_page(0)

func _text_label(host:Node,text_value:String,font_size:int=26,color:=Color("e7e4d9"))->Label:
	var label:=Label.new();label.text=text_value;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE;host.add_child(label);return label

func _scroll(host:Control,top:float=55.)->VBoxContainer:
	var scroll:=ScrollContainer.new();scroll.position=Vector2(0,top);scroll.size=Vector2(550,540-top);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;host.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",22);scroll.add_child(column);return column

func _paragraph(host:Node,value:String,font_size:int=24)->RichTextLabel:
	var text:=RichTextLabel.new();text.text=value;text.fit_content=true;text.scroll_active=false;text.custom_minimum_size.x=505;text.add_theme_font_size_override("normal_font_size",font_size)
	text.add_theme_color_override("default_color",Color("d2cbbc"));host.add_child(text);return text

func _build_voice(host:Control)->void:
	current_voice=_text_label(host,"英文配音 · 点击台词播放",24,Color("bdb7a7"))
	var switches:=HBoxContainer.new();switches.position=Vector2(0,44);switches.add_theme_constant_override("separation",14);host.add_child(switches)
	var column:=_scroll(host,105.)
	for scope in ["home","combat"]:
		var selector:=Button.new();selector.text="主页语音" if scope=="home" else "战斗语音";selector.toggle_mode=true
		selector.custom_minimum_size=Vector2(260,42);_style_button(selector);switches.add_child(selector)
		selector.pressed.connect(_select_voice_scope.bind(scope));voice_scope_buttons[scope]=selector
		var section:=VBoxContainer.new();section.add_theme_constant_override("separation",22);column.add_child(section);voice_sections[scope]=section
		var counts:Dictionary={};var indexes:Dictionary={}
		for row in voice.catalog.values():
			if row.scope==scope:counts[str(row.title)]=int(counts.get(str(row.title),0))+1
		for id in voice.catalog:
			var row:Dictionary=voice.catalog[id]
			if row.scope!=scope:continue
			var title:=str(row.title);indexes[title]=int(indexes.get(title,0))+1
			if int(counts[title])>1:title+="（"+str(indexes[title])+"）"
			var button:=Button.new();button.text="▷   "+title;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.custom_minimum_size=Vector2(510,59);button.flat=true
			button.set_meta("voice_id",str(id))
			button.add_theme_font_size_override("font_size",29);button.add_theme_color_override("font_hover_color",Color("ce763e"));button.pressed.connect(play_line.bind(str(id)));section.add_child(button)
	_select_voice_scope("home")

func _select_voice_scope(scope:String)->void:
	for key in voice_sections:
		voice_sections[key].visible=key==scope
		voice_scope_buttons[key].set_pressed_no_signal(key==scope)
	# Each category starts at its first line rather than inheriting a long scroll.
	if voice_sections.has(scope):voice_sections[scope].get_parent().get_parent().scroll_vertical=0

func _build_items(host:Control)->void:
	_text_label(host,"单品 / ITEMS",30,Color("cbbda2"))
	var column:=_scroll(host)
	var records:Array=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Cover/Pages/profile.json"))
	for row in records:
		if int(row.type)!=2:continue
		var heading:=HBoxContainer.new();heading.add_theme_constant_override("separation",20);column.add_child(heading)
		var image:=TextureRect.new();image.texture=load("res://"+str(row.image));image.custom_minimum_size=Vector2(125,120);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;heading.add_child(image)
		var title:=VBoxContainer.new();heading.add_child(title);_text_label(title,str(row.title),27);_text_label(title,str(row.titleEn),19,Color("bdb7a7"))
		_paragraph(column,str(row.text),23)

func _build_stories(host:Control)->void:
	_text_label(host,"文化 / STORY",30,Color("cbbda2"))
	var column:=_scroll(host)
	var records:Array=JSON.parse_string(FileAccess.get_file_as_string("res://Sotheby_Hcxmmx/Cover/Pages/profile.json"))
	for row in records:
		if int(row.type)!=3:continue
		var section:=VBoxContainer.new();section.add_theme_constant_override("separation",12);column.add_child(section)
		_text_label(section,str(row.title),29,Color("ce763e"));_text_label(section,str(row.titleEn),19,Color("bdb7a7"));_paragraph(section,str(row.text),24)

func _build_departure(host:Control)->void:
	_text_label(host,"启程 / DEPARTURE",30,Color("cbbda2"))
	var column:=_scroll(host)
	_text_label(column,"进阶难度",26)
	var difficulty:=HBoxContainer.new();difficulty.add_theme_constant_override("separation",18);column.add_child(difficulty)
	ascension_label=Label.new();ascension_label.text="进阶 "+str(gameplay.get("ascension",0));ascension_label.custom_minimum_size.x=230
	for direction in [-1,1]:
		var button:=Button.new();button.text="‹" if direction<0 else "›";button.custom_minimum_size=Vector2(52,44);_style_button(button)
		button.pressed.connect(func():ascension_requested.emit(direction));ascension_buttons.append(button)
		difficulty.add_child(button)
		if direction<0:difficulty.add_child(ascension_label)
	ascension_description=_paragraph(column,"",23)
	_text_label(column,"初始遗物 · "+str(gameplay.get("relic_title","蛇之戒指")),26)
	_paragraph(column,str(gameplay.get("relic_description","在每场战斗开始时，额外抽2张牌。")),23)
	var settings:=Button.new();settings.text="模组设置";_style_button(settings);settings.pressed.connect(func():open_settings_requested.emit())
	column.add_child(settings)
	bilingual=CheckBox.new();bilingual.text="中英双语字幕";bilingual.button_pressed=bool(Settings.read().bilingual_subtitles)
	bilingual.toggled.connect(func(value:bool):Settings.write("bilingual_subtitles",value);subtitle.english_only=not value);column.add_child(bilingual);subtitle.english_only=not bilingual.button_pressed

func _refresh_basic()->void:
	if basic==null:return
	basic.text="生命 %s   金币 %s   进阶 %s" % [str(gameplay.get("hp","70/70")),str(gameplay.get("gold","99")),str(gameplay.get("ascension",10))]

func update_ascension(state:Dictionary)->void:
	gameplay.ascension=int(state.get("level",gameplay.get("ascension",0)))
	gameplay.ascension_state=state
	if ascension_label:ascension_label.text="进阶 "+str(gameplay.ascension)
	if ascension_description:ascension_description.text=str(state.get("title",""))+"\n"+str(state.get("description",""))
	if ascension_buttons.size()==2:
		ascension_buttons[0].disabled=not bool(state.get("editable",false)) or int(gameplay.ascension)<=0
		ascension_buttons[1].disabled=not bool(state.get("editable",false)) or int(gameplay.ascension)>=int(state.get("max_level",0))
	_refresh_basic()

func _select_page(index:int)->void:
	page=index
	for i in range(tabs.size()):
		var row:Dictionary=tabs[i];var selected:=i==index
		row.cn.modulate=Color("ce763e") if selected else Color("bdb7a7");row.en.modulate=Color("8c653e") if selected else Color("6b695e")
		row.on.visible=selected;row.off.visible=not selected
	for i in panels:panels[i].visible=int(i)==index
	_layout()

func _toggle_clean(value:bool)->void:
	if clean_mode==value:return
	clean_mode=value
	for path in native_ui_paths:
		var node:=native_screen.get_node_or_null(path) as Control
		if node:
			if value:original_visibility[path]=node.visible;node.hide()
			elif original_visibility.has(path):node.visible=original_visibility[path]
	if not value:original_visibility.clear()
	if eye:eye.queue_redraw()
	_layout()

func _layout()->void:
	if not ready_ok or size.x<1. or size.y<1.:return
	cover._layout()
	var factor:float=cover.canvas.scale.x
	var logical:Vector2=cover.aspect/factor
	var intro:Node2D=cover.nodes[ROOT_PATH+"/content/intro"]
	intro.visible=page==0
	cover.nodes[ROOT_PATH+"/content/character"].position=cover.character_base_position-Vector2(145. if page!=0 else 0.,0.)
	var transform_value:Transform2D=get_global_transform().affine_inverse()*actor.get_global_transform()
	var bounds:Rect2=actor.bounds();touch.position=transform_value*bounds.position;touch.size=bounds.size*Vector2(transform_value.x.length(),transform_value.y.length())
	if custom_ui:
		custom_ui.scale=Vector2.ONE*factor;custom_ui.size=logical;custom_ui.visible=true
	if basic:
		var name_node:Node2D=cover.nodes[ROOT_PATH+"/content/intro/container/#txt_name"]
		basic.position=cover.canvas.get_global_transform().affine_inverse()*name_node.get_global_transform().origin+Vector2(0,50)
		basic.visible=page==0
	if eye:eye.position=Vector2(size.x-330*factor,30*factor);eye.scale=Vector2.ONE*factor
	if subtitle_overlay:
		subtitle_overlay.transform=get_global_transform()
		subtitle.scale=Vector2.ONE*factor;subtitle.logical_size=logical
		lift=0.
		subtitle.lift=lift
	if active:
		var info:=_remember("InfoPanel")
		if info:info.hide()
		var ascension:=_remember("AscensionPanel")
		if ascension:ascension.hide()

func set_active(value:bool)->void:
	if not value:
		if clean_mode:_toggle_clean(false)
		if eye:eye.set_pressed_no_signal(false);eye.queue_redraw()
		var ascension:=native_screen.get_node_or_null("AscensionPanel") as Control if is_instance_valid(native_screen) else null
		if ascension and native_states.has("AscensionPanel"):ascension.visible=native_states.AscensionPanel.visible
		if is_instance_valid(native_screen):
			var settings:=native_screen.get_node_or_null("SothebySettingsPanel")
			if settings:settings.queue_free()
	super.set_active(value)
	if subtitle_overlay:subtitle_overlay.visible=value

func _process(delta:float)->void:
	super._process(delta)
	if current_voice and voice!=null and not voice.playing:current_voice.text="英文配音 · 点击台词播放"

