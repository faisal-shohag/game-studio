## Run: godot --headless --path . tests/run.tscn -- tests/smoke_carrom_game.gd
## Plays a 4-bot Freestyle game and a 2-bot Classic game through the real scene (sped up) and
## checks both end.
extends Node


func _ready() -> void:
	Engine.time_scale = 50
	var ok := true
	for setup in [["freestyle", ["bot", "bot", "bot", "bot"]], ["classic", ["bot", "off", "bot", "off"]]]:
		ok = await _play(setup[0], setup[1]) and ok
	get_tree().quit(0 if ok else 1)


func _play(variant: String, seats: Array) -> bool:
	var game = load("res://games/carrom/carrom_game.tscn").instantiate()
	if game.get_script() == null:  # script failed to parse: fail now instead of hanging
		printerr("FAIL: carrom scene did not load")
		return false
	game.variant = variant
	game.seats = seats
	get_tree().root.add_child.call_deferred(game)
	for k in 200000:
		await get_tree().process_frame
		if game.is_inside_tree() and game.view.phase == "over" and game._results != null:
			print("carrom %s scene: OK, %d shots, winners %s, scores %s" % [variant, game.view.shots, game.view.winners, game.view.scores])
			game.queue_free()
			await get_tree().process_frame
			return true
	printerr("FAIL: carrom %s scene game did not finish" % variant)
	return false
