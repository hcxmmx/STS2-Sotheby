extends SceneTree

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Expected output PCK path");quit(1);return
	var packer:=PCKPacker.new()
	if packer.pck_start(args[0])!=OK:push_error("Cannot create output pack");quit(1);return
	var files:Array[String]=[]
	_collect("res://Sotheby_Hcxmmx",files)
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://../asset_manifest.json"))
	for row in manifest.files:
		if str(row.path).begins_with("images/") and str(row.path).ends_with(".png"):files.append("res://"+str(row.path))
	for path in files:
		if packer.add_file(path,path)!=OK:push_error("Cannot pack "+path);quit(1);return
		if path.get_extension() in ["png","ttf","otf"]:
			var imported:=path+".import";var config:=ConfigFile.new()
			if config.load(imported)!=OK:push_error("Import missing: "+path);quit(1);return
			var data:String=config.get_value("remap","path")
			if not data.begins_with("res://.godot/imported/"):push_error("Invalid import mapping");quit(1);return
			if packer.add_file(imported,imported)!=OK or packer.add_file(data,data)!=OK:push_error("Cannot pack imported texture/font");quit(1);return
	if packer.flush()!=OK:push_error("PCK flush failed");quit(1);return
	print("Packed project resources: ",files.size())
	quit()

func _collect(directory:String,files:Array[String])->void:
	for child in DirAccess.get_directories_at(directory):
		if child=="Dev":continue
		_collect(directory.path_join(child),files)
	for name_value in DirAccess.get_files_at(directory):
		if name_value.get_extension() in ["gd","gdshader","tscn","json","png","skel","atlas","wav","ttf","otf","bin"]:files.append(directory.path_join(name_value))
