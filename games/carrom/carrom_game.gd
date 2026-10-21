## Carrom table: the board fills the width, opponents' portraits sit above it, your striker
## slider and portrait below. The board turns so the local shooter is always at the bottom.
## Same turn loop as cards_game.gd: a shot goes through _intent -> _host_do, which runs the rules
## (and the physics) and queues the event; events animate one at a time from the frames the
## physics recorded, then the screen catches up with the state.
##
## Aiming: drag the slider to place the striker on your baseline, then touch the striker and pull
## back. The guide points the other way, up to the first coin (with a ghost striker where it would
## touch) or one cushion bounce; the ring round the striker shows the power. Let go to shoot, or
## let go back on the striker to cancel.
extends Node2D

const Rules = preload("res://games/carrom/carrom_rules.gd")
const Physics = preload("res://games/carrom/carrom_physics.gd")
const Ai = preload("res://games/carrom/carrom_ai.gd")
const Board = preload("res://games/carrom/carrom_board.gd")
const Seat = preload("res://games/shared/seat.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const BOARD_AT := Vector2(540, 1000)
## Opponent portraits (top-left corner) by side relative to the bottom one: right, across, left.
const SPOTS := {1: Vector2(870, 250), 2: Vector2(465, 210), 3: Vector2(60, 250)}
const MY_SPOT := Vector2(30, 1700)
const SLIDER_Y := 1625.0
const SLIDER_X := [130.0, 950.0]  # thumb travel on screen
const GRAB := 95.0  # how close to the striker a touch starts aiming
const CANCEL := 45.0  # let go this close to the striker: no shot
const FULL_PULL := 330.0  # pull for full power
const BOT_THINK := 0.6
const SINK_FRAMES := 14.0
const GUIDE := 520.0  # guide length past the first cushion

var variant := "classic"
## Seat type per seat: "human", "bot", "off" (or "remote" on another phone, later).
var seats := ["human", "off", "bot", "off"]
## LAN only (Phase 4): peer id per seat. Empty = offline.
var owners := []
var names := []
var avatars := []
var me := -1

var state: Dictionary  # the whole game, kept by the host (offline: this phone)
var view: Dictionary  # what the screen shows: the state as of the last finished animation
var busy := false
var waiting_host := false
var pending := []  # [event, state after it] waiting to be animated
var table := Node2D.new()  # shaken on hard shots
var board := Board.new()
var hud := Control.new()
var players := {}  # seat -> Seat
var slider := Control.new()
var hint := Label.new()
var status := Label.new()
var _results: Control
var _base := 0  # seat shown at the bottom
var _turn_seen := -1
var _oy := 0.0
var _spot := {}  # seat -> striker x it last used
var _x := 500.0  # striker spot while aiming
var _dragging := ""  # "" | slider | aim
var _pull := Vector2.ZERO
var _aim_ok := false
# shot playback
var _ev := {}
var _after := {}  # the state once the shot being played has landed
var _frames := []
var _ids := []  # piece id per frame slot; -1 = the striker
var _kinds := []
var _clock := 0.0
var _done_events := 0
var _last_clack := -1.0
var _rot_tw: Tween


func _ready() -> void:
	var colors := []
	for c in 4:
		if seats[c] != "off":
			colors.append(c)
	if me == -1:
		me = seats.find("human")
	if names.is_empty():
		for c in 4:
			names.append(UI.player_name if c == me else Games.BOT_NAMES[c] if seats[c] == "bot" else "Player %d" % (c + 1))
	if avatars.is_empty():  # offline: only you have one; bots and pass-and-play friends get the default
		avatars = [{}, {}, {}, {}]
		if me != -1:
			avatars[me] = UI.avatar
	state = Rules.new_state(variant, colors)
	view = state.duplicate(true)
	_base = me if me != -1 else colors[0]
	_build(colors)
	_turn_board(_base, false)
	set_process(false)
	_refresh()
	_next()


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	add_child(table)
	board.position = BOARD_AT + Vector2(0, _oy)
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
		var man := Rules.man_of(state, c)
		seat.coin = null if man == -1 else Board.KIND_COLORS[man]
		hud.add_child(seat)
		players[c] = seat
	slider.position = Vector2(SLIDER_X[0] - 70, SLIDER_Y + _oy - 45)
	slider.size = Vector2(SLIDER_X[1] - SLIDER_X[0] + 140, 90)
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slider.draw.connect(_draw_slider)
	hud.add_child(slider)
	hint.position = Vector2(200, 1715 + _oy)
	hint.size = Vector2(860, 70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 46)
	hud.add_child(hint)
	status.position = Vector2(200, 1790 + _oy)
	status.size = Vector2(860, 56)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 34)
	status.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hud.add_child(status)
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
	if view.phase == "over":
		_to_menu()
	elif await UI.confirm("Leave game?", "Your progress will be lost."):
		_to_menu()


