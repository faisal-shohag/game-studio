## Sholo Guti table: the board, both players' portraits, and a Stop button for jump chains.
## Drives turns for humans, bots and LAN peers the same way as snakes_game.gd: the host checks
## every move and broadcasts it, and each phone plays it on its own copy of the state.
extends Node2D

const Rules = preload("res://games/sholo/sholo_rules.gd")
const AI = preload("res://games/sholo/sholo_ai.gd")
const Board = preload("res://games/sholo/sholo_board.gd")
const Seat = preload("res://games/shared/seat.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")

## Seat type per color: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "off", "bot", "off"]
## LAN only: peer id per color, 0 = bot (run by host), -1 = off. Empty = offline.
var owners := []
var names := []
var avatars := []
var me := -1

var state: Dictionary
var busy := false
var waiting_host := false  # client sent an intent, host hasn't answered yet
var pending := []  # moves from host that arrived while animating
var table := Node2D.new()  # shaken on captures
var board := Board.new()
var hud := Control.new()
var players := {}  # color -> Seat
var hint := Label.new()
var stop: Button
var _results: Control
var _turn_seen := -1
var _oy := 0.0


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
	_next()


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	add_child(table)
	board.position = Vector2(540, 965 + _oy)
	var bottom: int = me if me in colors else colors[0]
	board.rotation = PI if bottom == colors[1] else 0.0  # the local player's beads start at the bottom
	board.board = state.board.duplicate()
	table.add_child(board)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	for c in colors:
		var seat := Seat.new()
		seat.color = UI.COLORS[c]
		seat.variant = c
		seat.player_name = names[c]
		seat.avatar = avatars[c]
		seat.fan_visible = false
		seat.position = Vector2(80, 1690 + _oy) if c == bottom else Vector2(540 - Seat.PORTRAIT / 2, 30 + _oy)
		hud.add_child(seat)
		players[c] = seat
	hint.position = Vector2(260, 1720 + _oy)
	hint.size = Vector2(500, 120)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 44)
	hud.add_child(hint)
	stop = UI.button("STOP", UI.ACCENT, Vector2(240, 120), 50)
	stop.position = Vector2(790, 1720 + _oy)
	stop.pressed.connect(_on_stop)
	stop.hide()
	hud.add_child(stop)
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


func _my_turn() -> bool:
	return state.phase != "over" and seats[state.turn] == "human" and not busy and not waiting_host and pending.is_empty()


func _next() -> void:
	if not pending.is_empty():
		_play.callv(pending.pop_front())
		return
	var c: int = state.turn
	var over: bool = state.phase == "over"
	for pc in players:
		var seat: Seat = players[pc]
		seat.active = pc == c and not over
		seat.badge = str(Rules.left(state, pc))
		seat.note = ""
		seat.happy = not over or state.winners.is_empty() or pc in state.winners
	board.selected = -1
	board.targets = []
	board.movable = _movable() if _my_turn() else []
	stop.visible = _my_turn() and state.phase == "chain"
	if over:
		if state.winners.is_empty():
			hint.text = "Draw!"
		else:
			hint.text = "%s wins!" % names[state.winners[0]]
		if _results == null:
			_show_results()
		return
	var who: String = seats[c]
	if who == "human" and c != _turn_seen:
		Sfx.play("your_turn", 0.0)
		if seats.count("human") > 1:
			Fx.popup(hud, "%s's turn" % names[c], UI.COLORS[c], board.position.y)
	_turn_seen = c
	if who == "remote":
		hint.text = "Waiting for %s..." % names[c]
		players[c].note = "Playing..."
	elif who == "human":
		hint.text = "Jump again or stop" if state.phase == "chain" else "Your move!" if seats.count("human") == 1 else "%s's move" % names[c]
	else:
		hint.text = "%s is thinking..." % names[c]
		players[c].note = "Thinking..."
		await _pause(0.5)
		var m := AI.pick(state)
		_intent("done" if m == -1 else "move", m)


## Points of beads that can move (in a chain: just the jumping bead).
func _movable() -> Array:
	var out := []
	for m in Rules.legal_moves(state):
		if not Rules.from_of(m) in out:
			out.append(Rules.from_of(m))
	return out


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
	if not ((kind == "move" and arg in Rules.legal_moves(state)) or (kind == "done" and state.phase == "chain")):
		if sender != 0:
			_rejected.rpc_id(sender)
		return
	if owners.is_empty():
		_play(kind, arg)
	else:
		_play.rpc(kind, arg)


