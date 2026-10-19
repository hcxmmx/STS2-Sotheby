extends Node

const PATHS := ["res://HextechRunes/audio/hextechReroll.wav", "res://HextechRunes/audio/hextechSelectSilver.wav", "res://HextechRunes/audio/hextechSelectGold.wav", "res://HextechRunes/audio/hextechSelectPrismatic.wav"]
var streams := {}
var players := {}

func get_player(player_name: String) -> AudioStreamPlayer:
	if players.has(player_name) and is_instance_valid(players[player_name]):return players[player_name]
	var player:=AudioStreamPlayer.new();player.name=player_name;player.bus=&"Master";player.process_mode=Node.PROCESS_MODE_ALWAYS;add_child(player)
	players[player_name]=player
	return player

func play_file(path: String, player: AudioStreamPlayer, volume: float) -> bool:
	if path not in PATHS or not is_instance_valid(player):return false
	if not streams.has(path):
		# Keep WAV entirely in the native/GDScript path. Returning a WAV Resource
		# to C# would initialize the incompatible managed AudioStreamWav wrapper.
		var stream=load(path)
		if stream==null or not stream is AudioStream:return false
		streams[path]=stream
	player.stop();player.stream=streams[path];player.volume_linear=clampf(volume,0,1)
	player.set_meta("sotheby_hex_path",path);player.play()
	return true

func inspect_player(player: AudioStreamPlayer) -> Dictionary:
	return {"playing":player.playing,"duration":player.stream.get_length() if player.stream!=null else 0.0,"path":str(player.get_meta("sotheby_hex_path","")),"volume":player.volume_linear,"bus":str(player.bus)}
