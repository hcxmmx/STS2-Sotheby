extends Node

var cover
var warm_view:SubViewport
var preparing:=false
var retained:Array=[]

func _ready()->void:
	add_to_group("sotheby_cover_cache")
	request()

func request()->void:
	if preparing or is_instance_valid(cover):return
	preparing=true
	await get_tree().create_timer(1.5).timeout
	# Dynamic image/font references are not PackedScene dependencies. Load them
	# off-thread and retain them until the prepared scene takes ownership.
	var paths:Array[String]=[]
	_collect("res://Sotheby_Hcxmmx/Cover",paths)
	paths.append("res://Sotheby_Hcxmmx/Assets/portrait/300901_sufubi_p.png")
	paths.append("res://Sotheby_Hcxmmx/Portrait.tscn")
	for path in paths:
		var error:=ResourceLoader.load_threaded_request(path)
		if error!=OK:continue
		while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED:
			retained.append(ResourceLoader.load_threaded_get(path))
		await get_tree().process_frame
	warm_view=SubViewport.new();warm_view.size=Vector2i(1920,1080)
	warm_view.disable_3d=true;warm_view.transparent_bg=true
	warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(warm_view)
	cover=load("res://Sotheby_Hcxmmx/Portrait.tscn").instantiate();warm_view.add_child(cover)
	if not cover.is_ready():
		cover.queue_free();cover=null;warm_view.queue_free();preparing=false;return
	cover.prepare_pages();cover._layout()
	# Draw each page once offscreen to populate font glyphs/meshes and shaders.
	for page in range(5):
		cover._select_page(page)
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	for row in cover.voice.catalog.values():
		var path:=str(row.audio.file)
		if not cover.voice.streams.has(path):cover.voice.streams[path]=AudioStreamWAV.load_from_file(path)
		await get_tree().process_frame
	cover._select_page(1);cover._select_voice_scope("combat")
	await RenderingServer.frame_post_draw
	cover._select_voice_scope("home")
	await cover.subtitle.warm_catalog(cover.voice.catalog)
	cover._select_page(0);cover.actor.portrait_idle(0.0);cover.set_active(false)
	warm_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	retained.clear();preparing=false
	print("[SothebySkin] Cover warmup ready (portrait, pages, voices, subtitle glyphs).")

func acquire():
	if preparing or not is_instance_valid(cover):return null
	var result=cover;cover=null
	warm_view.remove_child(result);warm_view.queue_free();warm_view=null
	# Scene lifetime remains owned by the select screen, not this cache.
	result.tree_exited.connect(_refill,CONNECT_ONE_SHOT)
	return result

func _refill()->void:
	# Defer until the old screen has left the tree; during shutdown the cache
	# disappears before this callback can start another asynchronous warmup.
	request.call_deferred()

func _collect(directory:String,paths:Array[String])->void:
	for child in DirAccess.get_directories_at(directory):_collect(directory.path_join(child),paths)
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["png","ttf","otf"]:paths.append(directory.path_join(file))
