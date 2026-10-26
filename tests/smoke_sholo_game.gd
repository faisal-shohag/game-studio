## Run: godot --headless --path . tests/run.tscn -- tests/smoke_sholo_game.gd
## Plays a full bot-vs-bot game through the real scene (sped up) and checks it ends.
extends Node


func _ready() -> void:
	Engine.time_scale = 50
	var game = load("res://games/sholo/sholo_game.tscn").instantiate()
	game.seats = ["bot", "off", "bot", "off"]
	get_tree().root.add_child.call_deferred(game)
	for k in 60000:
		await get_tree().process_frame
		if game.is_inside_tree() and game.state.phase == "over":
			print("sholo scene: OK, winners ", game.state.winners)
			get_tree().quit(0)
			return
	printerr("FAIL: sholo scene game did not finish")
	get_tree().quit(1)
