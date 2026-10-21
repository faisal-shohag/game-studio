## Pure Pen Fight rules. No nodes, no UI, no network: state is a plain Dictionary, like
## carrom_rules.gd. Nothing is hidden, so every phone may hold the whole state.
##
## 2-4 players, each for themselves, each with their own pen (pen id = seat). Everyone picks a pen
## type, then rounds are played: knock the other pens off the desk, the last pen on it wins the
## round. A match is 1 round or best of 3 (first to 2 round wins).
##
## Turns: players flick in turn order, skipping pens that are out. A flick is given in desk
## coordinates (the desk never turns): {grab: -1..1 along the pen, angle: radians, power: 0..1}.
## Real-time: no turns; a pen may be flicked whenever its cooldown is over. The host advances the
## world with live_step().
##
## If the last pens all go over in the same shot, the one that went over last wins the round; on
## the same frame the shooter loses the tie (Real-time: the pen flicked most recently).
## Knock-offs go to the owner of the last pen that knocked into the fallen pen; a pen that went
## over on its own counts as a self-out.

const Physics = preload("res://games/penfight/pen_physics.gd")
const COOLDOWN := 1.2  # Real-time: seconds between a pen's flicks
const MIN_POWER := 0.05
const RING := {2: 280.0, 3: 300.0, 4: 320.0}  # start: pen distance from the desk center
const CENTER := Vector2(Physics.W / 2, Physics.H / 2)


static func new_state(mode: String, rounds: int, colors: Array) -> Dictionary:
	var s := {
		"mode": mode,  # turns | realtime
		"rounds": rounds,  # 1 | 3
		"colors": colors.duplicate(),
		"pens": {},  # seat -> pen type
		"world": {"pens": [], "steps": 0, "acc": 0.0},
		"turn": colors[0],
		"round": 0,
		"round_wins": {},
		"out_order": [],  # this round: seats whose pens went over, in order
		"round_winner": -1,
		"phase": "pick",  # pick | aim | live | round_over | over
		"winners": [],  # final ranking once over
		"places": [],
		"stats": {},  # seat -> {flicks, knocks, self_outs, best: most knock-offs in one flick}
		"time": 0.0,  # Real-time: round clock
		"ready_at": {},  # Real-time: seat -> round time its pen may flick again
		"flicked_at": {},  # Real-time: seat -> round time of its last flick
		"flicks": 0,
	}
	for c in colors:
		s.round_wins[c] = 0
		s.stats[c] = {"flicks": 0, "knocks": 0, "self_outs": 0, "best": 0}
	return s


static func needed(s: Dictionary) -> int:
	return ceili(s.rounds / 2.0)


## Seat c picks a pen type. Once everyone has, the first round starts.
static func pick(s: Dictionary, c: int, type) -> bool:
	if s.phase != "pick" or not c in s.colors or not (type is String) or not type in Physics.TYPES:
		return false
	s.pens[c] = type
	if s.pens.size() == s.colors.size():
		start_round(s)
	return true


## Pens round the middle of the desk, each lying across its spoke: you at the bottom, the others
## going round (2: facing each other, 3: a triangle, 4: a square). Each round starts with the next
## player.
static func start_round(s: Dictionary) -> void:
	s.round += 1
	s.out_order = []
	s.round_winner = -1
	s.time = 0.0
	var n: int = s.colors.size()
	var pens := []
	for k in n:
		var c: int = s.colors[k]
		var spoke := PI / 2 - k * TAU / n  # 0 = down (bottom of the screen), then right, top, left
		var at: Vector2 = CENTER + Vector2.from_angle(spoke) * RING[n]
		pens.append(Physics.new_pen(c, s.pens[c], at, spoke + PI / 2))
		s.ready_at[c] = 0.0
		s.flicked_at[c] = -1.0
	s.world = {"pens": pens, "steps": 0, "acc": 0.0}
	s.turn = s.colors[(s.round - 1) % n]
	s.phase = "aim" if s.mode == "turns" else "live"