## Puts seat `base` at the bottom (turning the board) and the others round the table.
func _turn_board(base: int, animate := true) -> void:
	_base = base
	var target := base * PI / 2
	var from := board.rotation
	target = from + wrapf(target - from, -PI, PI)  # the short way round
	if _rot_tw:
		_rot_tw.kill()
		_rot_tw = null
	if animate:
		_rot_tw = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_rot_tw.tween_property(board, "rotation", target, 0.55)
	else:
		board.rotation = target
	for c in players:
		var rel := posmod(c - base, 4)
		var at: Vector2 = (MY_SPOT if rel == 0 else SPOTS[rel]) + Vector2(0, _oy)
		if _rot_tw:
			_rot_tw.tween_property(players[c], "position", at, 0.55)
		else:
			players[c].position = at


## Redraws everything from `view` (no animation).
func _refresh() -> void:
	board.pieces = view.pieces.duplicate(true)
	board.sinking = {}
	var over: bool = view.phase == "over"
	for c in players:
		var seat: Seat = players[c]
		seat.active = c == view.turn and not over
		if variant == "classic":  # men of their color already pocketed (partners share them)
			seat.badge = str(Rules.MEN - _left(view, Rules.man_of(view, c)))
		else:
			seat.badge = str(view.scores[c])
		if over:
			var i: int = view.winners.find(c)
			seat.note = ["1st place", "2nd place", "3rd place", ""][view.places[i]] if i != -1 else ""
			seat.happy = i != -1 and view.places[i] == 0
	var q: String = view.queen
	if q == "on_board":
		status.text = "Queen on the board" + ("  (50)" if variant == "freestyle" else "")
	elif q.begins_with("pending"):
		status.text = "%s must cover the queen!" % names[int(q.get_slice(":", 1))]
	else:
		status.text = "Queen covered by %s" % names[int(q.get_slice(":", 1))]
	_controls()


func _left(s: Dictionary, kind: int) -> int:
	return s.pieces.filter(func(p): return p.kind == kind).size()


## Striker, slider and hint for whoever is looking at the phone.
func _controls() -> void:
	var mine := _my_turn()
	slider.visible = mine
	slider.queue_redraw()
	var c: int = view.turn
	if view.phase == "over":
		hint.text = "Game over"
		board.striker = {}
		return
	if not busy:
		_place_striker(c, _x if mine else _spot.get(c, 500.0))
	if mine:
		var who := "Your turn!" if seats.count("human") == 1 else "%s's turn!" % names[c]
		if view.variant == "classic":
			who += "  Pocket %s" % ("white" if Rules.man_of(view, c) == Rules.WHITE else "black")
		hint.text = who if _aim_ok else "Move the striker off the coin"
	elif seats[c] == "human":
		hint.text = ""
	elif seats[c] == "remote":
		hint.text = "Waiting for %s..." % names[c]
	else:
		hint.text = "%s is thinking..." % names[c]


func _place_striker(c: int, x: float) -> void:
	_x = x
	var at := Rules.striker_at(c, x)
	board.striker = {"x": at.x, "y": at.y}
	_aim_ok = Rules.can_place(view, c, x)
	board.striker_bad = not _aim_ok and _my_turn()


func _my_turn() -> bool:
	return (not view.is_empty() and view.phase != "over" and seats[view.turn] == "human"
		and not busy and not waiting_host and pending.is_empty() and _results == null)


func _next() -> void:
	if not pending.is_empty():
		_animate.callv(pending.pop_front())
		return
	var c: int = view.turn
	if view.phase == "over":
		_refresh()
		if _results == null:
			_show_results()
		return
	var who: String = seats[c]
	if who == "human" and seats.count("human") > 1 and c != _base:
		_turn_board(c)  # pass and play: the board turns to whoever shoots
	if who == "human":
		var x: float = _spot.get(c, 500.0)
		if not Rules.can_place(view, c, x):
			x = _free_x(view, c, x)
		_x = x
	_refresh()
	if who == "human" and c != _turn_seen:
		Sfx.play("your_turn", 0.0)
		Input.vibrate_handheld(40)
		if seats.count("human") > 1:
			_popup("%s's turn" % names[c], UI.COLORS[c])
	_turn_seen = c
	if who == "bot":
		_bot_turn(c)


