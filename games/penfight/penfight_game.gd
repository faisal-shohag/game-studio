## Pen Fight table: the desk fills the width, opponents' portraits sit above it, yours below with
## the hint beside it. The desk never turns: this phone's player is at the bottom and pass-and-play
## friends flick from their own sides of it.
## Same turn loop as carrom_game.gd: a flick goes through _intent -> _host_do, which runs the rules
## (and the physics) and queues the event; events animate one at a time from the frames the
## physics recorded, then the screen catches up with the state.
##
## Before round 1 everyone picks a pen (bots at random, people on a card overlay). Aiming: touch
## anywhere on your pen (that is where the flick lands) and pull back. The arrow points the other
## way and a ring shows the power; grabbing near an end shows which way the pen will spin. Let go
## to flick, or let go near where you started to cancel.
##
## Real-time: no turns and no playback. The world steps live in _process, each pen flicks whenever
## its cooldown ring has run out, and every finger aims on its own, so pass-and-play friends can
## flick at once (a touch takes the nearest pen of a person on this phone). Bots wait a moment once
## ready, then weigh a few short simulations, one per slice, and flick.
extends Node2D

const Rules = preload("res://games/penfight/pen_rules.gd")
const Physics = preload("res://games/penfight/pen_physics.gd")
const Ai = preload("res://games/penfight/pen_ai.gd")
const Desk = preload("res://games/penfight/penfight_desk.gd")
const PenPick = preload("res://games/penfight/pen_pick.gd")
const Seat = preload("res://games/shared/seat.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const DESK_AT := Vector2(540, 990)
const DESK_SCALE := 0.94
## Opponent portraits (top-left corner) by place round the desk from yours.
const SPOTS := {"right": Vector2(880, 110), "across": Vector2(465, 95), "left": Vector2(215, 110)}
const MY_SPOT := Vector2(30, 1700)
const GRAB := 70.0  # desk units round your pen that still grab it
const CANCEL := 40.0  # screen pull shorter than this: no flick
const FULL_PULL := 340.0  # screen pull for full power
const BOT_THINK := 0.6
const SHOT_CLOCK := 20.0  # seconds a person gets when others are waiting; then a weak flick
const HARD_HIT := 900.0  # a contact this fast shakes the desk
const LIVE_STEP := 1.0 / 30.0  # Real-time: longest slice of time stepped at once
const PULSE_TIME := 0.45  # Real-time: the "ready" pulse
const SETTLE := 0.6  # Real-time: seconds pens keep tipping off after a round is decided

var variant := "turns"
var rounds := 1
## Seat type per seat: "human", "bot", "off". Set before adding to tree.
var seats := ["human", "off", "bot", "off"]
var names := []
var avatars := []
var me := -1

var state: Dictionary  # the whole game, kept by this phone
var view: Dictionary  # what the screen shows: the state as of the last finished animation
var busy := false
var pending := []  # [event, state after it] waiting to be animated
var table := Node2D.new()  # shaken on hard hits
var desk := Desk.new()
var hud := Control.new()
var players := {}  # seat -> Seat
var hint := Label.new()
var status := Label.new()
var _results: Control
var _pick: Control
var _turn_seen := -1
var _oy := 0.0
var _aiming := false
var _press := Vector2.ZERO  # screen point where the aim started
var _grab := 0.0  # -1..1 along the pen
var _pull := Vector2.ZERO
# flick playback
var _ev := {}
var _after := {}
var _frames := []
var _ids := []  # pen id per frame slot
var _types := []
var _clock := 0.0
var _done_events := 0
var _last_clack := -1.0
var _clock_tw: Tween
var _shaken := false
# real-time
var _live := false
var _paused := false  # the leave dialog is open
var _settle := 0.0
var _fingers := {}  # finger index (-1 = mouse) -> {seat, grab, press, pull}
var _bots := {}  # seat -> a bot getting ready to flick: {wake, cands, listed, i, best, score}
var _ready_seen := {}  # seat -> its pen was ready last frame


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
	state = Rules.new_state(variant, rounds, colors)
	for c in colors:
		if seats[c] == "bot":
			Rules.pick(state, c, Physics.TYPES.pick_random())
	view = state.duplicate(true)
	_build(colors)
	set_process(false)
	if view.phase != "pick":  # all bots: straight into round 1
		_round_start()
	_refresh()
	_next()


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	add_child(table)
	desk.position = DESK_AT + Vector2(0, _oy)
	desk.scale = Vector2(DESK_SCALE, DESK_SCALE)
	for c in colors:
		desk.colors[c] = UI.COLORS[c]
	table.add_child(desk)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var n := colors.size()
	var base := colors.find(me) if me != -1 else 0
	for k in n:
		var c: int = colors[k]
		var seat := Seat.new()
		seat.color = UI.COLORS[c]
		seat.variant = c
		seat.player_name = names[c]
		seat.avatar = avatars[c]
		seat.fan_visible = false
		seat.coin = UI.COLORS[c]
		var rel := posmod(k - base, n)
		seat.position = (MY_SPOT if rel == 0 else SPOTS[_side(rel, n)]) + Vector2(0, _oy)
		hud.add_child(seat)
		players[c] = seat
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


## Where a player `rel` places round the desk from you sits: 2 players face each other,
## 3 sit in a triangle, 4 in a square.
static func _side(rel: int, n: int) -> String:
	if n == 2:
		return "across"
	if n == 3:
		return ["", "right", "left"][rel]
	return ["", "right", "across", "left"][rel]


func _to_menu() -> void:
	UI.reset_to("res://ui/screens/home.gd")


func on_back() -> void:
	if view.phase == "over":
		_to_menu()
		return
	_paused = true
	var leave: bool = await UI.confirm("Leave game?", "Your progress will be lost.")
	_paused = false
	if leave:
		_to_menu()


## Redraws everything from `view` (no animation).
func _refresh() -> void:
	desk.pens = view.world.pens.duplicate(true)
	var over: bool = view.phase == "over"
	var need := Rules.needed(view)
	for c in players:
		var seat: Seat = players[c]
		var pen := Rules.pen_of(view, c)
		var out: bool = pen.get("out", false)
		seat.active = c == view.turn and view.phase == "aim"
		seat.pips = [view.round_wins[c], need]
		if over:
			var i: int = view.winners.find(c)
			seat.note = ["1st place", "2nd place", "3rd place", "4th place"][view.places[i]]
			seat.happy = view.places[i] == 0
			seat.modulate.a = 1.0
		else:
			seat.note = "Out" if out else ""
			seat.happy = not out
			seat.modulate.a = 0.55 if out else 1.0
	if view.phase == "pick":
		status.text = ""
	else:
		status.text = "Round %d  ·  %s" % [view.round, "one round" if view.rounds == 1 else "best of %d" % view.rounds]
	_controls()


func _controls() -> void:
	var c: int = view.turn
	match view.phase:
		"over":
			hint.text = "Game over"
		"pick":
			hint.text = "Pick your pens"
		"round_over":
			hint.text = ""
		"live":
			var people := seats.count("human")
			hint.text = "" if people == 0 else "Flick any time!" if people == 1 else "Everyone flick!"
		_:
			if _my_turn():
				hint.text = "Your turn! Pull back from your pen" if seats.count("human") == 1 else "%s's turn!" % names[c]
			elif seats[c] == "human":
				hint.text = ""
			else:
				hint.text = "%s is thinking..." % names[c]


func _my_turn() -> bool:
	return (not view.is_empty() and view.phase == "aim" and seats[view.turn] == "human"
		and not busy and pending.is_empty() and _results == null and _pick == null)


func _next() -> void:
	if not pending.is_empty():
		_animate.callv(pending.pop_front())
		return
	match view.phase:
		"over":
			_refresh()
			if _results == null:
				_show_results()
			return
		"pick":
			_next_pick()
			return
		"round_over":
			_round_break()
			return
		"live":
			_go_live()
			return
	var c: int = view.turn
	var who: String = seats[c]
	_refresh()
	if who == "human" and c != _turn_seen:
		Sfx.play("your_turn", 0.0)
		Input.vibrate_handheld(40)
		if seats.count("human") > 1:
			Fx.popup(hud, "%s's turn" % names[c], UI.COLORS[c], DESK_AT.y + _oy + 160)
	_turn_seen = c
	if who == "bot":
		_bot_turn(c)
	elif _clock_on():
		_start_clock(c)


# --- pen pick -------------------------------------------------------------------

## The next person without a pen picks one on the card overlay.
func _next_pick() -> void:
	var c := -1
	for d in view.colors:
		if not view.pens.has(d):
			c = d
			break
	if c == -1:
		return
	_refresh()
	_pick = PenPick.new()
	_pick.title = "Pick your pen" if seats.count("human") == 1 else "%s, pick your pen" % names[c]
	_pick.color = UI.COLORS[c]
	_pick.chosen = UI.settings.get_value("penfight", "pen", "") if c == me else ""
	_pick.picked.connect(_picked.bind(c))
	hud.add_child(_pick)


func _picked(type: String, c: int) -> void:
	if c == me:
		UI.settings.set_value("penfight", "pen", type)
		UI.settings.save(UI.SETTINGS_PATH)
	_pick.queue_free()
	_pick = null
	if not Rules.pick(state, c, type):
		return
	view = state.duplicate(true)
	if view.phase != "pick":
		_round_start()
	_next()


## Pens drop onto the desk with a "Round N" stamp.
func _round_start() -> void:
	_refresh()
	Sfx.play("hop", 0.1)
	Fx.popup(hud, "Round %d" % view.round if view.rounds > 1 else "Fight!", UI.COLORS[2], DESK_AT.y + _oy - 120, true)
	_turn_seen = -1


## Between rounds: put the pens back and go again.
func _round_break() -> void:
	busy = true
	_refresh()
	await get_tree().create_timer(1.6).timeout
	if not is_inside_tree():
		return
	Rules.next_round(state)
	view = state.duplicate(true)
	busy = false
	_round_start()
	_next()


# --- turns ----------------------------------------------------------------------

## The shot clock runs only when other people are waiting (pass and play), not vs bots.
func _clock_on() -> bool:
	return seats.count("human") > 1


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


## Time's up: a weak straight flick toward the middle of the desk.
func _time_up(c: int) -> void:
	_stop_clock()
	if not _my_turn() or view.turn != c:
		return
	_aiming = false
	desk.aim = {}
	var pen := Rules.pen_of(view, c)
	_popup("Time's up!", UI.COLORS[0])
	_intent({"grab": 0.0, "angle": (Rules.CENTER - Vector2(pen.x, pen.y)).angle(), "power": 0.25}, c)


## A bot weighs its flicks a few at a time (so the screen stays smooth), shows its aim for a
## moment, then flicks.
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
	var f := Ai.noisy(best)
	players[c].note = ""
	var pen := Rules.pen_of(view, c)
	desk.aim = _aim_view(pen, f.grab, Vector2.from_angle(f.angle), f.power)
	await get_tree().create_timer(0.5).timeout
	desk.aim = {}
	busy = false
	if is_inside_tree() and state.turn == c and state.phase == "aim":
		_intent(f, c)


## The local player or a bot flicks. This phone keeps the state and decides.
func _intent(f: Dictionary, c: int) -> void:
	_stop_clock()
	_host_do(f, c)


func _host_do(f: Dictionary, c: int) -> void:
	var ev := Rules.flick(state, c, f)
	if ev.is_empty():
		_controls()
		return
	_show(ev, state.duplicate(true))


func _show(ev: Dictionary, after: Dictionary) -> void:
	pending.append([ev, after])
	if not busy:
		_next()


# --- input ----------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if variant == "realtime":
		_live_input(e)
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var at := get_global_mouse_position()
		if e.pressed:
			if not _my_turn():
				return
			var g := _grab_at(Rules.pen_of(view, view.turn), desk.to_desk(at))
			if is_nan(g):
				return
			_aiming = true
			_grab = g
			_press = at
			_pull = Vector2.ZERO
			get_viewport().set_input_as_handled()
		elif _aiming:
			get_viewport().set_input_as_handled()
			_aiming = false
			_release()
	elif e is InputEventMouseMotion and _aiming:
		get_viewport().set_input_as_handled()
		_pull = get_global_mouse_position() - _press
		_update_aim()


## Where along the pen (-1..1) a touch at desk point p grabs it, or NAN when it misses.
static func _grab_at(pen: Dictionary, p: Vector2) -> float:
	var ends := Physics.ends(pen)
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	if p.distance_to(a.lerp(b, t)) > Physics.spec(pen.type).radius + GRAB:
		return NAN
	return t * 2.0 - 1.0


## The flick for the current pull, or {} when the pull is too short.
func _pulled() -> Dictionary:
	if _pull.length() < CANCEL:
		return {}
	var power := clampf((_pull.length() - CANCEL) / (FULL_PULL - CANCEL), Rules.MIN_POWER, 1.0)
	return {"grab": _grab, "angle": (-_pull).angle(), "power": power}


func _update_aim() -> void:
	var f := _pulled()
	desk.aim = {} if f.is_empty() else _aim_view(Rules.pen_of(view, view.turn), f.grab, Vector2.from_angle(f.angle), f.power)


## What the desk draws for a flick: the grab point, the arrow, the power and the spin it gives.
static func _aim_view(pen: Dictionary, grab: float, dir: Vector2, power: float) -> Dictionary:
	var axis := Vector2.from_angle(pen.angle)
	var center := Vector2(pen.x, pen.y)
	var arm: Vector2 = axis * grab * Physics.spec(pen.type).length / 2.0
	return {"grab": center + arm, "center": center, "dir": dir, "power": power, "spin": clampf(axis.cross(dir) * grab * 1.5, -1.0, 1.0)}


func _release() -> void:
	var f := _pulled()
	desk.aim = {}
	if f.is_empty():
		return
	_intent(f, view.turn)


# --- flick playback -------------------------------------------------------------

func _animate(ev: Dictionary, after: Dictionary) -> void:
	busy = true
	_stop_clock()
	_controls()
	_ev = ev
	_after = after
	_frames = ev.sim.frames
	_ids = view.world.pens.map(func(p): return p.id)
	_types = view.world.pens.map(func(p): return p.type)
	_clock = 0.0
	_last_clack = -1.0
	_done_events = 0
	_shaken = false
	for c in players:
		players[c].active = c == ev.seat
	Sfx.play("hop", 0.1, -6.0)
	set_process(true)


func _process(delta: float) -> void:
	if _live or _settle > 0.0:
		_live_tick(delta)
		return
	_clock += delta
	var fi := mini(int(_clock * 60.0), _frames.size() - 1)
	var f: PackedFloat32Array = _frames[fi]
	var pens := []
	for i in _ids.size():
		pens.append({"id": _ids[i], "type": _types[i], "x": f[i * 4], "y": f[i * 4 + 1], "angle": f[i * 4 + 2], "fall": f[i * 4 + 3]})
	desk.pens = pens
	var events: Array = _ev.sim.events
	while _done_events < events.size() and events[_done_events].t <= fi:
		_play_event(events[_done_events])
		_done_events += 1
	if fi >= _frames.size() - 1 and _done_events >= events.size():
		set_process(false)
		_shot_over()


func _play_event(e: Dictionary) -> void:
	match e.type:
		"hit":
			if _clock - _last_clack < 0.04:
				return
			_last_clack = _clock
			var loud := clampf(e.speed / 1200.0, 0.0, 1.0)
			if e.speed > HARD_HIT and not _shaken:
				_shaken = true
				Fx.shake(table, lerpf(6.0, 16.0, clampf((e.speed - HARD_HIT) / 1200.0, 0.0, 1.0)))
				Input.vibrate_handheld(25)
			Sfx.play("hop", 0.12, lerpf(-22.0, 0.0, loud))
		"edge":
			Sfx.play("hop", 0.05, -10.0)
		"out":
			var pen := _pen_in_frame(e.id)
			var at := desk.to_screen(Vector2(clampf(pen.x, 0.0, Physics.W), clampf(pen.y, 0.0, Physics.H)))
			Sfx.play("capture")
			Fx.burst(table, at, UI.COLORS[e.id])
			_popup("Out!", UI.COLORS[e.id])


func _pen_in_frame(id: int) -> Dictionary:
	for p in desk.pens:
		if p.id == id:
			return p
	return {"x": Physics.W / 2, "y": Physics.H / 2}


## Frames played: say who knocked whom, then catch up with the state.
func _shot_over() -> void:
	var ev := _ev
	var c: int = ev.seat
	view = _after
	_refresh()
	var wait := 0.25
	if not ev.knocks.is_empty():
		_knock_popups(ev.knocks)
		wait = 0.9
	if c in ev.self_outs:
		Sfx.play("no_move", 0.0)
		_popup("Oops!", UI.COLORS[0])
		wait = 0.9
	if ev.round_winner != -1:
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree():
			return
		_round_won(ev.round_winner)
		wait = 1.2
	await get_tree().create_timer(wait).timeout
	if not is_inside_tree():
		return
	for k in players:
		players[k].chip = ""
	busy = false
	_next()


## "Max knocked off Zoe & Leo!", one popup per knocker.
func _knock_popups(knocks: Array) -> void:
	var by := {}  # knocker -> names knocked off
	for k in knocks:
		if not by.has(k[0]):
			by[k[0]] = []
		by[k[0]].append(names[k[1]])
	for b in by:
		_popup("%s knocked off %s!" % [names[b], " & ".join(by[b])], UI.COLORS[b], true)


## The round's stamp: "Round 1: Zoe wins!".
func _round_won(w: int) -> void:
	Sfx.play("home", 0.0)
	var text := "%s wins!" % names[w] if view.rounds == 1 else "Round %d: %s wins!" % [view.round, names[w]]
	Fx.popup(hud, text, UI.COLORS[w], DESK_AT.y + _oy, true)
	Fx.burst(hud, players[w].position + Vector2(75, 75), UI.COLORS[w])
	players[w].chip = "Round won!" if view.rounds > 1 else ""


func _popup(text: String, color: Color, big := false) -> void:
	Fx.popup(hud, text, color, DESK_AT.y + _oy - 260, big)


# --- real-time ------------------------------------------------------------------

## A round starts: a moment to see the desk, then everyone goes.
func _go_live() -> void:
	if _live or busy:
		return
	busy = true
	_refresh()
	await get_tree().create_timer(0.7).timeout
	if not is_inside_tree():
		return
	busy = false
	_bots = {}
	_ready_seen = {}
	_clock = 0.0
	_last_clack = -1.0
	_live = true
	set_process(true)


## Steps the round by delta (in slices, so bots and events keep up when the frame was long),
## then redraws the pens, their cooldown rings and the aims.
func _live_tick(delta: float) -> void:
	if _paused:
		return
	if not _live:  # the round is decided: let the last pens finish tipping off
		Physics.step(state.world, delta)
		desk.pens = state.world.pens
		_settle -= delta
		if _settle <= 0.0:
			set_process(false)
			_live_over()
		return
	var left := delta
	while left > 0.0 and _live:
		var dt := minf(left, LIVE_STEP)
		left -= dt
		_clock += dt
		_bots_tick()
		var ev := Rules.live_step(state, dt)
		for e in ev.events:
			_play_event(e)
		if not ev.out.is_empty():
			_live_outs(ev)
		if ev.round_winner != -1:
			_live = false
			_settle = SETTLE
			_fingers = {}
			desk.aims = {}
			desk.cooldowns = {}
	view = state  # offline this phone is the host: the screen follows the live state
	desk.pens = state.world.pens
	for c in state.colors:
		var is_ready := Rules.ready(state, c)
		desk.cooldowns[c] = clampf((state.ready_at[c] - state.time) / Rules.COOLDOWN, 0.0, 1.0) if _live else 0.0
		if is_ready and not _ready_seen.get(c, true):
			desk.pulses[c] = 0.0
			if seats[c] == "human":
				Input.vibrate_handheld(15)
		_ready_seen[c] = is_ready
	for c in desk.pulses.keys():
		desk.pulses[c] += delta / PULSE_TIME
		if desk.pulses[c] >= 1.0:
			desk.pulses.erase(c)
	for i in _fingers:
		_update_finger(i)


func _live_outs(ev: Dictionary) -> void:
	_refresh()
	_knock_popups(ev.knocks)
	for c in ev.self_outs:
		Sfx.play("no_move", 0.0)
		_popup("Oops!", UI.COLORS[c])
	for i in _fingers.keys():  # a finger on a pen that just went over lets go
		if Rules.pen_of(state, _fingers[i].seat).out:
			_fingers.erase(i)
			desk.aims.erase(i)


## The last pens have dropped: stamp the round, then on to the next one (or the results).
func _live_over() -> void:
	busy = true
	view = state.duplicate(true)
	_refresh()
	_round_won(view.round_winner)
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	for k in players:
		players[k].chip = ""
	busy = false
	_next()


## Bots on cooldown wait; once ready they wait a human-ish moment, then weigh one candidate flick
## per slice and flick the best.
func _bots_tick() -> void:
	for c in state.colors:
		if seats[c] != "bot" or not Rules.ready(state, c):
			_bots.erase(c)
			continue
		if not _bots.has(c):
			_bots[c] = {"wake": state.time + randf_range(Ai.REACTION[0], Ai.REACTION[1]), "cands": [], "listed": false, "i": 0, "best": {}, "score": -INF}
			continue
		var job: Dictionary = _bots[c]
		if state.time < job.wake:
			continue
		if not job.listed:
			job.cands = Ai.quick_candidates(state, c)
			job.listed = true
		if job.i < job.cands.size():
			var sc := Ai.quick_eval(state, c, job.cands[job.i])
			if sc > job.score:
				job.score = sc
				job.best = job.cands[job.i]
			job.i += 1
			continue
		_bots.erase(c)
		if not Rules.live_flick(state, c, Ai.noisy(job.best)).is_empty():
			_flicked(c)


func _flicked(c: int) -> void:
	Sfx.play("hop", 0.1, -6.0)
	desk.pulses.erase(c)
	_ready_seen[c] = false


## Real-time input: every finger (and a real mouse) aims on its own.
func _live_input(e: InputEvent) -> void:
	if not _live or _paused or _results != null:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_finger_down(e.index, e.position)
		else:
			_finger_up(e.index)
	elif e is InputEventScreenDrag:
		_finger_move(e.index, e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.pressed:
			_finger_down(-1, get_global_mouse_position())
		else:
			_finger_up(-1)
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		_finger_move(-1, get_global_mouse_position())


## A touch takes the nearest pen (of someone on this phone, not already held) within reach.
func _finger_down(i: int, at: Vector2) -> void:
	var p := desk.to_desk(at)
	var held := _fingers.values().map(func(f): return f.seat)
	var best := -1
	var best_d := INF
	var grab := 0.0
	for c in state.colors:
		if seats[c] != "human" or c in held:
			continue
		var pen := Rules.pen_of(state, c)
		if pen.out:
			continue
		var g := _grab_at(pen, p)
		if is_nan(g):
			continue
		var d := p.distance_to(Vector2(pen.x, pen.y))
		if d < best_d:
			best_d = d
			best = c
			grab = g
	if best == -1:
		return
	_fingers[i] = {"seat": best, "grab": grab, "press": at, "pull": Vector2.ZERO}
	get_viewport().set_input_as_handled()


func _finger_move(i: int, at: Vector2) -> void:
	if not _fingers.has(i):
		return
	_fingers[i].pull = at - _fingers[i].press
	_update_finger(i)
	get_viewport().set_input_as_handled()


## Redraws a finger's aim on its pen (which may be moving).
func _update_finger(i: int) -> void:
	var f := _finger_flick(_fingers[i])
	if f.is_empty():
		desk.aims.erase(i)
	else:
		desk.aims[i] = _aim_view(Rules.pen_of(state, _fingers[i].seat), f.grab, Vector2.from_angle(f.angle), f.power)
	desk.queue_redraw()


func _finger_up(i: int) -> void:
	if not _fingers.has(i):
		return
	var finger: Dictionary = _fingers[i]
	_fingers.erase(i)
	desk.aims.erase(i)
	get_viewport().set_input_as_handled()
	var f := _finger_flick(finger)
	if f.is_empty():
		return
	if Rules.live_flick(state, finger.seat, f).is_empty():
		Sfx.play("no_move", 0.0)  # still cooling down
	else:
		_flicked(finger.seat)


static func _finger_flick(finger: Dictionary) -> Dictionary:
	var pull: Vector2 = finger.pull
	if pull.length() < CANCEL:
		return {}
	var power := clampf((pull.length() - CANCEL) / (FULL_PULL - CANCEL), Rules.MIN_POWER, 1.0)
	return {"grab": finger.grab, "angle": (-pull).angle(), "power": power}


# --- results --------------------------------------------------------------------

func _show_results() -> void:
	_stop_clock()
	_results = WinOverlay.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	hint.hide()
	status.hide()
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
