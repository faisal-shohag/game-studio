## Two-process LAN test through the real room screens + game. Run both:
##   godot --headless --path . tests/run.tscn -- tests/net_ludo.gd host
##   godot --headless --path . tests/run.tscn -- tests/net_ludo.gd join
## Each auto-taps its own seat; both print FINAL board, which must match.
## Add `drop` to the join command: client quits mid-game, host's bot must finish its seat.
## After the game the host presses Play Again; both print RESTARTED true.
extends Node


func _ready() -> void:
	var hosting := "host" in OS.get_cmdline_user_args()
	Engine.time_scale = 20
	UI.settings.set_value("player", "name", "Host Hana" if hosting else "Guest Gil")  # not saved to disk
	await get_tree().process_frame
	if hosting:
		UI.go("res://ui/screens/lan_room.gd", {"hosting": true})
		var room: Node = UI.current
		while multiplayer.get_peers().is_empty():
			await get_tree().process_frame
		await get_tree().create_timer(10.0).timeout  # ~0.5 s real: the guest's name arrives
		room._on_start()
	else:
		UI.go("res://ui/screens/lan_find.gd")
		var find: Node = UI.current
		await get_tree().create_timer(40.0).timeout  # ~2 s real, enough for a broadcast
		print("discovered rooms: ", find.found.size())
		find._join("127.0.0.1")
	var game: Node
	while game == null or game.get("state") == null:
		await get_tree().process_frame
		game = get_tree().root.get_node_or_null("Screen")
	print("seats: ", game.seats, " names: ", game.names)
	for k in 200000:
		await get_tree().process_frame
		if k == 300 and "drop" in OS.get_cmdline_user_args():
			print("client leaving mid-game")
			get_tree().quit()
			return
		var s: Dictionary = game.state
		if s.phase == "over":
			break
		if game.busy or game.waiting_host or game.seats[s.turn] != "human":
			continue
		if s.phase == "roll":
			game._intent("roll", 0)
		elif game.Rules.legal_moves(s).size() > 1:
			game._intent("move", game.Rules.legal_moves(s).pick_random())
	await get_tree().create_timer(20.0).timeout  # let client finish last animation
	print("FINAL ", game.state.tokens, " ", game.state.winners)
	if hosting:  # Play Again must restart every phone
		game._play_again()
	await get_tree().create_timer(40.0).timeout
	var fresh: Node = get_tree().root.get_node_or_null("Screen")
	print("RESTARTED ", fresh != game, " ", fresh.state.phase, " ", fresh.state.tokens[0])
	get_tree().quit()
