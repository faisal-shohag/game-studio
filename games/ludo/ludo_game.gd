## Ludo table: board, pawns, player cards and dice; drives turns for humans, bots and LAN peers.
extends Node2D

const Rules = preload("res://games/ludo/ludo_rules.gd")
const AI = preload("res://games/ludo/ludo_ai.gd")
const BoardArt = preload("res://games/ludo/board_art.gd")
const Pawn = preload("res://games/shared/pawn.gd")
const PlayerPanel = preload("res://games/shared/player_panel.gd")
const Dice = preload("res://games/shared/dice.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const PLACES := ["1st place", "2nd place", "3rd place"]
const PANEL_SIZE := Vector2(400, 190)

## Seat type per color: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "bot", "bot", "bot"]
## LAN only: peer id per color, 0 = bot (run by host), -1 = off. Empty = offline.
var owners := []
## Display name per color; filled in when empty.
var names := []
## Avatar per color ({} = default look); filled in when empty.
var avatars := []
## Local player's color; their base is drawn bottom-left. -1 = first human seat.
var me := -1

var state: Dictionary
var busy := false
var waiting_host := false  # client sent an intent, host hasn't answered yet
var pending := []  # actions from host that arrived while animating
var table := Node2D.new()  # board + pawns; shaken on captures
var board := BoardArt.new()
var pawn_layer := Node2D.new()
var pawns := []  # pawns[color][i]
var panels := {}  # color -> PlayerPanel
var dice := Dice.new()
var hint := Label.new()
var hud := Control.new()  # cards, dice, hint, back button
var captures := [0, 0, 0, 0]  # per color, for the results screen
var sixes := [0, 0, 0, 0]
var _results: Control
var _turn_seen := -1  # last color we played the "your turn" sound for
var _turns := 0  # quarter turns the board is rotated
var _top_y := 0.0
var _bottom_y := 0.0


func _ready() -> void:
	if not owners.is_empty():
		var my_id := multiplayer.get_unique_id()
		me = owners.find(my_id)
		for c in 4:
			var o: int = owners[c]
			seats[c] = "off" if o == -1 else "human" if o == my_id else "bot" if o == 0 and multiplayer.is_server() else "remote"
		multiplayer.peer_disconnected.connect(_on_peer_left)
		multiplayer.server_disconnected.connect(_on_host_left)
	var colors := []
	for c in 4:
		if seats[c] != "off":
			colors.append(c)
	state = Rules.new_state(colors)
	if me == -1:
		me = seats.find("human")
	if names.is_empty():
		for c in 4:
			var bot: bool = seats[c] == "bot" or (not owners.is_empty() and owners[c] == 0)
			names.append(UI.player_name if c == me else Games.BOT_NAMES[c] if bot else "Player %d" % (c + 1))
	if avatars.is_empty():  # offline: only you have one; bots and pass-and-play friends get the default
		avatars = [{}, {}, {}, {}]
		if me != -1:
			avatars[me] = UI.avatar
	_build(colors)
	_layout()
	_next()


func _build(colors: Array) -> void:
	var oy := maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	_top_y = 230 + oy
	_bottom_y = 1500 + oy
	_turns = posmod(3 - me, 4) if me != -1 else 0
	add_child(table)
	board.position = Vector2(540, 960 + oy)
	board.rotation = _turns * PI / 2
	table.add_child(board)
	pawn_layer.y_sort_enabled = true
	table.add_child(pawn_layer)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	for c in 4:
		var row := []
		for i in 4:
			var p := Pawn.new()
			p.color = UI.COLORS[c]
			p.visible = c in colors
			pawn_layer.add_child(p)
			row.append(p)
		pawns.append(row)
	for c in colors:
		var v := _corner_of(c)
		var panel := PlayerPanel.new()
		panel.color = UI.COLORS[c]
		panel.player_name = names[c]
		panel.avatar = avatars[c]
		panel.size = PANEL_SIZE
		panel.position = Vector2(30 if v in [0, 3] else 650, _top_y if v < 2 else _bottom_y)
		panel.tapped.connect(_on_roll_tap.bind(c))
		hud.add_child(panel)
		panels[c] = panel
	dice.size = Vector2(170, 170)
	dice.position = _dice_spot(state.turn)
	dice.tapped.connect(func(): _on_roll_tap(state.turn))
	hud.add_child(dice)
	hint.position = Vector2(0, _bottom_y + 220)
	hint.size = Vector2(1080, 80)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 46)
	hud.add_child(hint)
	var back := UI.icon_button("back", 120)
	back.position = Vector2(30, 50)
	back.pressed.connect(on_back)
	hud.add_child(back)


