## Run: godot --headless --path . --script tests/test_pen_rules.gd
extends SceneTree

const Rules = preload("res://games/penfight/pen_rules.gd")
const Physics = preload("res://games/penfight/pen_physics.gd")
const Ai = preload("res://games/penfight/pen_ai.gd")
const GAMES := 200
const BALANCE_GAMES := 240

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func world(pens: Array) -> Dictionary:
	return {"pens": pens, "steps": 0, "acc": 0.0}


func pen(id: int, type: String, x: float, y: float, angle := 0.0) -> Dictionary:
	return Physics.new_pen(id, type, Vector2(x, y), angle)


func momentum(w: Dictionary) -> Vector2:
	var p := Vector2.ZERO
	for q in w.pens:
		p += Vector2(q.vx, q.vy) * Physics.spec(q.type).mass
	return p


## A game already in its first round with these pens.
func game(mode: String, rounds: int, colors: Array, types := {}) -> Dictionary:
	var s := Rules.new_state(mode, rounds, colors)
	for c in colors:
		Rules.pick(s, c, types.get(c, "gel"))
	return s


## A fake simulation result: these seats went over (in order, at these steps), knocked by these.
func result(s: Dictionary, fell: Array, when := {}, by := {}) -> Dictionary:
	var w: Dictionary = s.world.duplicate(true)
	var steps := {}
	var hit := {}
	for k in fell.size():
		var id: int = fell[k]
		for p in w.pens:
			if p.id == id:
				p.out = true
				p.fall = 1.0
		steps[id] = when.get(id, k)
		hit[id] = by.get(id, -1)
	return {"final": w, "fallen": fell, "fall_step": steps, "hit_by": hit, "frames": [], "events": []}


