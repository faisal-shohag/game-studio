## Run: godot --headless --path . tests/run.tscn -- tests/smoke_penfight_game.gd
## Plays a 4-bot Turns best-of-3 match and a 2-bot Turns single round through the real scene
## (sped up) and checks both end.
extends Node


func _ready() -> void:
	Engine.time_scale = 50
	var ok := true
	for setup in [["turns", 3, ["bot", "bot", "bot", "bot"]], ["turns", 1, ["bot", "off", "bot", "off"]]]:
		ok = await _play(setup[0], setup[1], setup[2]) and ok
	get_tree().quit(0 if ok else 1)


func _play(variant: String, rounds: int, seats: Array) -> bool:
	var game = load("res://games/penfight/penfight_game.tscn").instantiate()
	if game.get_script() == null:  # script failed to parse: fail now instead of hanging
		printerr("FAIL: penfight scene did not load")
		return false
	game.variant = variant
	game.rounds = rounds
	game.seats = seats
	get_tree().root.add_child.call_deferred(game)
	for k in 200000:
		await get_tree().process_frame
		if game.is_inside_tree() and game.view.phase == "over" and game._results != null:
			print("penfight %s best of %d scene: OK, %d flicks, %d rounds, winners %s, round wins %s" % [variant, rounds, game.view.flicks, game.view.round, game.view.winners, game.view.round_wins])
			game.queue_free()
			await get_tree().process_frame
			return true
	printerr("FAIL: penfight %s scene game did not finish" % variant)
	return false
