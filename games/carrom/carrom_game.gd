## Carrom table: the board fills the width, opponents' portraits sit above it, your striker
## slider and portrait below. The board never turns during a game: it is drawn with this phone's
## player at the bottom, and pass-and-play friends shoot from their own sides of it.
## Same turn loop as cards_game.gd: a shot goes through _intent -> _host_do, which runs the rules
## (and the physics) and queues the event; events animate one at a time from the frames the
## physics recorded, then the screen catches up with the state.
##
## Over LAN the host decides every shot. A guest sends only {x, angle, power}; the host checks it,
## shoots and sends everyone the shot and the state after it (no frames). Each phone replays the
## shot with its own physics for the animation, then snaps to the host's state: floats may differ
## slightly between phones, the host's result is the truth.
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
const SHOT_CLOCK := 20.0  # seconds a person gets when others are waiting; then a weak shot
const TRAIL := 10  # striker trail length, frames
const HARD_HIT := 1500.0  # a contact this fast shakes the table

var variant := "classic"
## Seat type per seat: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "off", "bot", "off"]
## LAN only: peer id per seat, 0 = bot (run by host), -1 = off. Empty = offline.
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
var _synced := []  # host: peers whose table is ready for events
var _clock_tw: Tween
var _shaken := false  # this shot already shook the table


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
	var start := Rules.new_state(variant, colors)
	view = start.duplicate(true)  # a guest's stand-in until the host's state arrives
	_base = me if me != -1 else colors[0]
	_build(colors)
	_turn_board(_base)
	set_process(false)
	if multiplayer.is_server():
		state = start
		_refresh()
		_next()
	else:
		waiting_host = true
		_refresh()
		hint.text = "Joining the table..."
		_hello.rpc_id(1)  # the host may have started already; it answers with the current state


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
		var man := Rules.man_of(view, c)
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
	elif await UI.confirm("Leave game?", "Your progress will be lost." if owners.is_empty() else "You will leave the room."):
		_to_menu()


## Puts seat `base` at the bottom of the screen (fixed for the game) and the others round it.
func _turn_board(base: int) -> void:
	_base = base
	board.rotation = base * PI / 2
	for c in players:
		var rel := posmod(c - base, 4)
		players[c].position = (MY_SPOT if rel == 0 else SPOTS[rel]) + Vector2(0, _oy)


## Redraws everything from `view` (no animation).
func _refresh() -> void:
	board.pieces = view.pieces.duplicate(true)
	board.sinking = {}
	var over: bool = view.phase == "over"
	for c in players:
		var seat: Seat = players[c]
		seat.active = c == view.turn and not over
		if c != view.turn or over:
			seat.chip = ""
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
	elif seats[c] == "remote" and owners[c] != 0:
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
			Fx.popup(hud, "%s's turn" % names[c], UI.COLORS[c], BOARD_AT.y + _oy + 160)  # below any shot popup
	_turn_seen = c
	if who == "bot":
		_bot_turn(c)
	elif _clock_on() and (who == "human" or owners[c] != 0):
		_start_clock(c)


## The shot clock runs only when other people are waiting (pass and play, LAN), not vs bots.
func _clock_on() -> bool:
	var people := 0
	for c in 4:
		if seats[c] == "human" or (seats[c] == "remote" and owners[c] != 0):
			people += 1
	return people > 1


## A ring round the shooter's portrait runs down; on this phone's own seat, time up shoots weakly.
## Every phone shows the ring; only the shooter's phone acts on it.
func _start_clock(c: int) -> void:
	_stop_clock()
	var seat: Seat = players[c]
	_clock_tw = create_tween()
	_clock_tw.tween_method(func(v: float): seat.clock = v, 1.0, 0.0, SHOT_CLOCK)
	_clock_tw.tween_callback(_time_up.bind(c))


func _stop_clock() -> void:
	if _clock_tw:
		_clock_tw.kill()
		_clock_tw = null
	for c in players:
		players[c].clock = -1.0


func _time_up(c: int) -> void:
	_stop_clock()
	if not _my_turn() or view.turn != c:
		return
	_dragging = ""
	board.aim = {}
	var x := _x if Rules.can_place(view, c, _x) else _free_x(view, c, _x)
	_popup("Time's up!", UI.COLORS[0])
	_spot[c] = x
	_intent({"x": x, "angle": 0.0, "power": 0.25}, c)


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


## The local player or a bot shoots. The host (or an offline phone) decides; guests ask the host.
func _intent(shot: Dictionary, c: int) -> void:
	_stop_clock()
	if multiplayer.is_server():
		_host_do(shot, c, 0)
	else:
		waiting_host = true
		_controls()
		_request.rpc_id(1, shot)


@rpc("any_peer", "reliable")
func _request(shot: Dictionary) -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		_host_do(shot, owners.find(sender), sender)


## Host runs the shot. sender 0 = this phone; else that peer must own seat c.
func _host_do(shot: Dictionary, c: int, sender: int) -> void:
	if c == -1 or (sender != 0 and owners[c] != sender):
		return
	var ev := Rules.shoot(state, c, shot)
	if ev.is_empty():
		if sender != 0:
			_rejected.rpc_id(sender)
		return
	var after := state.duplicate(true)
	var light := ev.duplicate()
	light.erase("sim")  # guests replay the shot themselves
	for peer in _synced:
		_show.rpc_id(peer, light, after)
	_show(ev, after)


