## Run: godot --headless --path . tests/run.tscn -- tests/smoke_cards_game.gd
## Plays a full 4-bot game through the real scene (sped up) and checks it ends.
extends Node


func _ready() -> void:
	Engine.time_scale = 50
	var game = load("res://games/cards/cards_game.tscn").instantiate()
	game.seats = ["bot", "bot", "bot", "bot"]
	get_tree().root.add_child.call_deferred(game)
	for k in 60000:
		await get_tree().process_frame
		if game.is_inside_tree() and game.view.phase == "over":
			print("cards scene: OK, winners ", game.view.winners, ", +4s ", game.plus4)
			get_tree().quit(0)
			return
	printerr("FAIL: cards scene game did not finish")
	get_tree().quit(1)
