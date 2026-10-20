## Entry scene: first launch asks for a name, otherwise straight to Home.
extends Node


func _ready() -> void:
	UI.reset_to.call_deferred("res://ui/screens/home.gd" if UI.player_name != "" else "res://ui/screens/welcome.gd")
	queue_free()
