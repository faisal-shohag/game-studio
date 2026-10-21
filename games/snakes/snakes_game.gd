## Snakes & Ladders table: board, one pawn per player, player cards and dice.
## Drives turns for humans, bots and LAN peers the same way as ludo_game.gd (host decides every roll).
extends Node2D

const Rules = preload("res://games/snakes/snakes_rules.gd")
const Board = preload("res://games/snakes/snakes_board.gd")
const Pawn = preload("res://games/shared/pawn.gd")
const PlayerPanel = preload("res://games/shared/player_panel.gd")
const Dice = preload("res://games/shared/dice.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const PLACES := ["1st place", "2nd place", "3rd place"]
const PANEL_SIZE := Vector2(400, 190)
const PAWN_SCALE := 1.3  # Ludo-sized pins look tiny on 102 px squares
const WAIT_SPOT := Vector2(355, 165)  # waiting pawn's foot on its player card, card coords

## Seat type per color: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "bot", "bot", "bot"]
## LAN only: peer id per color, 0 = bot (run by host), -1 = off. Empty = offline.
var owners := []
## Display name per color; filled in when empty.
var names := []
## Local player's color; their card sits bottom-left. -1 = first human seat.
var me := -1

var state: Dictionary
var busy := false
var waiting_host := false  # client sent an intent, host hasn't answered yet
var pending := []  # actions from host that arrived while animating
var table := Node2D.new()  # board + pawns; shaken on snakes
var board := Board.new()
var pawn_layer := Node2D.new()
var pawns := []  # one per color
var panels := {}  # color -> PlayerPanel
var dice := Dice.new()
var hint := Label.new()
var hud := Control.new()  # cards, dice, hint, back button
var ladders := [0, 0, 0, 0]  # per color, for the results screen
var snakes := [0, 0, 0, 0]
var _results: Control
var _turn_seen := -1  # last color we played the "your turn" sound for
var _turns := 0  # quarter turns that put the local player's card bottom-left
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
	table.add_child(board)
	pawn_layer.y_sort_enabled = true
	table.add_child(pawn_layer)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	for c in 4:
		var p := Pawn.new()
		p.color = UI.COLORS[c]
		p.scale = Vector2.ONE * PAWN_SCALE
		p.visible = c in colors
		pawn_layer.add_child(p)
		pawns.append(p)
	for c in colors:
		var v := _corner_of(c)
		var panel := PlayerPanel.new()
		panel.color = UI.COLORS[c]
		panel.player_name = names[c]
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
	var back := UI.button("", UI.INK.lightened(0.3), Vector2(120, 120))
	var arrow := UI.icon("back", Color.WHITE, 100)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.offset_bottom = -10
	back.add_child(arrow)
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


## Screen corner (0 TL, 1 TR, 2 BR, 3 BL) of color c's card.
func _corner_of(c: int) -> int:
	return (c + _turns) % 4


func _dice_spot(c: int) -> Vector2:
	return Vector2(455, (_top_y if _corner_of(c) < 2 else _bottom_y) + 10)


## Table position of color c's pawn on square n (0 = waiting on its player card).
func _at(c: int, n: int) -> Vector2:
	return panels[c].position + WAIT_SPOT if n == 0 else board.position + board.square_pos(n)


## Snap every pawn to its square; pawns sharing a square shrink and fan out.
func _layout() -> void:
	var groups := {}
	for c in state.colors:
		groups.get_or_add(state.pos[c] if state.pos[c] > 0 else -1 - c, []).append(c)
	for key in groups:
		var g: Array = groups[key]
		for k in g.size():
			var at := _at(g[k], state.pos[g[k]])
			pawns[g[k]].position = at if g.size() == 1 else at + Vector2(24, 0).rotated(TAU * k / g.size())
			pawns[g[k]].base_scale = 1.0 if g.size() == 1 else 0.72
			pawns[g[k]].z_index = 1 if state.pos[g[k]] == 0 else 0  # waiting pawns stand over their card


func _next() -> void:
	if not pending.is_empty():
		_play.callv(pending.pop_front())
		return
	var c: int = state.turn
	var who: String = seats[c]
	var over: bool = state.phase == "over"
	for pc in panels:
		var panel: PlayerPanel = panels[pc]
		panel.active = pc == c and not over
		var pos: int = state.pos[pc]
		panel.status = "Needs a 6" if pos == 0 else "Finished!" if pos == Rules.FINISH else "Square %d" % pos
		var place: int = state.winners.find(pc)
		panel.note = PLACES[place] if place != -1 and place < PLACES.size() else ""
	if not over:
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(dice, "position", _dice_spot(c), 0.3)
	dice.waiting = who == "human" and not over
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
	elif who == "human":
		hint.text = "%s, tap the dice!" % names[c]
	else:
		hint.text = "%s is thinking..." % names[c]
		panels[c].note = "Thinking..."
		await _pause(0.45)
		_intent("roll", 0)


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
func _host_do(kind: String, _arg: int, sender: int) -> void:
	while busy:  # client finished animating before host did
		await get_tree().process_frame
	if sender != 0 and owners[state.turn] != sender:
		return
	if kind != "roll" or state.phase != "roll":
		return
	var value := randi_range(1, 6)
	if owners.is_empty():
		_play(kind, value)
	else:
		_play.rpc(kind, value)


@rpc("authority", "call_local", "reliable")
func _play(kind: String, arg: int) -> void:
	waiting_host = false
	if busy:
		pending.append([kind, arg])
	elif kind == "roll":
		_roll(arg)


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
	var ev := Rules.roll(state, value)
	if ev.is_empty():
		busy = false
		return
	var pawn: Node2D = pawns[c]
	pawn.base_scale = 1.0
	pawn.z_index = 5
	match ev.kind:
		"forfeit", "wait", "stay":
			panels[c].note = {"forfeit": "Three 6s!", "wait": "Needs a 6", "stay": "Too high!"}[ev.kind]
			_popup({"forfeit": "Three 6s!", "wait": "Need a 6!", "stay": "Too high!"}[ev.kind], UI.COLORS[c])
			Sfx.play("no_move", 0.0)
			await get_tree().create_timer(0.8).timeout
		"start":
			await pawn.hop_to(_at(c, 1), 0.45, 120.0)
			Sfx.play("hop")
		_:
			for n in range(ev.from + 1, ev.walk_to + 1):
				await pawn.hop_to(_at(c, n))
				Sfx.play("hop")
	if ev.kind == "ladder":
		ladders[c] += 1
		await get_tree().create_timer(0.15).timeout
		Sfx.play("home", 0.0)
		await _climb(pawn, _at(c, ev.to), UI.COLORS[c])
		Fx.burst(table, pawn.position, UI.COLORS[c])
	elif ev.kind == "snake":
		snakes[c] += 1
		await get_tree().create_timer(0.15).timeout
		Sfx.play("capture")
		Fx.shake(table)
		await _slide(pawn, ev.walk_to)
	pawn.z_index = 0
	if ev.to == Rules.FINISH:
		Fx.burst(table, pawn.position, UI.COLORS[c])
		Sfx.play("home", 0.0)
		if state.phase != "over":
			_popup("%s: %s!" % [names[c], PLACES[state.winners.find(c)]], UI.COLORS[c], true)
	elif ev.kind == "ladder":
		_popup("Ladder!", UI.COLORS[c])
	elif ev.kind == "snake":
		_popup("Snake!", UI.COLORS[c])
	elif state.turn == c and state.phase == "roll" and value == 6:
		_popup("Bonus roll!", UI.COLORS[c])
	_layout()
	busy = false
	_next()


## Ladder climb / snake slide: straight glide with a small lift.
## Ladder: climbs rung by rung (little bounces) with a sparkle trail, squashes on arrival.
func _climb(pawn: Node2D, to: Vector2, color: Color) -> void:
	var from := pawn.position
	var steps := maxi(3, int(from.distance_to(to) / 60.0))
	var trail := _sparkles(color)
	var step := func(k: float) -> void:
		pawn.position = from.lerp(to, k)
		pawn.lift = -absf(sin(k * steps * PI)) * 14.0
		trail.position = pawn.position
	var tw := pawn.create_tween()
	tw.tween_method(step, 0.0, 1.0, 0.18 * steps)
	await tw.finished
	pawn.lift = 0.0
	trail.emitting = false
	get_tree().create_timer(1.0).timeout.connect(trail.queue_free)
	pawn.squash = 1.0
	pawn.create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).tween_property(pawn, "squash", 0.0, 0.5)