func _to_menu() -> void:
	UI.reset_to("res://ui/screens/home.gd")


func on_back() -> void:
	if state.phase == "over":
		_to_menu()
	elif await UI.confirm("Leave game?", "Your progress will be lost." if owners.is_empty() else "You will leave the room."):
		_to_menu()


## Screen corner (0 TL, 1 TR, 2 BR, 3 BL) where color c's base ends up after rotation.
func _corner_of(c: int) -> int:
	return (c + _turns) % 4


func _dice_spot(c: int) -> Vector2:
	return Vector2(455, (_top_y if _corner_of(c) < 2 else _bottom_y) + 10)


## Table position of a token at progress p (i picks the base spot).
func _at(c: int, p: int, i := 0) -> Vector2:
	return board.transform * board.local_pos(c, p, i)


## Snap every pawn to its square; pawns sharing a square shrink and fan out.
func _layout() -> void:
	var groups := {}
	for c in state.colors:
		for i in 4:
			groups.get_or_add(_at(c, state.tokens[c][i], i).round(), []).append(pawns[c][i])
	for at in groups:
		var g: Array = groups[at]
		for k in g.size():
			g[k].position = at if g.size() == 1 else at + Vector2(15, 0).rotated(TAU * k / g.size())
			g[k].base_scale = 1.0 if g.size() == 1 else 0.72


func _next() -> void:
	if not pending.is_empty():
		_play.callv(pending.pop_front())
		return
	var c: int = state.turn
	var moves := Rules.legal_moves(state)
	var who: String = seats[c]
	var over: bool = state.phase == "over"
	for pc in panels:
		var panel: PlayerPanel = panels[pc]
		panel.active = pc == c and not over
		panel.home = state.tokens[pc].count(Rules.HOME)
		var place: int = state.winners.find(pc)
		panel.note = PLACES[place] if place != -1 and place < PLACES.size() else ""
	for row in pawns:
		for p in row:
			p.movable = false
	if not over:
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(dice, "position", _dice_spot(c), 0.3)
	dice.waiting = who == "human" and state.phase == "roll"
	if over:
		hint.text = "%s wins!" % names[state.winners[0]]
		if _results == null:
			_show_results()
		return
	if who == "human" and c != _turn_seen:
		Sfx.play("your_turn", 0.0)
	_turn_seen = c
	if who == "remote":
		hint.text = "Waiting for %s..." % names[c]
		panels[c].note = "Playing..."
	elif state.phase == "roll":
		if who == "human":
			hint.text = "%s, tap the dice!" % names[c]
		else:
			hint.text = "%s is thinking..." % names[c]
			panels[c].note = "Thinking..."
			await _pause(0.45)
			_intent("roll", 0)
	elif who == "bot" or _same_square(c, moves):
		await _pause(0.3)
		_intent("move", AI.pick(state) if who == "bot" else moves[0])
	else:
		hint.text = "%s, pick a pawn" % names[c]
		for t in moves:
			pawns[c][t].movable = true


## All legal moves are pawns on the same square, so the choice doesn't matter.
func _same_square(c: int, moves: Array) -> bool:
	var first: int = state.tokens[c][moves[0]]
	return moves.all(func(t): return state.tokens[c][t] == first)


func _pause(sec: float) -> void:
	busy = true
	await get_tree().create_timer(sec).timeout
	busy = false


## Local player or bot wants to act. Host (or offline) decides; clients ask host.
func _intent(kind: String, arg: int) -> void:
	if multiplayer.is_server():
		_host_do(kind, arg, 0)
	else:
		waiting_host = true
		_request.rpc_id(1, kind, arg)


@rpc("any_peer", "reliable")
func _request(kind: String, arg: int) -> void:
	if multiplayer.is_server():
		_host_do(kind, arg, multiplayer.get_remote_sender_id())


## Host validates and broadcasts. sender 0 = local; else must own the seat in turn.
func _host_do(kind: String, arg: int, sender: int) -> void:
	while busy:  # client finished animating before host did
		await get_tree().process_frame
	if sender != 0 and owners[state.turn] != sender:
		return
	if kind == "roll":
		if state.phase != "roll":
			return
		arg = randi_range(1, 6)
	elif not arg in Rules.legal_moves(state):
		return
	if owners.is_empty():
		_play(kind, arg)
	else:
		_play.rpc(kind, arg)


@rpc("authority", "call_local", "reliable")
func _play(kind: String, arg: int) -> void:
	waiting_host = false
	if busy:
		pending.append([kind, arg])
	elif kind == "roll":
		_roll(arg)
	else:
		_move(arg)