func _init() -> void:
	# --- physics ---
	# a metal pen slides end-first into a gel pen lying on the same line
	var w := world([pen(0, "metal", 300, 700), pen(1, "gel", 700, 700)])
	w.pens[0].vx = 1200.0
	var before := momentum(w)
	var hit_seen := false
	for k in 400:
		before = momentum(w)
		var evs := Physics.step(w, Physics.DT)
		if evs.any(func(e): return e.type == "hit"):
			hit_seen = true
			break
	var after := momentum(w)
	check(hit_seen, "pens on a line meet")
	check(near(after.x, before.x, 0.01) and absf(after.y) < 1.0, "momentum conserved in a head-on hit (%.0f vs %.0f)" % [before.x, after.x])
	check(w.pens[1].vx > w.pens[0].vx and w.pens[0].vx > 0.0, "the light pen shoots ahead, the heavy one follows")
	check(absf(w.pens[0].w) < 0.001 and absf(w.pens[1].w) < 0.001, "an end-on hit doesn't spin")

	var p := pen(0, "gel", 500, 700)
	Physics.flick(p, 0.0, -PI / 2, 0.5)
	check(p.w == 0.0 and p.vy < 0.0 and absf(p.vx) < 0.001, "a middle flick pushes straight")
	p = pen(0, "gel", 500, 700)
	Physics.flick(p, 1.0, -PI / 2, 0.5)
	check(absf(p.w) > 1.0, "an end flick spins")
	var sim := Physics.simulate(world([pen(0, "gel", 500, 700)]), [{"id": 0, "grab": 0.0, "angle": -PI / 2, "power": 0.4}])
	var fp: Dictionary = sim.final.pens[0]
	check(fp.vx == 0.0 and fp.vy == 0.0 and fp.w == 0.0 and sim.time < 5.0 and fp.y < 600.0, "friction stops a pen (%.0f u in %.2f s)" % [700.0 - fp.y, sim.time])
	check(absf(fp.angle) < 0.0001, "and a straight push doesn't turn it")
	sim = Physics.simulate(world([pen(0, "gel", 500, 700)]), [{"id": 0, "grab": 0.9, "angle": -PI / 2, "power": 0.4}])
	check(absf(sim.final.pens[0].angle) > 0.3, "an end flick turns it")
	var slide := {}
	for type in Physics.TYPES:
		sim = Physics.simulate(world([pen(0, type, 500, 1300)]), [{"id": 0, "grab": 0.0, "angle": -PI / 2, "power": 0.5}])
		slide[type] = 1300.0 - sim.final.pens[0].y
	check(slide.metal < slide.highlighter and slide.highlighter < slide.marker and slide.marker < slide.gel, "heavier pens slide less %s" % [slide])
	sim = Physics.simulate(world([pen(0, "gel", 500, 120), pen(1, "metal", 500, 700)]), [{"id": 0, "grab": 0.0, "angle": -PI / 2, "power": 0.6}])
	check(sim.fallen == [0] and sim.final.pens[0].out and sim.final.pens[0].fall == 1.0, "a pen pushed past the edge goes out")
	check(sim.events.any(func(e): return e.type == "edge" and e.id == 0) and sim.events.any(func(e): return e.type == "out" and e.id == 0), "edge and out events")
	check(sim.hit_by[0] == -1, "nobody knocked it")
	check(not sim.final.pens[1].out and sim.final.pens[1].x == 500.0, "the other pen stays put")
	# knock a pen off: credit goes to the knocker
	var s := game("turns", 1, [0, 2])
	s.world = world([pen(0, "metal", 500, 600, PI / 2), pen(2, "gel", 500, 250)])
	var ev := Rules.flick(s, 0, {"grab": 0.0, "angle": -PI / 2, "power": 1.0})
	check(not ev.is_empty() and 2 in ev.out and ev.knocks == [[0, 2]], "a hard push knocks the pen off, credited to the pusher %s" % [ev.get("knocks")])
	check(ev.round_winner == 0 and s.phase == "over" and s.winners == [0, 2], "last pen standing wins")
	check(s.stats[0].knocks == 1 and s.stats[0].flicks == 1, "knock-off counted")

	var start: Dictionary = game("turns", 1, [0, 1, 2, 3]).world
	var fl := [{"id": 0, "grab": 0.3, "angle": -1.4, "power": 0.9}]
	var r1 := Physics.simulate(start, fl)
	var r2 := Physics.simulate(start, fl)
	check(r1.final == r2.final and r1.frames == r2.frames and r1.events == r2.events, "same flick, same result")
	check(start == game("turns", 1, [0, 1, 2, 3]).world, "simulate leaves its input alone")
	check(r1.frames.size() > 10 and r1.frames[0].size() == 16, "frames hold every pen")
	check(not overlapping(r1.final), "pens don't end up inside each other")
	var r3 := Physics.simulate(r1.final, [{"id": 1, "grab": 0.0, "angle": 2.0, "power": 1.0}])
	check(r3.events.all(func(e): return e.t < r3.frames.size()), "a second run's events fall within its own frames")

	# --- setup ---
	for n in [2, 3, 4]:
		var cols: Array = [[0, 2], [0, 1, 2], [0, 1, 2, 3]][n - 2]
		var g := game("turns", 3, cols, {0: "marker", 1: "highlighter", 2: "marker", 3: "highlighter"})
		check(g.phase == "aim" and g.round == 1 and g.turn == cols[0], "%d players: first round starts once all picked" % n)
		check(not overlapping(g.world, 30.0), "%d players: nobody touching at the start" % n)
		check(g.world.pens.all(func(q): return Physics.edge_distance(q.x, q.y) > 150), "%d players: pens well inside the desk" % n)
		var me: Dictionary = Rules.pen_of(g, cols[0])
		check(me.y > Rules.CENTER.y + 200 and absf(me.x - Rules.CENTER.x) < 1.0, "%d players: first seat at the bottom" % n)
	s = Rules.new_state("turns", 1, [0, 1])
	check(Rules.pick(s, 0, "metal") and s.phase == "pick", "waits for every pick")
	check(not Rules.pick(s, 1, "pencil") and not Rules.pick(s, 3, "gel") and not Rules.pick(s, 1, 5), "bad picks refused")
	check(Rules.pick(s, 1, "gel") and s.phase == "aim" and Rules.pen_of(s, 0).type == "metal", "picked pens are used")

	# --- turns ---
	s = game("turns", 1, [0, 1, 2, 3])
	Rules.apply_result(s, 0, result(s, [1], {}, {1: 0}))
	check(s.turn == 2 and s.out_order == [1], "turn skips a pen that's out")
	Rules.apply_result(s, 2, result(s, []))
	Rules.apply_result(s, 3, result(s, [3]))
	check(s.turn == 0 and s.stats[3].self_outs == 1 and s.stats[0].knocks == 1, "self-out passes on and is counted")
	ev = Rules.apply_result(s, 0, result(s, []))
	check(s.turn == 2 and ev.round_winner == -1, "the round goes on with two pens")
	ev = Rules.apply_result(s, 2, result(s, [0], {}, {0: 2}))
	check(ev.round_winner == 2 and ev.over and s.winners == [2, 0, 3, 1], "last pen wins; the rest by how long they lasted %s" % [s.winners])

	# ties: both last pens go over in the same shot
	s = game("turns", 1, [0, 1])
	ev = Rules.apply_result(s, 0, result(s, [0, 1], {0: 10, 1: 12}))
	check(ev.round_winner == 1, "went over last: wins")
	s = game("turns", 1, [0, 1])
	ev = Rules.apply_result(s, 0, result(s, [1, 0], {0: 30, 1: 12}))
	check(ev.round_winner == 0, "the shooter going over last wins too")
	s = game("turns", 1, [0, 1])
	ev = Rules.apply_result(s, 0, result(s, [0, 1], {0: 12, 1: 12}))
	check(ev.round_winner == 1, "same frame: the shooter loses")
	s = game("turns", 1, [0, 1])
	s.turn = 1
	ev = Rules.apply_result(s, 1, result(s, [0, 1], {0: 12, 1: 12}))
	check(ev.round_winner == 0, "same frame: the shooter loses (other seat)")
	s = game("turns", 1, [0, 1, 2])
	ev = Rules.apply_result(s, 1, result(s, [0, 1, 2], {0: 5, 1: 5, 2: 5}))
	check(ev.round_winner == 2, "three on one frame: the next after the shooter wins")

	# rounds
	s = game("turns", 3, [0, 1, 2], {0: "metal", 1: "gel", 2: "marker"})
	ev = Rules.apply_result(s, 0, result(s, [1, 2], {}, {1: 0, 2: 0}))
	check(ev.round_winner == 0 and not ev.over and s.phase == "round_over" and s.round_wins[0] == 1, "best of 3: one round isn't enough")
	check(Rules.flick(s, s.turn, {"grab": 0.0, "angle": 0.0, "power": 0.5}).is_empty(), "no flicks between rounds")
	check(Rules.next_round(s) and s.round == 2 and s.phase == "aim" and s.turn == 1, "next round, next starter")
	check(Rules.on_desk(s).size() == 3 and Rules.pen_of(s, 0).type == "metal", "pens back on the desk")
	ev = Rules.apply_result(s, 1, result(s, [1, 0]))
	check(ev.round_winner == 2 and s.phase == "round_over", "round 2 to someone else")
	Rules.next_round(s)
	check(s.turn == 2, "round 3 starter")
	ev = Rules.apply_result(s, 2, result(s, [1, 2]))
	check(ev.round_winner == 0 and ev.over and s.winners == [0, 2, 1], "two round wins take the match %s" % [s.winners])
	check(not Rules.next_round(s), "no rounds after the end")
	check(Rules.stats(s, 0) == "Rounds 2    Knock-offs 2    Flicks 1", "stats line: %s" % Rules.stats(s, 0))

	# --- real-time ---
	s = game("realtime", 1, [0, 1])
	check(s.phase == "live", "real-time starts live")
	var f := {"grab": 0.0, "angle": -PI / 2, "power": 0.3}
	check(not Rules.live_flick(s, 0, f).is_empty(), "a ready pen flicks")
	check(Rules.live_flick(s, 0, f).is_empty(), "then waits for its cooldown")
	check(not Rules.live_flick(s, 1, f).is_empty(), "others aren't held up")
	for k in 60:
		Rules.live_step(s, 1.0 / 60.0)
	check(Rules.live_flick(s, 0, f).is_empty() and not Rules.ready(s, 0), "still cooling down after 1 s")
	for k in 15:
		Rules.live_step(s, 1.0 / 60.0)
	check(Rules.ready(s, 0) and not Rules.live_flick(s, 0, f).is_empty(), "ready after %.1f s" % Rules.COOLDOWN)
	check(s.stats[0].flicks == 2 and s.stats[1].flicks == 1, "real-time flicks counted")
	s = game("realtime", 1, [0, 1])
	s.world = world([pen(0, "metal", 500, 600, PI / 2), pen(1, "gel", 500, 250)])
	Rules.live_flick(s, 0, {"grab": 0.0, "angle": -PI / 2, "power": 1.0})
	var won := -1
	for k in 300:
		var le := Rules.live_step(s, 1.0 / 60.0)
		if le.get("round_winner", -1) != -1:
			won = le.round_winner
			break
	check(won == 0 and s.phase == "over" and s.stats[0].knocks == 1, "real-time knock-off ends the round")
	check(Rules.live_flick(s, 0, f).is_empty(), "no flicks once over")
	s = game("realtime", 1, [0, 1])
	s.world = world([pen(0, "gel", 30, 700, PI / 2), pen(1, "gel", 970, 700, PI / 2)])
	s.time = 5.0
	Rules.live_flick(s, 1, {"grab": 0.0, "angle": 0.0, "power": 0.5})
	s.time = 5.5
	s.ready_at[0] = 0.0
	Rules.live_flick(s, 0, {"grab": 0.0, "angle": PI, "power": 0.5})
	var tie := {}
	for k in 120:
		tie = Rules.live_step(s, 1.0 / 60.0)
		if tie.get("round_winner", -1) != -1:
			break
	check(tie.get("round_winner", -1) == 1, "real-time tie: the pen flicked last loses")

	# --- untrusted flicks ---
	s = game("turns", 1, [0, 1])
	var fresh := s.duplicate(true)
	for bad in [null, {}, {"grab": 0, "angle": 0}, {"grab": "0", "angle": 0, "power": 0.5}, {"grab": 1.5, "angle": 0.0, "power": 0.5},
			{"grab": 0.0, "angle": 0.0, "power": 1.5}, {"grab": 0.0, "angle": 0.0, "power": 0.0}, {"grab": NAN, "angle": 0.0, "power": 0.5},
			{"grab": 0.0, "angle": INF, "power": 0.5}, {"grab": 0.0, "angle": 0.0, "power": NAN}, {"grab": 0.0, "angle": 99.0, "power": 0.5}]:
		check(Rules.flick(s, 0, bad).is_empty(), "rejects %s" % [bad])
	var ok_f := {"grab": 0.0, "angle": 0.0, "power": 0.5}
	check(Rules.flick(s, 1, ok_f).is_empty(), "rejects out of turn")
	check(Rules.flick(s, 3, ok_f).is_empty(), "rejects a seat not playing")
	check(Rules.live_flick(s, 0, ok_f).is_empty(), "no live flicks in Turns")
	check(s == fresh, "rejected flicks change nothing")
	ev = Rules.flick(s, 0, {"grab": 0, "angle": 0, "power": 1})
	check(not ev.is_empty() and ev.sim.frames.size() > 0 and s.flicks == 1, "int fields are fine")
	s = game("turns", 1, [0, 1, 2])
	Rules.apply_result(s, 0, result(s, [1]))
	s.turn = 1  # forced: a pen that's out can't flick
	check(Rules.flick(s, 1, ok_f).is_empty(), "rejects a pen that's out")
	s = game("realtime", 1, [0, 1, 2])
	Rules.pen_of(s, 2).out = true
	check(Rules.live_flick(s, 2, ok_f).is_empty(), "real-time rejects a pen that's out")
	fresh = s.duplicate(true)
	for bad in [null, {"grab": NAN, "angle": 0.0, "power": 0.5}, {"grab": 0.0, "angle": 0.0, "power": 2.0}]:
		check(Rules.live_flick(s, 0, bad).is_empty(), "real-time rejects %s" % [bad])
	check(s == fresh, "rejected live flicks change nothing")

	# --- bots ---
	if "quick" in OS.get_cmdline_user_args():  # -- quick: rules only
		print("pen rules (quick): ", "OK" if fails == 0 else "%d failed" % fails)
		quit(1 if fails else 0)
		return
	var t := Time.get_ticks_msec()
	Ai.pick(game("turns", 1, [0, 1, 2, 3]), 0)
	var pick_ms := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	for k in 10:
		Ai.quick_pick(game("realtime", 1, [0, 1, 2, 3]), 0)
	var quick_ms := (Time.get_ticks_msec() - t) / 10.0
	t = Time.get_ticks_msec()
	var flicks := 0
	var longest := 0
	for g in GAMES:
		var cols: Array = [[0, 2], [0, 1, 2], [0, 1, 2, 3]][g % 3]
		s = random_game("turns", 1 if g % 2 == 0 else 3, cols)
		var n := play_turns(s, 8)
		if n < 0:
			check(false, "turns bot game %d broke" % g)
			continue
		flicks += n
		longest = maxi(longest, n)
		check(s.phase == "over" and s.winners.size() == cols.size(), "turns bot game %d finished (%d flicks)" % [g, n])
	print("  turns: avg %.1f flicks/match, longest %d, %d s" % [float(flicks) / GAMES, longest, (Time.get_ticks_msec() - t) / 1000])
	t = Time.get_ticks_msec()
	var secs := 0.0
	for g in GAMES:
		var cols: Array = [[0, 2], [0, 1, 2], [0, 1, 2, 3]][g % 3]
		s = random_game("realtime", 1 if g % 2 == 0 else 3, cols)
		var time := play_realtime(s)
		secs += time
		check(s.phase == "over" and s.winners.size() == cols.size(), "real-time bot game %d finished (%.0f s)" % [g, time])
	print("  real-time: avg %.1f s of play/match, %d s" % [secs / GAMES, (Time.get_ticks_msec() - t) / 1000])

	# balance: four bots, each with a different pen
	t = Time.get_ticks_msec()
	var wins := {}
	for type in Physics.TYPES:
		wins[type] = 0
	for g in BALANCE_GAMES:
		var types: Array = Physics.TYPES.duplicate()
		types.shuffle()
		s = Rules.new_state("turns", 1, [0, 1, 2, 3])
		for c in 4:
			Rules.pick(s, c, types[c])
		play_turns(s, 8)
		if s.phase == "over":
			wins[s.pens[s.winners[0]]] += 1
	var rates := []
	for type in Physics.TYPES:
		var rate: float = wins[type] / float(BALANCE_GAMES)
		rates.append("%s %d%%" % [type, roundi(rate * 100)])
		check(rate >= 0.15 and rate <= 0.40, "%s wins %d%% of 4-bot matches" % [type, roundi(rate * 100)])
	print("  balance: %s (%d s)" % [", ".join(rates), (Time.get_ticks_msec() - t) / 1000])
	print("  bot pick (30 sims, 4 pens): %d ms; quick pick: %.0f ms" % [pick_ms, quick_ms])

	print("pen rules: ", "OK" if fails == 0 else "%d failed" % fails)
	quit(1 if fails else 0)


