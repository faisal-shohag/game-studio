## Dots and Boxes table: the dot grid and a row of player portraits with their scores.
## Drives turns for humans, bots and LAN peers the same way as snakes_game.gd: the host checks
## every line and broadcasts it, and each phone plays it on its own copy of the state.
extends Node2D

const Rules = preload("res://games/dots/dots_rules.gd")
const AI = preload("res://games/dots/dots_ai.gd")
const Board = preload("res://games/dots/dots_board.gd")
const Seat = preload("res://games/shared/seat.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const PLACES := ["1st place", "2nd place", "3rd place", "4th place"]

## Seat type per color: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "bot", "bot", "bot"]
## LAN only: peer id per color, 0 = bot (run by host), -1 = off. Empty = offline.
var owners := []
var names := []
var avatars := []
var me := -1

var state: Dictionary
var busy := false
var waiting_host := false  # client sent an intent, host hasn't answered yet
var pending := []  # lines from host that arrived while animating
var table := Node2D.new()
var board := Board.new()
var hud := Control.new()
var players := {}  # color -> Seat
var hint := Label.new()
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
	board.position = Vector2(540, 1070 + _oy)
	for c in colors:
		var n: String = names[c].trim_prefix("Bot ")
		board.marks[c] = n.left(1).to_upper()
	board.state = state
	table.add_child(board)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var order: Array = colors.duplicate()
	if me in order:  # you first, then the turn order after you
		var k := order.find(me)
		order = order.slice(k) + order.slice(0, k)
	var gap := 1080.0 / (order.size() + (1 if order.size() < 4 else 0))  # leave the corner for the back button
	for i in order.size():
		var c: int = order[i]
		var seat := Seat.new()
		seat.color = UI.COLORS[c]
		seat.variant = c
		seat.player_name = names[c]
		seat.avatar = avatars[c]
		seat.fan_visible = false
		var cx := gap * (i + (1.5 if order.size() < 4 else 0.5))
		seat.position = Vector2(cx - Seat.PORTRAIT / 2, (200 if order.size() == 4 else 60) + _oy)
		hud.add_child(seat)
		players[c] = seat
	hint.position = Vector2(60, 1720 + _oy)
	hint.size = Vector2(960, 80)
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
		seat.badge = str(state.scores[pc])
		seat.note = ""
		if over:
			var place: int = state.places[state.winners.find(pc)]
			seat.note = PLACES[place]
			seat.happy = place == 0
	if over:
		var top: Array = state.winners.filter(func(w): return state.scores[w] == state.scores[state.winners[0]])
		hint.text = "%s wins!" % names[top[0]] if top.size() == 1 else "It's a tie!"
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
		hint.text = "Draw a line!" if seats.count("human") == 1 else "%s, draw a line!" % names[c]
	else:
		hint.text = "%s is thinking..." % names[c]
		players[c].note = "Thinking..."
		await _pause(0.4)
		_intent(AI.pick(state))


func _pause(sec: float) -> void:
	busy = true
	await get_tree().create_timer(sec).timeout
	busy = false


## Local player or bot wants to draw a line. Host (or offline) decides; clients ask host.
func _intent(line: int) -> void:
	if multiplayer.is_server():
		_host_do(line, 0)
	else:
		waiting_host = true
		_request.rpc_id(1, line)


@rpc("any_peer", "reliable")
func _request(line: int) -> void:
	if multiplayer.is_server():
		_host_do(line, multiplayer.get_remote_sender_id())


## Host validates and broadcasts. sender 0 = local; else must own the seat in turn.
func _host_do(line: int, sender: int) -> void:
	while busy:  # client finished animating before host did
		await get_tree().process_frame
	if sender != 0 and owners[state.turn] != sender:
		return
	if not line in Rules.legal(state):
		if sender != 0:
			_rejected.rpc_id(sender)
		return
	if owners.is_empty():
		_play(line)
	else:
		_play.rpc(line)


@rpc("authority", "reliable")
func _rejected() -> void:
	waiting_host = false
	_next()


@rpc("authority", "call_local", "reliable")
func _play(line: int) -> void:
	waiting_host = false
	if busy:
		pending.append([line])
	else:
		_draw_line(line)


func _draw_line(line: int) -> void:
	busy = true
	var c: int = state.turn
	Sfx.play("tap")
	var tw := create_tween()
	tw.tween_method(func(k: float): board.grow = {"line": line, "color": c, "k": k}, 0.0, 1.0, 0.18)
	await tw.finished
	board.grow = {}
	var ev := Rules.draw(state, line)
	board.last = line
	if not ev.is_empty() and not ev.boxes.is_empty():
		Sfx.play("home", 0.0)
		var pop := {}
		for b in ev.boxes:
			pop[b] = 0.0
		var fill := func(k: float) -> void:
			for b in ev.boxes:
				pop[b] = k
			board.pop = pop
		var tw2 := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_method(fill, 0.0, 1.0, 0.35)
		await tw2.finished
		board.pop = {}
		for b in ev.boxes:
			var tl := board.dot_pos(b % Rules.COLS, b / Rules.COLS) + Vector2(Board.GAP, Board.GAP) / 2
			Fx.burst(table, table.to_local(board.to_global(tl)), UI.COLORS[c])
		if state.phase != "over":
			Fx.popup(hud, "+%d  Go again!" % ev.boxes.size(), UI.COLORS[c], board.position.y)
	board.queue_redraw()
	busy = false
	_next()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or not _my_turn():
		return
	var line := board.line_at(board.to_local(get_global_mouse_position()))
	if line != -1:
		get_viewport().set_input_as_handled()
		_intent(line)


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
	hint.text = "Host left the game"


func _show_results() -> void:
	_results = WinOverlay.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():  # left during the pause
		return
	hint.hide()
	_results.ranking = state.winners
	_results.places = state.places
	_results.faces = true
	_results.names = names
	_results.avatars = avatars
	_results.me = me
	_results.stats = range(4).map(func(c): return "Boxes %d" % state.scores[c])
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
