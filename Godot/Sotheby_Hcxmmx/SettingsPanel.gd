extends CanvasLayer

const Settings=preload("res://Sotheby_Hcxmmx/Settings.gd")
const INK=Color("e7e4d9")
const MUTED=Color("b5ad9b")
const ACCENT=Color("ce763e")
const DESIGN=Vector2(1160,800)
var cards:Array=[]
var list:ItemList
var search:LineEdit
var selected:Label
var note:Label
var settings:Dictionary
var shown:Array=[]
var page:Control
var panels:Array=[]
var tabs:Array=[]
var controls:Dictionary={}
var section:=0

class ArchiveToggle extends Button:
	func _draw()->void:
		var c:=Color("ce763e") if button_pressed else Color("aaa38f")
		var center:=Vector2(18,size.y*.5)
		var points:=PackedVector2Array([center+Vector2(0,-8),center+Vector2(8,0),center+Vector2(0,8),center+Vector2(-8,0),center+Vector2(0,-8)])
		draw_polyline(points,c,1.5,true)
		if button_pressed:draw_colored_polygon(PackedVector2Array([center+Vector2(0,-4),center+Vector2(4,0),center+Vector2(0,4),center+Vector2(-4,0)]),c)

class ArchiveSlider extends HSlider:
	func _draw()->void:
		var left:=Vector2(8,size.y*.5);var right:=Vector2(size.x-8,size.y*.5)
		var t:=float((value-min_value)/maxf(.001,max_value-min_value))
		draw_line(left,right,Color("686451"),2.,true)
		var at:=left.lerp(right,t)
		draw_line(left,at,Color("ce763e"),3.,true)
		draw_circle(at,6.,Color("e2d3b5"))

class ArchiveTab extends Button:
	func _draw()->void:
		var c:=Color("ce763e") if button_pressed else Color("aaa38f")
		var p:=Vector2(22,37)
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(7,0),p+Vector2(0,7),p+Vector2(-7,0)]),c)
		if button_pressed:draw_polyline(PackedVector2Array([p+Vector2(0,-15),p+Vector2(15,0),p+Vector2(0,15),p+Vector2(-15,0),p+Vector2(0,-15)]),c,1.4,true)

func _ready()->void:
	layer=110;settings=Settings.read()
	var screen:=Control.new();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(screen);screen.theme=_theme()
	var veil:=ColorRect.new();veil.color=Color(0,0,0,.8);screen.add_child(veil);veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page=Control.new();page.size=DESIGN;page.clip_contents=true;screen.add_child(page)
	_art("bg_fmand2.png",Vector2.ZERO,DESIGN);_art("bg_leftdown.png",Vector2(0,380),Vector2(600,420),.55);_art("bg_noise2.png",Vector2.ZERO,DESIGN,.25)
	var border:=Panel.new();border.mouse_filter=Control.MOUSE_FILTER_IGNORE;border.size=DESIGN;border.add_theme_stylebox_override("panel",_box(Color(0,0,0,0),Color("776a51"),1));page.add_child(border)
	var title:=_label(page,"苏芙比 · 演出设置",36);title.position=Vector2(48,35)
	var english:=_label(page,"SOTHEBY   /   PERFORMANCE & PREFERENCES",16,MUTED);english.position=Vector2(50,90)
	_rule(Vector2(48,145),Vector2(1064,1));_rule(Vector2(300,182),Vector2(1,505))
	var close:=Button.new();close.text="×";close.tooltip_text="关闭";close.position=Vector2(1060,35);close.size=Vector2(52,48);close.add_theme_font_size_override("font_size",32);close.pressed.connect(queue_free);page.add_child(close)
	var titles:=["演出","语音与互动","卡牌绑定"];var subtitles:=["PERFORMANCE","VOICE & INTERACTION","CARD BINDING"]
	for i in range(3):
		var tab:=ArchiveTab.new();tab.toggle_mode=true;tab.position=Vector2(42,202+i*116);tab.size=Vector2(235,96);tab.flat=true;tab.pressed.connect(_select_section.bind(i));page.add_child(tab)
		var cn:=_label(tab,titles[i],30);cn.position=Vector2(55,15)
		var en:=_label(tab,subtitles[i],13,MUTED);en.position=Vector2(56,58);tabs.append({"button":tab,"cn":cn,"en":en})
		var content:=VBoxContainer.new();content.position=Vector2(350,185);content.size=Vector2(755,490);content.add_theme_constant_override("separation",15);page.add_child(content);panels.append(content)
	var signature:=_label(page,"Sotheby",42,ACCENT);signature.position=Vector2(48,615)
	var caption:=_label(page,"原衣着 / ORIGINAL COSTUME",14,MUTED);caption.position=Vector2(49,690)
	_build_performance(panels[0]);_build_voice(panels[1]);_build_binding(panels[2])
	_rule(Vector2(48,721),Vector2(1064,1))
	note=_label(page,"更改自动保存并即时应用。",18,MUTED);note.position=Vector2(350,743);note.size=Vector2(550,38);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var done:=Button.new();done.text="完成 / CLOSE";done.position=Vector2(922,739);done.size=Vector2(184,42);done.pressed.connect(queue_free);page.add_child(done)
	_filter("");_selected_text();_select_section(0);_dependencies();_layout();close.grab_focus();get_viewport().size_changed.connect(_layout)