## Snake: slides down the snake's body from head to tail at an even speed, wobbling a little.
func _slide(pawn: Node2D, head: int) -> void:
	var pts := board.snake_path(head)
	var dist := PackedFloat32Array([0.0])  # arc length at each point
	for i in range(1, pts.size()):
		dist.append(dist[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := dist[dist.size() - 1]
	var step := func(k: float) -> void:
		var d := k * total
		var i := clampi(dist.bsearch(d), 1, pts.size() - 1)
		var seg := dist[i] - dist[i - 1]
		pawn.position = board.position + pts[i - 1].lerp(pts[i], (d - dist[i - 1]) / seg if seg > 0.0 else 1.0)
		pawn.spin = sin(k * TAU * 3.0) * 0.25 * (1.0 - k)
	var tw := pawn.create_tween()
	tw.tween_method(step, 0.0, 1.0, clampf(total / 650.0, 0.7, 1.5)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	pawn.spin = 0.0


## Little star sparkles that trail a climbing pawn; caller moves it and frees it.
func _sparkles(color: Color) -> CPUParticles2D:
	var fx := CPUParticles2D.new()
	fx.z_index = 6
	fx.amount = 24
	fx.lifetime = 0.6
	fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 22.0
	fx.direction = Vector2.DOWN
	fx.spread = 60.0
	fx.initial_velocity_min = 30.0
	fx.initial_velocity_max = 90.0
	fx.gravity = Vector2(0, 120)
	fx.scale_amount_min = 4.0
	fx.scale_amount_max = 8.0
	var ramp := Gradient.new()
	ramp.set_color(0, UI.COLORS[2].lightened(0.4))
	ramp.set_color(1, Color(color.lightened(0.3), 0.0))
	fx.color_ramp = ramp
	table.add_child(fx)
	fx.emitting = true
	return fx


## Big bouncy word over the board ("Ladder!", "Bonus roll!").
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
	var rest: Array = state.colors.filter(func(c): return not c in ranking)
	rest.sort_custom(func(a, b): return state.pos[a] > state.pos[b])  # closest to 100 places higher
	ranking.append_array(rest)
	_results.ranking = ranking
	_results.names = names
	_results.me = me
	_results.stats = range(4).map(func(c): return "Ladders %d    Snakes %d" % [ladders[c], snakes[c]])
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
		_restart.rpc(owners, n)


@rpc("authority", "call_local", "reliable")
func _restart(o: Array, n: Array) -> void:
	UI.restart({"owners": o, "names": n})