static func pen_of(s: Dictionary, c: int) -> Dictionary:
	for pen in s.world.pens:
		if pen.id == c:
			return pen
	return {}


static func on_desk(s: Dictionary) -> Array:
	return s.colors.filter(func(c): return not pen_of(s, c).get("out", true))


## Whether a flick from an untrusted source is well formed and seat c's pen can take it.
static func valid_flick(s: Dictionary, c: int, f) -> bool:
	if not c in s.colors or typeof(f) != TYPE_DICTIONARY:
		return false
	for k in ["grab", "angle", "power"]:
		var v: Variant = f.get(k)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
		if is_nan(float(v)) or is_inf(float(v)):
			return false
	if not (f.power >= MIN_POWER and f.power <= 1.0) or absf(f.grab) > 1.0 or absf(f.angle) > TAU:
		return false
	return not pen_of(s, c).get("out", true)


static func _clean(c: int, f: Dictionary) -> Dictionary:
	return {"id": c, "grab": float(f.grab), "angle": float(f.angle), "power": float(f.power)}


## Turns: seat c flicks. Returns {} when illegal, else an event:
##   {seat, flick, sim (Physics.simulate result), out: seats that went over, knocks: [[by, seat]],
##    self_outs: seats, round_winner: seat or -1, over}
static func flick(s: Dictionary, c: int, f) -> Dictionary:
	if s.phase != "aim" or c != s.turn or not valid_flick(s, c, f):
		return {}
	var fl := _clean(c, f)
	var sim := Physics.simulate(s.world, [fl])
	var ev := apply_result(s, c, sim)
	fl.erase("id")
	ev.flick = fl
	ev.sim = sim
	return ev


## Applies a finished simulation of seat c's flick; returns the event (without flick and sim).
## Bots use it on copies to score candidate flicks.
static func apply_result(s: Dictionary, c: int, sim: Dictionary) -> Dictionary:
	s.world = sim.final.duplicate(true)
	s.flicks += 1
	s.stats[c].flicks += 1
	var ev := _outs(s, sim.fallen, sim.hit_by)
	ev.seat = c
	ev.round_winner = _round_end(s, sim.fallen, sim.fall_step, c)
	if ev.round_winner == -1:
		s.turn = next_of(s, c)
	ev.over = s.phase == "over"
	return ev


## Records the pens that went over; returns {out, knocks, self_outs}.
static func _outs(s: Dictionary, fell: Array, hit_by: Dictionary) -> Dictionary:
	var ev := {"out": fell.duplicate(), "knocks": [], "self_outs": []}
	var streak := {}  # knocker -> pens it knocked off this time
	for id in fell:
		s.out_order.append(id)
		var by: int = hit_by.get(id, -1)
		if by != -1 and by != id and by in s.colors:
			s.stats[by].knocks += 1
			ev.knocks.append([by, id])
			streak[by] = streak.get(by, 0) + 1
		else:
			s.stats[id].self_outs += 1
			ev.self_outs.append(id)
	for by in streak:
		s.stats[by].best = maxi(s.stats[by].best, streak[by])
	return ev


## Ends the round when one pen (or none) is left. `when`: seat -> when it went over; `loser`
## loses a tie on the same frame. Returns the round winner or -1.
static func _round_end(s: Dictionary, fell: Array, when: Dictionary, loser: int) -> int:
	var left := on_desk(s)
	var w := -1
	if left.size() == 1:
		w = left[0]
	elif left.is_empty() and not fell.is_empty():
		var last := -1
		for id in fell:
			last = maxi(last, when[id])
		var tied: Array = fell.filter(func(id): return when[id] == last)
		if tied.size() > 1:
			tied.erase(loser)
			var n: int = s.colors.size()
			var k0: int = s.colors.find(loser)
			tied.sort_custom(func(a, b): return posmod(s.colors.find(a) - k0, n) < posmod(s.colors.find(b) - k0, n))
		w = tied[0]
	if w == -1:
		return -1
	s.round_winner = w
	s.out_order.erase(w)
	s.round_wins[w] += 1
	if s.round_wins[w] >= needed(s):
		_finish(s, w)
	else:
		s.phase = "round_over"
	return w