func _theme()->Theme:
	var result:=Theme.new();result.default_font=load("res://Sotheby_Hcxmmx/Cover/fonts/hwzs.ttf");result.default_font_size=23
	for type in ["Button","OptionButton","LineEdit","ItemList","PopupMenu"]:
		result.set_color("font_color",type,INK);result.set_color("font_hover_color",type,ACCENT);result.set_color("font_pressed_color",type,ACCENT);result.set_color("font_focus_color",type,ACCENT);result.set_color("font_disabled_color",type,Color("777569"))
	for type in ["Button","OptionButton"]:
		result.set_stylebox("normal",type,_box(Color("22271f"),Color("665f4d"),1));result.set_stylebox("hover",type,_box(Color("35352a"),ACCENT,1))
		result.set_stylebox("pressed",type,_box(Color("393226"),ACCENT,1));result.set_stylebox("disabled",type,_box(Color("22251f"),Color("46473d"),1));result.set_stylebox("focus",type,_box(Color(0,0,0,0),ACCENT,1))
	for state in ["normal","focus"]:result.set_stylebox(state,"LineEdit",_box(Color("1c231e"),ACCENT if state=="focus" else Color("72684e"),1))
	result.set_color("font_placeholder_color","LineEdit",MUTED);result.set_color("caret_color","LineEdit",ACCENT)
	result.set_stylebox("panel","ItemList",_box(Color("1b221d"),Color("72684e"),1))
	for state in ["selected","selected_focus","hovered"]:result.set_stylebox(state,"ItemList",_box(Color("443a2b"),Color("88714e"),1))
	result.set_color("font_selected_color","ItemList",Color("e6af72"));result.set_stylebox("panel","PopupMenu",_box(Color("20271f"),Color("9a7c52"),1));result.set_stylebox("hover","PopupMenu",_box(Color("42392a"),ACCENT,1));result.set_constant("v_separation","PopupMenu",12)
	return result

func _box(color:Color,border:Color,width:int)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=border;style.set_border_width_all(width)
	style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=7;style.content_margin_bottom=7;return style

func _art(file:String,at:Vector2,extent:Vector2,alpha:float=1.0)->void:
	var image:=TextureRect.new();image.texture=load("res://Sotheby_Hcxmmx/Cover/images/"+file);image.position=at;image.size=extent;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_SCALE;image.modulate.a=alpha;image.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(image)