## Nearest striker spot to x that isn't on a coin.
static func _free_x(s: Dictionary, c: int, x: float) -> float:
	for k in 80:
		for sx in [x + k * 8.0, x - k * 8.0]:
			if Rules.can_place(s, c, sx):
				return sx
	return x


## A bot weighs its shots a few at a time (so the screen stays smooth), slides the striker to its
## spot, shows its aim for a moment, then shoots.
func _bot_turn(c: int) -> void:
	busy = true
	players[c].note = "Thinking..."
	var started := Time.get_ticks_msec()
	var best := {}
	var best_score := -INF
	var snapshot := state.duplicate(true)
	var cands := Ai.candidates(snapshot, c)
	for i in cands.size():
		var sc := Ai.evaluate(snapshot, c, cands[i])
		if sc > best_score:
			best_score = sc
			best = cands[i]
		if i % 4 == 3:
			await get_tree().process_frame
			if not is_inside_tree():
				return
	var left := BOT_THINK - (Time.get_ticks_msec() - started) / 1000.0 * Engine.time_scale
	if left > 0:
		await get_tree().create_timer(left).timeout
	var shot := Ai.noisy(snapshot, c, best)
	players[c].note = ""
	# slide over, aim, shoot
	var tw := create_tween()
	tw.tween_method(func(x: float): _place_striker(c, x), _x, shot.x, 0.35).set_trans(Tween.TRANS_SINE)
	await tw.finished
	if not is_inside_tree():
		return
	var at := Rules.striker_at(c, shot.x)
	board.aim = _guide(view, at, Rules.shot_dir(c, shot.angle), shot.power)
	await get_tree().create_timer(0.45).timeout
	board.aim = {}
	busy = false
	if is_inside_tree() and state.turn == c and state.phase != "over":
		_spot[c] = shot.x
		_intent(shot, c)


## The local player or a bot shoots. The host (or an offline phone) decides.
func _intent(shot: Dictionary, c: int) -> void:
	_host_do(shot, c, 0)


func _host_do(shot: Dictionary, c: int, sender: int) -> void:
	if c == -1 or (sender != 0 and owners[c] != sender):
		return
	var ev := Rules.shoot(state, c, shot)
	if ev.is_empty():
		return
	_show(ev, state.duplicate(true))


func _show(ev: Dictionary, after: Dictionary) -> void:
	waiting_host = false
	pending.append([ev, after])
	if not busy:
		_next()


# --- input --------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var at := get_global_mouse_position()
		if e.pressed:
			if not _my_turn():
				return
			var striker_at := board.to_screen(Vector2(board.striker.x, board.striker.y))
			if at.distance_to(striker_at) < GRAB:
				_dragging = "aim"
				_pull = Vector2.ZERO
			elif absf(at.y - (SLIDER_Y + _oy)) < 80:
				_dragging = "slider"
				_slide_to(at.x)
			if _dragging != "":
				get_viewport().set_input_as_handled()
		elif _dragging != "":
			get_viewport().set_input_as_handled()
			var was := _dragging
			_dragging = ""
			if was == "aim":
				_release()
	elif e is InputEventMouseMotion and _dragging != "":
		get_viewport().set_input_as_handled()
		var at := get_global_mouse_position()
		if _dragging == "slider":
			_slide_to(at.x)
		else:
			_pull = at - board.to_screen(Vector2(board.striker.x, board.striker.y))
			_update_aim()


func _slide_to(screen_x: float) -> void:
	var t := clampf((screen_x - SLIDER_X[0]) / (SLIDER_X[1] - SLIDER_X[0]), 0.0, 1.0)
	_place_striker(view.turn, lerpf(Rules.BASE_MIN, Rules.BASE_MAX, t))
	slider.queue_redraw()
	_controls()


## Shot for the current pull: {x, angle, power}, or {} when the pull is too short.
func _pulled_shot() -> Dictionary:
	if _pull.length() < CANCEL:
		return {}
	var s := board.to_screen(Vector2(board.striker.x, board.striker.y))
	var dir := board.to_board(s - _pull) - board.to_board(s)
	var power := clampf((_pull.length() - CANCEL) / (FULL_PULL - CANCEL), Rules.MIN_POWER, 1.0)
	return {"x": _x, "angle": Rules.angle_of(view.turn, dir.normalized()), "power": power}


func _update_aim() -> void:
	var shot := _pulled_shot()
	if shot.is_empty():
		board.aim = {}
		return
	var at := Rules.striker_at(view.turn, _x)
	board.aim = _guide(view, at, Rules.shot_dir(view.turn, shot.angle), shot.power)


