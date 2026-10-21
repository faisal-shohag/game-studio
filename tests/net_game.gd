## Two-process LAN test through the real room screens + game. Run both (game: ludo | snakes | cards |
## carrom, which plays Classic, or Freestyle with `freestyle` added to the host command | penfight,
## which plays Turns best of 3, or Real-time with `realtime` added to the host command):
##   godot --headless --path . tests/run.tscn -- tests/net_game.gd host ludo
##   godot --headless --path . tests/run.tscn -- tests/net_game.gd join ludo
## Each auto-taps its own seat; both print FINAL board, which must match.
## The joiner only names the game to check it: the host's room tells it what to load.
## Add `drop` to the join command: client quits mid-game, host's bot must finish its seat.
## After the game the host presses Play Again; both print RESTARTED true.
## Avatars: the host plays with a photo, the guest with face 5; both print `avatars:`, which must match.
## Cards: FINAL compares public info only, and the client prints SECRET ok if every event and view
## it received carried only its own cards (until game over, when every hand is revealed).
## Carrom: each phone shoots random legal shots for its seat; FINAL compares coin positions
## (rounded), scores and winners, so the guest's replays must have snapped to the host's state.
## Pen Fight: each phone picks a random pen, then flicks random legal flicks for its seat (Real-time:
## whenever its cooldown allows); FINAL compares round wins, winners, which pens are out and each
## seat's flicks (the guest's must be there: its flicks reached the host).
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var hosting := "host" in args
	var game_id := "ludo"
	for g in ["snakes", "cards", "carrom", "penfight"]:
		if g in args:
			game_id = g
	Engine.time_scale = 20
	UI.settings.set_value("player", "name", "Host Hana" if hosting else "Guest Gil")  # not saved to disk
	var pic := Image.create(300, 300, false, Image.FORMAT_RGB8)
	pic.fill(Color.ORANGE)
	UI._avatar = {"photo": UI.Avatar.photo_from(pic, Rect2(0, 0, 300, 300))} if hosting else {"face": 5}  # not saved either
	await get_tree().process_frame
	if hosting:
		var variant := ""
		var rounds := 0
		if game_id == "carrom":
			variant = "freestyle" if "freestyle" in args else "classic"
		elif game_id == "penfight":
			variant = "realtime" if "realtime" in args else "turns"
			rounds = 3
		UI.go("res://ui/screens/lan_room.gd", {"hosting": true, "game": game_id, "variant": variant, "rounds": rounds})
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
		if k == (60 if game_id == "penfight" else 300) and "drop" in args:  # Pen Fight Real-time is over fast
			print("client leaving mid-game")
			get_tree().quit()
			return
		if game_id == "penfight":
			if game.view.get("phase") == "over" and game._results != null:
				break
			if game._pick != null:  # pick as the overlay would, without saving the choice to disk
				game._pick.queue_free()
				game._pick = null
				var type: String = game.Physics.TYPES.pick_random()
				if hosting:
					game._host_pick(game.me, type, 0)
				else:
					game.waiting_host = true
					game._pick_request.rpc_id(1, type)
			elif game.variant == "turns" and game._my_turn():
				game._intent(_pen_flick(game), game.me)
			elif game.variant == "realtime" and game.can_flick(game.me):
				game.live_flick(game.me, _pen_flick(game))
			continue
		if game_id == "carrom":
			if game.view.get("phase") == "over":
				break
			if game._my_turn():
				var x := randf_range(game.Rules.BASE_MIN, game.Rules.BASE_MAX)
				if game.Rules.can_place(game.view, game.me, x):
					game._intent({"x": x, "angle": randf_range(-1.2, 1.2), "power": randf_range(0.3, 1.0)}, game.me)
			continue
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
	if hosting:
		await get_tree().create_timer(20.0).timeout  # and print FINAL before Play Again replaces its game
	print("FINAL ", _board(game))
	if game_id == "cards" and not hosting:
		print("SECRET ", "ok" if leaks.is_empty() else "LEAKED %s" % [leaks[0]])
	if hosting:  # Play Again must restart every phone
		game._play_again()
	await get_tree().create_timer(40.0).timeout
	var fresh: Node = get_tree().root.get_node_or_null("Screen")
	# Carrom: the shot clock may already have fired on one phone, so compare what a restart keeps
	print("RESTARTED ", fresh != game, " ", [fresh.variant, fresh.view.colors] if game_id == "carrom"
		else [fresh.variant, fresh.rounds, fresh.view.colors] if game_id == "penfight" else _board(fresh))
	get_tree().quit()


## A random flick at one of the other pens still on the desk.
func _pen_flick(game: Node) -> Dictionary:
	var mine: Dictionary = game.Rules.pen_of(game.view, game.me)
	var others: Array = game.view.world.pens.filter(func(p): return p.id != game.me and not p.out)
	var target: Dictionary = others.pick_random() if not others.is_empty() else mine
	var aim := Vector2(target.x - mine.x, target.y - mine.y).angle() + randf_range(-0.3, 0.3)
	return {"grab": randf_range(-0.6, 0.6), "angle": wrapf(aim, -PI, PI), "power": randf_range(0.4, 1.0)}


## What both phones must agree on. Cards: public info only (a client has no state).
func _board(game: Node) -> Array:
	if game.get("view") != null and game.view.has("round_wins"):  # Pen Fight
		var v: Dictionary = game.view
		var flicks: Array = v.colors.map(func(c): return v.stats[c].flicks)
		return [v.phase, v.mode, v.round_wins, v.winners, v.world.pens.map(func(p): return [p.id, p.out]), flicks]
	if game.get("view") != null and game.view.has("pieces"):  # Carrom
		var v: Dictionary = game.view
		var coins: Array = v.pieces.map(func(p): return [p.id, roundi(p.x), roundi(p.y)])
		coins.sort()
		return [v.phase, v.variant, coins, v.scores, v.winners]
	if game.get("view") != null:
		var v: Dictionary = game.view
		return [v.get("phase"), v.get("discard", [-1]).back(), v.get("counts"), v.get("winners")]
	var s: Dictionary = game.state
	return [s.phase, s.tokens if s.has("tokens") else s.pos, s.winners]
