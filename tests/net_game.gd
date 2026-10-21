## Two-process LAN test through the real room screens + game. Run both (game: ludo | snakes | cards):
##   godot --headless --path . tests/run.tscn -- tests/net_game.gd host ludo
##   godot --headless --path . tests/run.tscn -- tests/net_game.gd join ludo
## Each auto-taps its own seat; both print FINAL board, which must match.
## The joiner only names the game to check it: the host's room tells it what to load.
## Add `drop` to the join command: client quits mid-game, host's bot must finish its seat.
## After the game the host presses Play Again; both print RESTARTED true.
## Avatars: the host plays with a photo, the guest with face 5; both print `avatars:`, which must match.
## Cards: FINAL compares public info only, and the client prints SECRET ok if every event and view
## it received carried only its own cards (until game over, when every hand is revealed).
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var hosting := "host" in args
	var game_id := "snakes" if "snakes" in args else "cards" if "cards" in args else "ludo"
	Engine.time_scale = 20
	UI.settings.set_value("player", "name", "Host Hana" if hosting else "Guest Gil")  # not saved to disk
	var pic := Image.create(300, 300, false, Image.FORMAT_RGB8)
	pic.fill(Color.ORANGE)
	UI._avatar = {"photo": UI.Avatar.photo_from(pic, Rect2(0, 0, 300, 300))} if hosting else {"face": 5}  # not saved either
	await get_tree().process_frame
	if hosting:
		UI.go("res://ui/screens/lan_room.gd", {"hosting": true, "game": game_id})
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
	print("loaded: ", game.scene_file_path.get_file(), " (expected ", game_id, ")")
	print("seats: ", game.seats, " names: ", game.names)
	print("avatars: ", game.avatars.map(func(a): return "photo" if a.has("photo") else "face %d" % a.face if a.has("face") else "-"))
	var leaks := []
	if game_id == "cards" and not hosting:
		game.shown.connect(func(ev: Dictionary, v: Dictionary):
			if v.has("hands") or v.has("pile") or v.me != game.me or not game.state.is_empty() 					or (v.has("reveal") and v.phase != "over"):
				leaks.append(v)
			if ev.has("ids") and ev.color != game.me and not ev.ids.is_empty():
				leaks.append(ev))
	for k in 200000:
		await get_tree().process_frame
		if k == 300 and "drop" in args:
			print("client leaving mid-game")
			get_tree().quit()
			return
		if game_id == "cards":
			if game.view.get("phase") == "over":
				break
			if game._my_turn():
				game._intent(game.Rules.legal(game.view, game.view.hand).pick_random(), game.me)
			continue
		var s: Dictionary = game.state
		if s.phase == "over":
			break
		if game.busy or game.waiting_host or game.seats[s.turn] != "human":
			continue
		if s.phase == "roll":
			game._intent("roll", 0)
		elif s.phase == "move" and game.Rules.legal_moves(s).size() > 1:  # Ludo only
			game._intent("move", game.Rules.legal_moves(s).pick_random())
	await get_tree().create_timer(20.0).timeout  # let client finish last animation
	print("FINAL ", _board(game))
	if game_id == "cards" and not hosting:
		print("SECRET ", "ok" if leaks.is_empty() else "LEAKED %s" % [leaks[0]])
	if hosting:  # Play Again must restart every phone
		game._play_again()
	await get_tree().create_timer(40.0).timeout
	var fresh: Node = get_tree().root.get_node_or_null("Screen")
	print("RESTARTED ", fresh != game, " ", _board(fresh))
	get_tree().quit()


## What both phones must agree on. Cards: public info only (a client has no state).
func _board(game: Node) -> Array:
	if game.get("view") != null:
		var v: Dictionary = game.view
		return [v.get("phase"), v.get("discard", [-1]).back(), v.get("counts"), v.get("winners")]
	var s: Dictionary = game.state
	return [s.phase, s.tokens if s.has("tokens") else s.pos, s.winners]