func _release() -> void:
	var shot := _pulled_shot()
	board.aim = {}
	if shot.is_empty():
		return
	if not _aim_ok:
		Sfx.play("no_move", 0.0)
		_popup("Move the striker!", UI.COLORS[0])
		return
	_spot[view.turn] = _x
	_intent(shot, view.turn)


## The aim guide from board point `from` along `dir`: straight to the first coin it would touch
## (a ghost striker drawn there, and a short line where the coin would go) or to a cushion and
## one bounce on.
static func _guide(s: Dictionary, from: Vector2, dir: Vector2, power: float) -> Dictionary:
	var path := [from]
	var at := from
	var d := dir
	var g := {"power": power, "path": path}
	for leg in 2:
		var hit := _first_coin(s.pieces, at, d)
		var wall := _wall_distance(at, d)
		if hit[0] < wall:
			var ghost: Vector2 = at + d * hit[0]
			path.append(ghost)
			g.ghost = ghost
			var coin: Vector2 = hit[1]
			g.push = [coin, coin + (coin - ghost).normalized() * 110]
			return g
		var end := at + d * (wall if leg == 0 else minf(wall, GUIDE))
		path.append(end)
		if leg == 0:  # bounce: flip the component that hit the wall
			var r := Physics.STRIKER_R
			if end.x <= r + 0.5 or end.x >= Physics.SIZE - r - 0.5:
				d.x = -d.x
			if end.y <= r + 0.5 or end.y >= Physics.SIZE - r - 0.5:
				d.y = -d.y
			at = end
	return g


## [distance along d, coin center] of the first coin a striker from `at` moving along `d` touches.
static func _first_coin(pieces: Array, at: Vector2, d: Vector2) -> Array:
	var best := [INF, Vector2.ZERO]
	var reach := Physics.STRIKER_R + Physics.COIN_R
	for p in pieces:
		var q := Vector2(p.x, p.y)
		var t := (q - at).dot(d)
		if t <= 0:
			continue
		var off2 := (at + d * t).distance_squared_to(q)
		if off2 > reach * reach:
			continue
		var back := sqrt(reach * reach - off2)
		if t - back < best[0] and t - back > 0:
			best = [t - back, q]
	return best


static func _wall_distance(at: Vector2, d: Vector2) -> float:
	var r := Physics.STRIKER_R
	var best := INF
	if d.x > 0.0001:
		best = minf(best, (Physics.SIZE - r - at.x) / d.x)
	elif d.x < -0.0001:
		best = minf(best, (r - at.x) / d.x)
	if d.y > 0.0001:
		best = minf(best, (Physics.SIZE - r - at.y) / d.y)
	elif d.y < -0.0001:
		best = minf(best, (r - at.y) / d.y)
	return maxf(best, 0.0)


func _draw_slider() -> void:
	var r := Rect2(Vector2(20, 22), Vector2(slider.size.x - 40, 46))
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0, 0, 0, 0.3)
	pill.set_corner_radius_all(23)
	pill.anti_aliasing = true
	slider.draw_style_box(pill, r)
	for k in 9:  # tick marks
		var tx := 70 + k * (slider.size.x - 140) / 8.0
		slider.draw_line(Vector2(tx, 36), Vector2(tx, 54), Color(1, 1, 1, 0.2), 3)
	var t := inverse_lerp(Rules.BASE_MIN, Rules.BASE_MAX, _x)
	var x := 70 + t * (slider.size.x - 140)
	slider.draw_circle(Vector2(x, 45), 46, UI.INK)
	Board.draw_piece(slider, Vector2(x, 45), Physics.STRIKER, 0.0, 1.45, 1.0, not _aim_ok)


# --- shot playback ------------------------------------------------------------