func random_game(mode: String, rounds: int, cols: Array) -> Dictionary:
	var s := Rules.new_state(mode, rounds, cols)
	for c in cols:
		Rules.pick(s, c, Physics.TYPES.pick_random())
	return s


## Bots play a Turns match to the end; returns the flicks taken, -1 if a flick was refused.
func play_turns(s: Dictionary, budget: int) -> int:
	var n := 0
	while s.phase != "over" and n < 400:
		if s.phase == "round_over":
			Rules.next_round(s)
		var c: int = s.turn
		var f := Ai.pick(s, c, budget)
		if Rules.flick(s, c, f).is_empty():
			printerr("refused ", f)
			return -1
		n += 1
	return n


## Bots play a Real-time match with simulated time; returns the seconds played.
func play_realtime(s: Dictionary) -> float:
	var dt := 1.0 / 60.0
	var time := 0.0
	var wake := {}
	while s.phase != "over" and time < 600.0:
		if s.phase == "round_over":
			Rules.next_round(s)
			wake = {}
		for c in s.colors:
			if not Rules.ready(s, c):
				continue
			if not wake.has(c):
				wake[c] = s.time + randf_range(Ai.REACTION[0], Ai.REACTION[1])
			if s.time >= wake[c]:
				wake.erase(c)
				if Rules.live_flick(s, c, Ai.quick_pick(s, c)).is_empty():
					printerr("real-time flick refused")
		Rules.live_step(s, dt)
		time += dt
	return time


func overlapping(w: Dictionary, margin := 0.0) -> bool:
	var live: Array = w.pens.filter(func(q): return not q.out)
	for i in live.size():
		for j in range(i + 1, live.size()):
			if Physics.touching(live[i], live[j], margin - 1.0):
				return true
	return false