func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server():
		return
	for c in 4:
		if owners[c] == id:
			owners[c] = 0
			seats[c] = "bot"
	if not busy:
		_next()


func _on_host_left() -> void:
	busy = true
	hint.text = "Host left the game"


func _on_roll_tap(c: int) -> void:
	if not busy and not waiting_host and c == state.turn and state.phase == "roll" and seats[c] == "human":
		_intent("roll", 0)


func _roll(value: int) -> void:
	busy = true
	var c: int = state.turn
	panels[c].note = ""
	Sfx.play("dice")
	await dice.roll(value)
	Rules.roll(state, value)
	if value == 6:
		sixes[c] += 1
		if state.turn != c:
			_popup("Three 6s!", UI.COLORS[c])
	if state.phase == "roll":  # no legal move (or third six)
		panels[c].note = "No moves"
		hint.text = "No moves!"
		Sfx.play("no_move", 0.0)
		await get_tree().create_timer(0.8).timeout
	busy = false
	_next()


func _move(t: int) -> void:
	busy = true
	var c: int = state.turn
	var ev := Rules.move(state, t)
	if ev.is_empty():
		busy = false
		return
	for p in pawns[c]:
		p.movable = false
	var pawn: Node2D = pawns[c][t]
	pawn.base_scale = 1.0
	pawn.z_index = 5
	if ev.from == -1:
		await pawn.hop_to(_at(c, 0), 0.3, 80.0)
		Sfx.play("hop")
	else:
		for p in range(ev.from + 1, ev.to + 1):
			await pawn.hop_to(_at(c, p))
			Sfx.play("hop")
	pawn.z_index = 0
	if not ev.captured.is_empty():
		Fx.shake(table)
		Sfx.play("capture")
		for cap in ev.captured:
			var victim: Node2D = pawns[cap[0]][cap[1]]
			victim.z_index = 5
			victim.fly_to(_at(cap[0], -1, cap[1]))
		await get_tree().create_timer(0.6).timeout
		for cap in ev.captured:
			pawns[cap[0]][cap[1]].z_index = 0
	if ev.to == Rules.HOME:
		Fx.burst(table, pawn.position, UI.COLORS[c])
		Sfx.play("home", 0.0)
	captures[c] += ev.captured.size()
	if c in state.winners and state.phase != "over":
		_popup("%s: %s!" % [names[c], PLACES[state.winners.find(c)]], UI.COLORS[c], true)
	elif not ev.captured.is_empty():
		_popup("Captured!", UI.COLORS[c])
	elif ev.to == Rules.HOME:
		_popup("Home!", UI.COLORS[c])
	elif state.turn == c and state.phase == "roll":
		_popup("Bonus roll!", UI.COLORS[c])
	_layout()
	busy = false
	_next()


## Big bouncy word over the board ("Captured!", "Bonus roll!").
func _popup(text: String, color: Color, big := false) -> void:
	Fx.popup(hud, text, color, board.position.y, big)


func _show_results() -> void:
	_results = WinOverlay.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():  # left during the pause
		return
	hint.hide()
	dice.hide()
	var ranking: Array = state.winners.duplicate()
	for c in state.colors:
		if not c in ranking:
			ranking.append(c)
	_results.ranking = ranking
	_results.names = names
	_results.avatars = avatars
	_results.me = me
	_results.stats = range(4).map(func(c): return "Captures %d    Sixes %d" % [captures[c], sixes[c]])
	_results.can_restart = owners.is_empty() or multiplayer.is_server()
	_results.play_again.connect(_play_again)
	_results.home.connect(_to_menu)
	hud.add_child(_results)


func _play_again() -> void:
	if owners.is_empty():
		UI.restart()
	else:
		var n := names.duplicate()
		for c in 4:
			if owners[c] == 0:  # players who left are bots now
				n[c] = Games.BOT_NAMES[c]
		var a := avatars.duplicate()
		for c in 4:
			if owners[c] == 0:
				a[c] = {}
		_restart.rpc(owners, n, a)


@rpc("authority", "call_local", "reliable")
func _restart(o: Array, n: Array, a: Array) -> void:
	UI.restart({"owners": o, "names": n, "avatars": a})


func _unhandled_input(e: InputEvent) -> void:
	if busy or waiting_host or not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase != "move" or seats[state.turn] != "human":
		return
	var at := get_global_mouse_position()
	var best := -1
	var best_d := 60.0
	for t in Rules.legal_moves(state):
		var d: float = pawns[state.turn][t].hit_point().distance_to(at)
		if d < best_d:
			best_d = d
			best = t
	if best != -1:
		_intent("move", best)