static func _finish(s: Dictionary, w: int) -> void:
	var finish := [w]  # this round, best first: the winner, then the last pens to go over
	for k in range(s.out_order.size() - 1, -1, -1):
		finish.append(s.out_order[k])
	for c in s.colors:
		if not c in finish:
			finish.append(c)
	var order: Array = s.colors.duplicate()
	order.sort_custom(func(a, b): return s.round_wins[a] > s.round_wins[b] or (s.round_wins[a] == s.round_wins[b] and finish.find(a) < finish.find(b)))
	s.winners = order
	s.places = range(order.size())
	s.phase = "over"


## After a round's end: on to the next round.
static func next_round(s: Dictionary) -> bool:
	if s.phase != "round_over":
		return false
	start_round(s)
	return true


## The next seat after c whose pen is still on the desk.
static func next_of(s: Dictionary, c: int) -> int:
	var n: int = s.colors.size()
	var k: int = s.colors.find(c)
	for step in range(1, n + 1):
		var d: int = s.colors[(k + step) % n]
		if not pen_of(s, d).get("out", true):
			return d
	return c


## Real-time: whether seat c's pen is ready to flick.
static func ready(s: Dictionary, c: int) -> bool:
	return s.phase == "live" and c in s.colors and s.time >= s.ready_at[c] and not pen_of(s, c).get("out", true)


## Real-time: seat c flicks its pen now. Returns {} when illegal, else {seat, flick}.
static func live_flick(s: Dictionary, c: int, f) -> Dictionary:
	if not valid_flick(s, c, f) or not ready(s, c):
		return {}
	var fl := _clean(c, f)
	Physics.flick(pen_of(s, c), fl.grab, fl.angle, fl.power)
	s.ready_at[c] = s.time + COOLDOWN
	s.flicked_at[c] = s.time
	s.flicks += 1
	s.stats[c].flicks += 1
	fl.erase("id")
	return {"seat": c, "flick": fl}


## Real-time: advances the round by dt. Returns {events (physics), out, knocks, self_outs,
## round_winner, over}.
static func live_step(s: Dictionary, dt: float) -> Dictionary:
	if s.phase != "live":
		return {}
	s.time += dt
	var events := Physics.step(s.world, dt)
	var fell := []
	var when := {}
	var hit_by := {}
	for e in events:
		if e.type == "edge":
			fell.append(e.id)
			when[e.id] = e.t
			hit_by[e.id] = pen_of(s, e.id).hit_by
	var ev := _outs(s, fell, hit_by)
	ev.events = events
	var loser := -1
	for id in fell:  # the pen flicked most recently loses a tie
		if loser == -1 or s.flicked_at[id] > s.flicked_at[loser]:
			loser = id
	ev.round_winner = _round_end(s, fell, when, loser) if not fell.is_empty() else -1
	ev.over = s.phase == "over"
	return ev


## Stats line for the results screen: "Rounds 2  KOs 3  Best x2  Oops 1  Flicks 7" (Best only for
## two or more in one flick, Oops only for self-outs).
static func stats(s: Dictionary, c: int) -> String:
	var st: Dictionary = s.stats[c]
	var parts := ["Rounds %d" % s.round_wins[c], "KOs %d" % st.knocks]
	if st.best >= 2:
		parts.append("Best x%d" % st.best)
	if st.self_outs > 0:
		parts.append("Oops %d" % st.self_outs)
	parts.append("Flicks %d" % st.flicks)
	return "  ".join(parts)
