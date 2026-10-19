extends RefCounted

const PATH:="user://sotheby_skin.cfg"
const DEFAULTS:={"mode":"combo","ultimate_enabled":true,"ultimate_mode":"rhythm","ultimate_card":"OUTBREAK","ultimate_camera":true,"ultimate_post":true,"ultimate_shake":true,"combat_voice":true,"bilingual_subtitles":true,"voice_volume":1.0,"auto_greeting":true,"home_touch_interval":0.8,"combat_voice_interval":4.0}
const RANGES:={"voice_volume":[0.0,1.0],"home_touch_interval":[0.0,15.0],"combat_voice_interval":[0.0,15.0]}

static func _validated(key:String,value):
	if RANGES.has(key):
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return DEFAULTS[key]
		return clampf(float(value),float(RANGES[key][0]),float(RANGES[key][1]))
	if DEFAULTS[key] is bool:return value if value is bool else DEFAULTS[key]
	if key=="mode":return value if value in ["combo","full"] else DEFAULTS[key]
	if key=="ultimate_mode":return value if value in ["rhythm","full"] else DEFAULTS[key]
	return str(value)

static func read()->Dictionary:
	var result:=DEFAULTS.duplicate()
	var cfg:=ConfigFile.new()
	if cfg.load(PATH)==OK:
		for key in DEFAULTS:result[key]=_validated(key,cfg.get_value("visuals",key,DEFAULTS[key]))
	return result

static func write(key:String,value)->Error:
	if not DEFAULTS.has(key):return ERR_INVALID_PARAMETER
	var cfg:=ConfigFile.new();cfg.load(PATH)
	cfg.set_value("visuals",key,_validated(key,value))
	return cfg.save(PATH)