## A guest's table is ready: send it the game as it stands.
@rpc("any_peer", "reliable")
func _hello() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and owners.has(peer) and not peer in _synced:
		_synced.append(peer)
		_sync_state.rpc_id(peer, state)


@rpc("authority", "reliable")
func _sync_state(s: Dictionary) -> void:
	view = s
	waiting_host = false
	if not busy:
		_next()


## The host turned our shot down (the turn moved on, ...): let the player try again.
@rpc("authority", "reliable")
func _rejected() -> void:
	waiting_host = false
	if not busy:
		_controls()


@rpc("authority", "reliable")
func _show(ev: Dictionary, after: Dictionary) -> void:
	waiting_host = false
	pending.append([ev, after])
	if not busy:
		_next()


func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server():
		return
	_synced.erase(id)
	for c in 4:
		if owners[c] == id:
			owners[c] = 0
			seats[c] = "bot"
	if not busy and pending.is_empty() and view.phase != "over":
		_next()


func _on_host_left() -> void:
	_stop_clock()
	busy = true
	set_process(false)
	hint.text = "Host left the game"
	slider.hide()


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
	_place_striker(view.turn, lerpf(Rules.BASE_MIN, Rules.BASE_MAX, t if _slider_forward() else 1.0 - t))
	slider.queue_redraw()
	_controls()


## Whether the slider runs the same way as the shooter's baseline looks on screen: left to right
## for the bottom and top sides, top to bottom for the left and right ones. The board doesn't
## turn for pass-and-play friends, so a friend across the table slides "backwards" in their frame.
func _slider_forward() -> bool:
	var a := board.to_screen(Rules.striker_at(view.turn, Rules.BASE_MIN))
	var b := board.to_screen(Rules.striker_at(view.turn, Rules.BASE_MAX))
	return b.x > a.x if absf(b.x - a.x) > absf(b.y - a.y) else b.y > a.y


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
	if not _slider_forward():
		t = 1.0 - t
	var x := 70 + t * (slider.size.x - 140)
	slider.draw_circle(Vector2(x, 45), 46, UI.INK)
	Board.draw_piece(slider, Vector2(x, 45), Physics.STRIKER, 0.0, 1.45, 1.0, not _aim_ok)


# --- shot playback ------------------------------------------------------------

func _animate(ev: Dictionary, after: Dictionary) -> void:
	busy = true
	_controls()
	if not ev.has("sim"):  # from the host: replay it here, slide the striker over first
		var tw := create_tween()
		tw.tween_method(func(x: float): _place_striker(ev.seat, x), _spot.get(ev.seat, 500.0), ev.shot.x, 0.3).set_trans(Tween.TRANS_SINE)
		await tw.finished
		if not is_inside_tree():
			return
		ev.sim = Physics.simulate(view.pieces, Rules.launch(ev.seat, ev.shot))
	_spot[ev.seat] = ev.shot.x
	_stop_clock()
	players[ev.seat].chip = ""
	board.trail = []
	board.bulge = {}
	_shaken = false
	_ev = ev
	_frames = ev.sim.frames
	_ids = view.pieces.map(func(p): return p.id) + [-1]
	_kinds = view.pieces.map(func(p): return p.kind) + [Physics.STRIKER]
	_clock = 0.0
	_done_events = 0
	_after = after
	board.spin = {}
	board.sinking = {}
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
		board.spin[id] = board.spin.get(id, 0.0) + moved / Physics.COIN_R * 0.8 * (1 if id % 2 == 0 else -1)
	var s := (n - 1) * 2
	var striker_sink: float = board.sinking.get(-1, 0.0)
	board.striker = {} if striker_sink >= 1.0 else {"x": f[s], "y": f[s + 1]}
	var step := Vector2(f[s] - prev[s], f[s + 1] - prev[s + 1]).length()
	board.striker_spin += step / Physics.STRIKER_R * 0.6
	if not board.striker.is_empty() and step > 6.0:  # flying: leave a trail
		board.trail.append(Vector2(f[s], f[s + 1]))
	elif not board.trail.is_empty():
		board.trail.pop_front()
	while board.trail.size() > TRAIL:
		board.trail.pop_front()
	for k in board.bulge.keys():
		board.bulge[k] += delta * 60.0 / 24.0
		if board.bulge[k] >= 1.0:
			board.bulge.erase(k)
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
			if e.type == "hit" and e.speed > HARD_HIT and not _shaken:  # a power shot lands
				_shaken = true
				Fx.shake(table, lerpf(8.0, 20.0, clampf((e.speed - HARD_HIT) / 1500.0, 0.0, 1.0)))
				Input.vibrate_handheld(25)
			Sfx.play("hop", 0.12, lerpf(-22.0, 0.0, loud) - (6.0 if e.type == "cushion" else 0.0))
		"pocket":
			board.sinking[e.id] = 0.01
			board.bulge[e.pocket] = 0.0
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
	if ev.foul != "" and ev.points < 0:
		players[c].note = "%d" % ev.points
	view = _after
	board.trail = []
	_refresh()
	if ev.again and view.phase != "over":
		players[c].chip = "Shoot again!"
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
	_stop_clock()
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
	UI.restart({"owners": o, "names": n, "avatars": a})  # the variant carries over
