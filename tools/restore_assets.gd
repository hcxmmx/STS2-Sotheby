extends SceneTree

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Expected a local SothebySkin PCK path");quit(1);return
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://../asset_manifest.json"))
	if not ProjectSettings.load_resource_pack(args[0]):push_error("Cannot mount local resource pack");quit(1);return
	for row in manifest.files:
		var relative:String=row.path
		if relative.contains("..") or relative.is_absolute_path():push_error("Invalid manifest path");quit(1);return
		var virtual_path:="res://"+relative
		if not FileAccess.file_exists(virtual_path):push_error("Missing private asset: "+relative);quit(1);return
		var destination:=ProjectSettings.globalize_path(virtual_path)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var bytes:=FileAccess.get_file_as_bytes(virtual_path)
		var file:=FileAccess.open(destination,FileAccess.WRITE)
		if file==null:push_error("Cannot write "+destination);quit(1);return
		file.store_buffer(bytes);file.close()
	print("Restored local private assets: ",manifest.files.size())
	quit()
