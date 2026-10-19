extends "res://Sotheby_Hcxmmx/Cover/Subtitle.gd"
var lift:=0.0
func _process(delta:float)->void:
	super._process(delta)
	position=(logical_size*.5-Vector2(0,lift))*scale.x