@rpc("authority", "reliable")
func _rejected() -> void:
	waiting_host = false
	_next()


@rpc("authority", "call_local", "reliable")
func _play(kind: String, arg: int) -> void:
	waiting_host = false
	if busy:
		pending.append([kind, arg])
	elif kind == "move":
		_move(arg)
	elif kind == "done":
		Rules.end_chain(state)
		_next()


func _move(m: int) -> void:
	busy = true
	var from := Rules.from_of(m)
	var over := Rules.jumped(m)
	var c: int = state.turn
	board.selected = -1
	board.targets = []
	board.movable = []
	var shown: Array = board.board.duplicate()
	shown[from] = -1
	board.board = shown
	var a := board.point_pos(from)
	var b := board.point_pos(Rules.to_of(m))
	var hop := func(k: float) -> void:
		board.flying = {"color": c, "at": a.lerp(b, k), "scale": 1.0 + sin(k * PI) * (0.35 if over != -1 else 0.15)}
	var tw := create_tween()
	tw.tween_method(hop, 0.0, 1.0, 0.4 if over != -1 else 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	board.flying = {}
	var ev := Rules.move(state, m)
	board.board = state.board.duplicate()
	if ev.is_empty():  # can't happen: the host checked it
		busy = false
		_next()
		return
	Sfx.play("hop")
	if over != -1:
		Sfx.play("capture")
		Fx.shake(table)
		Fx.burst(table, table.to_local(board.to_global(board.point_pos(over))), UI.COLORS[_other(c)])
		if ev.chain and seats[c] == "human":
			_popup("Jump again?", UI.COLORS[c])
	busy = false
	_next()


func _other(c: int) -> int:
	return state.colors[1] if c == state.colors[0] else state.colors[0]


func _on_stop() -> void:
	if _my_turn() and state.phase == "chain":
		stop.hide()
		_intent("done", 0)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or not _my_turn():
		return
	var i := board.point_at(board.to_local(get_global_mouse_position()))
	if i == -1:
		return
	get_viewport().set_input_as_handled()
	if i in board.targets:
		_intent("move", Rules.encode(board.selected, i))
		board.targets = []
		board.movable = []
		return
	if i in _movable() and i != board.selected:
		board.selected = i
		board.targets = Rules.legal_moves(state).filter(func(m): return Rules.from_of(m) == i).map(func(m): return Rules.to_of(m))
		Sfx.play("tap")
	elif state.phase == "chain" and i == state.chain_at:
		_on_stop()  # tapping the jumping bead again stops the chain
	else:
		board.selected = -1
		board.targets = []


func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server():
		return
	for c in 4:
		if owners[c] == id:
			owners[c] = 0
			seats[c] = "bot"
	if not busy and state.phase != "over":
		_next()


func _on_host_left() -> void:
	busy = true
	stop.hide()
	hint.text = "Host left the game"


func _popup(text: String, color: Color) -> void:
	Fx.popup(hud, text, color, board.position.y)


func _show_results() -> void:
	_results = WinOverlay.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():  # left during the pause
		return
	hint.hide()
	stop.hide()
	var ranking: Array = state.winners.duplicate()
	ranking.append_array(state.colors.filter(func(c): return not c in ranking))
	_results.ranking = ranking
	_results.places = [0, 0] if state.winners.is_empty() else [0, 1]
	_results.faces = true
	_results.names = names
	_results.avatars = avatars
	_results.me = me
	_results.stats = range(4).map(func(c): return "Captured %d" % state.captured[c])
	_results.can_restart = owners.is_empty() or multiplayer.is_server()
	_results.play_again.connect(_play_again)
	_results.home.connect(_to_menu)
	hud.add_child(_results)


func _play_again() -> void:
	if owners.is_empty():
		UI.restart()
		return
	var n := names.duplicate()
	var a := avatars.duplicate()
	for c in 4:
		if owners[c] == 0:  # players who left are bots now
			n[c] = Games.BOT_NAMES[c]
			a[c] = {}
	_restart.rpc(owners, n, a)


@rpc("authority", "call_local", "reliable")
func _restart(o: Array, n: Array, a: Array) -> void:
	UI.restart({"owners": o, "names": n, "avatars": a})
