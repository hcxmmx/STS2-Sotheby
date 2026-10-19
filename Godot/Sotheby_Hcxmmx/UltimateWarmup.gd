extends Node

var controller
var preparing:=false
var leased:=false
var warm_view:SubViewport

func _ready()->void:
	add_to_group("sotheby_ultimate_cache")
	request()

func request()->void:
	if preparing or is_instance_valid(controller):return
	var settings=load("res://Sotheby_Hcxmmx/Settings.gd").read()
	if not settings.ultimate_enabled:return
	preparing=true
	# Do not extend the mod initializer or room-attachment call.
	await get_tree().create_timer(1.).timeout
	var path:="res://Sotheby_Hcxmmx/Ultimate.gd"
	var error:=ResourceLoader.load_threaded_request(path)
	if error!=OK:
		preparing=false;push_warning("[SothebySkin] Ultimate warmup load: "+error_string(error));return
	while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED:
		preparing=false;return
	var script=ResourceLoader.load_threaded_get(path)
	warm_view=SubViewport.new();warm_view.size=Vector2i(get_viewport().get_visible_rect().size)
	warm_view.transparent_bg=true;warm_view.disable_3d=true;warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(warm_view)
	controller=script.new();controller.progressive_loading=true;warm_view.add_child(controller)
	while not controller.prepared:await get_tree().process_frame
	# Draw representative phases offscreen, so their meshes and shader variants
	# have been used before the player first triggers the real effect.
	controller.rhythm=false;controller._update_layout();controller.visible=true
	for at in [.95,1.5,2.3,3.5,5.1,6.3,6.85,7.55,8.4]:
		controller.seek(at)
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	controller.visible=false
	controller.fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	controller.reparent(get_tree().root,false)
	warm_view.queue_free();warm_view=null;preparing=false
	print("[SothebySkin] Ultimate warmup ready (offscreen, reusable).")

func acquire():
	if preparing or leased or not is_instance_valid(controller):return null
	leased=true
	return controller

func release(value)->void:
	if not is_instance_valid(controller) or value!=controller:return
	controller.cancel();controller.live_actor=null;controller.targets.clear();leased=false