func _rule(at:Vector2,extent:Vector2)->void:
	var line:=ColorRect.new();line.position=at;line.size=extent;line.color=Color("716c58");line.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(line)

func _label(host:Node,text_value:String,font_size:int=23,color:Color=INK)->Label:
	var label:=Label.new();label.text=text_value;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;host.add_child(label);return label

func _heading(host:Node,title:String,description:String)->void:
	_label(host,title,31,INK)
	var detail:=_label(host,description,19,MUTED);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size=Vector2(0,55)

func _build_performance(host:Node)->void:
	_heading(host,"演出节奏","按自己的出牌习惯选择。仅调整人物与特效演出，卡牌结算照常。")
	_choice(host,"普通技能","mode",["动作接续","完整演出 · 适度提速"],["combo","full"]);_toggle(host,"启用绑定卡牌的大招演出","ultimate_enabled")
	_choice(host,"大招节奏","ultimate_mode",["节奏剪辑 · 2.7 秒","完整演出 · 7.4 秒"],["rhythm","full"])
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);host.add_child(row)
	_toggle(row,"跟随镜头","ultimate_camera");_toggle(row,"爆发后期","ultimate_post");_toggle(row,"镜头震动","ultimate_shake")
	var hint:=_label(host,"下一张牌可打断大招镜头；声音保持原速、原音高。",19,MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _build_voice(host:Node)->void:
	_heading(host,"声音与互动","音量同时作用于主页与战斗，并继续服从游戏总音量、音效音量和后台静音。")
	_slider(host,"角色语音音量","voice_volume",0.,1.,.05,true)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);host.add_child(row)
	_toggle(row,"自动问候","auto_greeting");_toggle(row,"战斗配音","combat_voice");_toggle(row,"中英字幕","bilingual_subtitles")
	_slider(host,"主页点击间隔","home_touch_interval",0.,15.,.2);_slider(host,"战斗语音间隔","combat_voice_interval",0.,15.,.5)
	var hint:=_label(host,"主页间隔只限制点击互动，语音页可自由点播。\n战斗间隔限制普通播报；开场、胜利及大招保留优先播放。",19,MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _build_binding(host:Node)->void:
	_heading(host,"大招绑定","仅显示猎人卡池。选择一张卡触发大招演出，卡牌本身的效果保持原样。")
	selected=_label(host,"",23,Color("e1ae73"));selected.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;selected.custom_minimum_size=Vector2(0,40)
	search=LineEdit.new();search.placeholder_text="搜索猎人卡牌名称或 ID";host.add_child(search);search.text_changed.connect(_filter)
	list=ItemList.new();list.custom_minimum_size=Vector2(0,200);list.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.add_child(list)
	list.item_selected.connect(func(i:int):_save("ultimate_card",str(shown[i].id));_selected_text())
	var reset:=Button.new();reset.text="绑定恢复为毒性爆发";reset.pressed.connect(func():_save("ultimate_card","OUTBREAK");_selected_text();_filter(search.text));host.add_child(reset)

func _layout()->void:
	if page==null:return
	var extent:=get_viewport().get_visible_rect().size;var factor:=minf(1.,minf((extent.x-32)/DESIGN.x,(extent.y-32)/DESIGN.y))
	page.scale=Vector2.ONE*factor;page.position=(extent-DESIGN*factor)*.5

func _select_section(index:int)->void:
	section=index
	for i in range(3):
		panels[i].visible=i==index;tabs[i].button.set_pressed_no_signal(i==index);tabs[i].button.queue_redraw()
		tabs[i].cn.modulate=ACCENT if i==index else MUTED;tabs[i].en.modulate=Color("a8794a") if i==index else MUTED

func set_cards(value:Array)->void:
	cards=value
	if list!=null:_filter("");_selected_text()

func _selected_text()->void:
	var name_value:=str(settings.ultimate_card)+"（当前未加载）"
	for card in cards:
		if str(card.id)==str(settings.ultimate_card):name_value=str(card.title)+"  ["+str(card.id)+"]";break
	selected.text="当前绑定："+name_value

func _filter(query:String)->void:
	list.clear();shown.clear()
	for card in cards:
		if query.is_empty() or query.to_lower() in (str(card.title)+" "+str(card.id)).to_lower():shown.append(card);list.add_item(str(card.title)+"  ["+str(card.id)+"]")
	for i in shown.size():
		if str(shown[i].id)==str(settings.ultimate_card):list.select(i);break

func _save(key:String,value)->void:
	var error:=Settings.write(key,value)
	if error!=OK:
		if note!=null:note.text="设置保存失败："+error_string(error)
		return
	settings=Settings.read();get_tree().call_group("sotheby_battles","reload_settings");get_tree().call_group("sotheby_portraits","reload_settings");get_tree().call_group("sotheby_voices","reload_settings")
	if key=="ultimate_enabled" and value==true:get_tree().call_group("sotheby_ultimate_cache","request")
	_dependencies()

func _dependencies()->void:
	for key in ["ultimate_mode","ultimate_camera","ultimate_post","ultimate_shake"]:
		if controls.has(key):controls[key].disabled=not bool(settings.ultimate_enabled)
	if controls.has("combat_voice_interval"):controls.combat_voice_interval.editable=bool(settings.combat_voice)

func _choice(host:Node,title:String,key:String,labels:Array,values:Array)->void:
	var row:=HBoxContainer.new();row.custom_minimum_size.y=48;host.add_child(row)
	var label:=_label(row,title);label.custom_minimum_size.x=225
	var options:=OptionButton.new();options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for text_value in labels:options.add_item(text_value)
	options.select(maxi(0,values.find(settings[key])));options.item_selected.connect(func(i:int):_save(key,values[i]));row.add_child(options);controls[key]=options

func _toggle(host:Node,title:String,key:String)->void:
	var button:=ArchiveToggle.new();button.text="     "+title;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.toggle_mode=true;button.flat=true;button.custom_minimum_size=Vector2(0,46);button.button_pressed=bool(settings[key])
	button.toggled.connect(func(value:bool):button.queue_redraw();_save(key,value));host.add_child(button);controls[key]=button

func _slider(host:Node,title:String,key:String,low:float,high:float,step_value:float,percent:bool=false)->void:
	var row:=HBoxContainer.new();row.custom_minimum_size.y=45;row.add_theme_constant_override("separation",16);host.add_child(row)
	var label:=_label(row,title);label.custom_minimum_size.x=210
	var slider:=ArchiveSlider.new();slider.min_value=low;slider.max_value=high;slider.step=step_value;slider.custom_minimum_size=Vector2(300,36);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var transparent:=GradientTexture2D.new();transparent.width=16;transparent.height=16;transparent.gradient=Gradient.new();transparent.gradient.colors=PackedColorArray([Color.TRANSPARENT,Color.TRANSPARENT])
	for icon in ["grabber","grabber_highlight","grabber_disabled"]:slider.add_theme_icon_override(icon,transparent)
	for state in ["slider","grabber_area","grabber_area_highlight"]:slider.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	slider.value=float(settings[key]);row.add_child(slider);controls[key]=slider
	var number:=_label(row,_number(slider.value,percent),23,Color("e1ae73"));number.custom_minimum_size.x=86;number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(value:float):number.text=_number(value,percent);slider.queue_redraw();_save(key,value))

func _number(value:float,percent:bool)->String:
	return str(roundi(value*100))+"%" if percent else "%.1f 秒"%value

func _input(event:InputEvent)->void:
	if event.is_action_pressed("ui_cancel"):get_viewport().set_input_as_handled();queue_free()

func _process(_delta:float)->void:
	var owner_node:=get_parent()
	if owner_node is CanvasItem and not owner_node.is_visible_in_tree():queue_free()