func _animate(ev: Dictionary, after: Dictionary) -> void:
	busy = true
	_controls()
	_ev = ev
	_frames = ev.sim.frames
	_ids = view.pieces.map(func(p): return p.id) + [-1]
	_kinds = view.pieces.map(func(p): return p.kind) + [Physics.STRIKER]
	_clock = 0.0
	_done_events = 0
	_after = after
	board.spin = {}
	board.sinking = {}
	if ev.shot.power > 0.85:
		Fx.shake(table)
	Sfx.play("hop", 0.1, -4.0)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	var fi := mini(int(_clock * 60.0), _frames.size() - 1)
	var f: PackedFloat32Array = _frames[fi]
	var prev: PackedFloat32Array = _frames[maxi(fi - 1, 0)]
	var pieces := []
	var n := _ids.size()
	for i in n - 1:
		var id: int = _ids[i]
		var sink: float = board.sinking.get(id, 0.0)
		if sink >= 1.0:
			continue
		pieces.append({"id": id, "kind": _kinds[i], "x": f[i * 2], "y": f[i * 2 + 1]})
		var moved := Vector2(f[i * 2] - prev[i * 2], f[i * 2 + 1] - prev[i * 2 + 1]).length()
		board.spin[id] = board.spin.get(id, 0.0) + moved / Physics.COIN_R * 0.35 * (1 if id % 2 == 0 else -1)
	var s := (n - 1) * 2
	var striker_sink: float = board.sinking.get(-1, 0.0)
	board.striker = {} if striker_sink >= 1.0 else {"x": f[s], "y": f[s + 1]}
	board.striker_spin += Vector2(f[s] - prev[s], f[s + 1] - prev[s + 1]).length() / Physics.STRIKER_R * 0.3
	for id in board.sinking:
		board.sinking[id] = minf(1.0, board.sinking[id] + delta * 60.0 / SINK_FRAMES)
	board.pieces = pieces
	var events: Array = _ev.sim.events
	while _done_events < events.size() and events[_done_events].t <= fi:
		_play_event(events[_done_events])
		_done_events += 1
	if fi >= _frames.size() - 1 and _done_events >= events.size() and board.sinking.values().all(func(v): return v >= 1.0):
		set_process(false)
		_shot_over()


func _play_event(e: Dictionary) -> void:
	match e.type:
		"hit", "cushion":
			if _clock - _last_clack < 0.035:
				return  # the break: one clack at a time is plenty
			_last_clack = _clock
			var loud := clampf(e.speed / 1800.0, 0.0, 1.0)
			Sfx.play("hop", 0.12, lerpf(-22.0, 0.0, loud) - (6.0 if e.type == "cushion" else 0.0))
		"pocket":
			board.sinking[e.id] = 0.01
			var at := board.to_screen(Physics.POCKETS[e.pocket])
			if e.id == -1:
				Sfx.play("no_move", 0.0)
				return
			var kind := Rules.kind_of(e.id)
			Sfx.play("capture")
			Fx.burst(table, at, Board.KIND_COLORS[kind] if kind != Physics.BLACK else Color("6b5a52"))
			if kind == Physics.QUEEN:
				Sfx.play("home", 0.0)
				_popup("Queen!", Board.QUEEN_RED)


## Frames played: say what happened, bring returned coins back, then catch up with the state.
func _shot_over() -> void:
	var ev := _ev
	var c: int = ev.seat
	board.striker = {}
	if ev.foul != "":
		Sfx.play("no_move", 0.0)
		Fx.shake(table)
		_popup("Foul!" if ev.foul == "striker" else "Foul! Last man", UI.COLORS[0], true)
	elif ev.queen == "covered":
		Sfx.play("home", 0.0)
		_popup("Covered!", Board.QUEEN_RED, true)
	elif ev.queen == "returned":
		_popup("Queen back!", Board.QUEEN_RED)
	elif ev.points > 0:
		_popup("+%d" % ev.points, UI.COLORS[c])
	elif ev.again:
		_popup("Shoot again!", UI.COLORS[1])
	if ev.foul != "" and ev.points < 0:
		players[c].note = "%d" % ev.points
	view = _after
	_refresh()
	if not ev.returned.is_empty():  # coins put back pop up in the middle
		await get_tree().create_timer(0.25).timeout
		Sfx.play("hop", 0.0)
	await get_tree().create_timer(0.55 if ev.foul != "" or ev.queen != "" else 0.25).timeout
	if not is_inside_tree():
		return
	players[c].note = ""
	busy = false
	_next()


func _popup(text: String, color: Color, big := false) -> void:
	Fx.popup(hud, text, color, BOARD_AT.y + _oy - 120, big)


# --- results ------------------------------------------------------------------

func _show_results() -> void:
	_results = WinOverlay.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	hint.hide()
	status.hide()
	slider.hide()
	_results.ranking = view.winners
	_results.places = view.places
	_results.faces = true
	_results.names = names
	_results.avatars = avatars
	_results.me = me
	var lines := ["", "", "", ""]
	for c in view.colors:
		lines[c] = Rules.stats(view, c)
	_results.stats = lines
	_results.play_again.connect(UI.restart)
	_results.home.connect(_to_menu)
	hud.add_child(_results)
