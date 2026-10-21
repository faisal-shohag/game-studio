## Run: godot --headless --path . --script tests/test_carrom_rules.gd
extends SceneTree

const Rules = preload("res://games/carrom/carrom_rules.gd")
const Physics = preload("res://games/carrom/carrom_physics.gd")
const Ai = preload("res://games/carrom/carrom_ai.gd")
const W := Physics.WHITE
const B := Physics.BLACK
const Q := Physics.QUEEN
const GAMES := 200

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


func coin(id: int, at: Vector2) -> Dictionary:
	return {"id": id, "kind": Rules.kind_of(id), "x": at.x, "y": at.y}


func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


## A game with only the given coins on the board.
func board(variant: String, colors: Array, pieces: Array) -> Dictionary:
	var s := Rules.new_state(variant, colors)
	s.pieces = pieces
	return s


## A fake simulation result: these coins went in (in order), the rest stay where they are.
func result(s: Dictionary, pocketed: Array, striker_in := false) -> Dictionary:
	return {"final": s.pieces.filter(func(p): return not p.id in pocketed), "pocketed": pocketed,
		"striker_pocketed": striker_in, "first_hit": -1, "frames": [], "events": []}


## Shot from seat c straight at a board point, at full power fraction p.
func aim_at(c: int, x: float, target: Vector2, p: float) -> Dictionary:
	return {"x": x, "angle": Rules.angle_of(c, target - Rules.striker_at(c, x)), "power": p}


func _init() -> void:
	# --- physics ---
	var a := {"x": 300.0, "y": 500.0, "vx": 1200.0, "vy": 0.0}
	var sim := Physics.simulate([coin(1, Vector2(400, 500))], a)
	var e: Dictionary = sim.events.filter(func(ev): return ev.type == "hit")[0]
	check(sim.first_hit == 1, "first contact is the coin")
	# right after the hit the striker keeps going slower, the coin runs ahead faster
	var f0: PackedFloat32Array = sim.frames[e.t - 1]
	var f1: PackedFloat32Array = sim.frames[e.t + 1]
	var f2: PackedFloat32Array = sim.frames[e.t + 2]
	var slowed := Physics.FRICTION * 1.5 / 60.0  # friction since the hit, about 1.5 frames ago
	var coin_v := (f2[0] - f1[0]) * 60.0 + slowed
	var striker_v := (f2[2] - f1[2]) * 60.0 + slowed
	var before_v: float = e.speed
	var ms := Physics.STRIKER_M
	var mc := Physics.COIN_M
	check(near(ms * before_v, ms * striker_v + mc * coin_v, 0.025), "momentum conserved in a head-on hit (%.0f vs %.0f)" % [ms * before_v, ms * striker_v + mc * coin_v])
	check(coin_v > striker_v and striker_v > 0, "heavier striker follows the coin")
	check(near(coin_v - striker_v, Physics.E_PIECE * before_v, 0.05), "restitution sets the separation speed")
	check(absf(f1[1] - 500) < 0.001 and absf(f0[3] - 500) < 0.001, "a head-on hit stays on the line")

	sim = Physics.simulate([], {"x": 500.0, "y": 300.0, "vx": 800.0, "vy": -800.0})  # 45° into the top cushion
	var bounce: Dictionary = sim.events.filter(func(ev): return ev.type == "cushion")[0]
	var g0: PackedFloat32Array = sim.frames[bounce.t + 1]
	var g1: PackedFloat32Array = sim.frames[bounce.t + 3]
	var out := Vector2(g1[0] - g0[0], g1[1] - g0[1])
	check(out.y > 0 and out.x > 0, "cushion sends it back down")
	check(near(out.y / out.x, Physics.E_CUSHION, 0.05), "cushion reflects the angle, damping the bounce (%.2f)" % (out.y / out.x))

	sim = Physics.simulate([], {"x": 500.0, "y": 500.0, "vx": 300.0, "vy": 0.0})
	var travel: float = sim.striker_end.x - 500.0
	check(sim.time < 1.0 and near(travel, 300.0 * 300.0 / (2.0 * Physics.FRICTION), 0.05), "friction stops it (%.1f u in %.2f s)" % [travel, sim.time])

	var pocket: Vector2 = Physics.POCKETS[1]  # top right
	var from := Vector2(400, 600)
	var dir := (pocket - from).normalized()
	sim = Physics.simulate([coin(5, from + dir * 200)], {"x": from.x, "y": from.y, "vx": dir.x * 2500, "vy": dir.y * 2500})
	check(sim.pocketed == [5] and sim.final.is_empty(), "straight shot pockets the coin")
	check(sim.events.any(func(ev): return ev.type == "pocket" and ev.id == 5 and ev.pocket == 1), "pocket event names the pocket")
	sim = Physics.simulate([], {"x": 500.0, "y": 500.0, "vx": 2500.0, "vy": 2500.0})
	check(sim.striker_pocketed, "striker can go in too")

	var start := Rules.start_pieces()
	var shot := {"x": 520.0, "y": Rules.BASE_Y, "vx": -100.0, "vy": -3000.0}
	var r1 := Physics.simulate(start, shot)
	var r2 := Physics.simulate(start, shot)
	check(r1.final == r2.final and r1.pocketed == r2.pocketed and r1.frames == r2.frames, "same shot, same result")
	check(start == Rules.start_pieces(), "simulate leaves its input alone")
	check(r1.frames.size() > 10 and r1.frames[0].size() == (start.size() + 1) * 2, "frames hold every piece")
	var spread := true
	for i in r1.final.size():
		for j in range(i + 1, r1.final.size()):
			var p: Dictionary = r1.final[i]
			var q: Dictionary = r1.final[j]
			if Vector2(p.x, p.y).distance_to(Vector2(q.x, q.y)) < Physics.COIN_R * 2 - 0.5:
				spread = false
	check(spread, "break leaves no overlapping coins")

	# --- setup ---
	check(start.size() == 19 and start.filter(func(p): return p.kind == W).size() == 9 and start.filter(func(p): return p.kind == B).size() == 9, "9 white, 9 black, 1 queen")
	check(start.all(func(p): return Rules.kind_of(p.id) == p.kind), "ids match kinds")
	var s := Rules.new_state("classic", [0, 2])
	check(Rules.man_of(s, 0) == W and Rules.man_of(s, 2) == B and s.turn == 0, "breaker plays white")
	var s4 := Rules.new_state("classic", [0, 1, 2, 3])
	check(Rules.man_of(s4, 0) == W and Rules.man_of(s4, 2) == W and Rules.man_of(s4, 1) == B and Rules.man_of(s4, 3) == B, "partners sit opposite")
	for c in 4:
		var at := Rules.striker_at(c, 500)
		check(at.distance_to(Rules.CENTER) > 300 and near(Rules.shot_dir(c, 0).dot((Rules.CENTER - at).normalized()), 1.0), "seat %d shoots at the center" % c)
		check(near(Rules.angle_of(c, Rules.shot_dir(c, 0.3)), 0.3), "angle round trip seat %d" % c)
	check(Rules.striker_at(1, 500).x > 800, "seat 1 sits on the right")

	# --- classic ---
	var mk := func(): return board("classic", [0, 2], [coin(0, Vector2(500, 500)), coin(1, Vector2(300, 300)), coin(2, Vector2(700, 300)), coin(10, Vector2(300, 700)), coin(11, Vector2(700, 700))])
	s = mk.call()
	var ev := Rules.apply_result(s, 0, result(s, [1]))
	check(ev.again and s.turn == 0 and s.pocketed[0] == [1] and s.scores[0] == 1, "own man: shoot again")
	ev = Rules.apply_result(s, 0, result(s, [10]))
	check(not ev.again and s.turn == 2 and s.pocketed[0] == [1, 10], "opponent's man: turn passes, it stays down")
	ev = Rules.apply_result(s, 2, result(s, []))
	check(s.turn == 0 and ev.foul == "", "miss passes the turn")

	s = mk.call()
	ev = Rules.apply_result(s, 0, result(s, [0, 1]))
	check(ev.queen == "covered" and s.queen == "covered:0" and ev.again, "queen covered in the same shot")
	s = mk.call()
	ev = Rules.apply_result(s, 0, result(s, [0]))
	check(ev.queen == "pocketed" and s.queen == "pending:0" and ev.again and s.turn == 0, "queen alone: shoot again to cover")
	ev = Rules.apply_result(s, 0, result(s, [2]))
	check(ev.queen == "covered" and s.queen == "covered:0" and QUEEN_IN(s.pocketed[0]), "queen covered on the next shot")
	s = mk.call()
	Rules.apply_result(s, 0, result(s, [0]))
	ev = Rules.apply_result(s, 0, result(s, [10]))
	check(ev.queen == "returned" and s.queen == "on_board" and s.turn == 2, "no cover: the queen goes back")
	check(s.pieces.any(func(p): return p.id == 0 and Vector2(p.x, p.y).distance_to(Rules.CENTER) < 1), "returned queen sits in the center")

	s = mk.call()
	Rules.apply_result(s, 0, result(s, [1]))
	ev = Rules.apply_result(s, 0, result(s, [2], true))
	check(ev.foul == "striker" and s.turn == 2 and s.fouls[0] == 1, "striker in: foul, turn passes")
	check(2 in ev.returned and 1 in ev.returned and s.pocketed[0].is_empty(), "foul undoes the shot and costs a pocketed man")
	check(s.pieces.size() == 5 and not overlapping(s.pieces), "returned men are placed without overlap")
	s = mk.call()
	ev = Rules.apply_result(s, 0, result(s, [], true))
	check(ev.foul == "striker" and ev.returned.is_empty() and s.turn == 2, "foul with nothing to give back")
	s = mk.call()
	ev = Rules.apply_result(s, 0, result(s, [10, 11]))
	check(ev.foul == "last_man" and 10 in ev.returned and 11 in ev.returned and s.turn == 2, "opponent's last man before the queen: foul")
	s = mk.call()
	ev = Rules.apply_result(s, 0, result(s, [1, 2]))
	check(ev.foul == "last_man" and s.phase == "aim", "own last man before the queen: foul, no win")
	s = mk.call()
	Rules.apply_result(s, 0, result(s, [0]))
	ev = Rules.apply_result(s, 0, result(s, [1, 2], true))
	check(ev.queen == "returned" and s.queen == "on_board" and 0 in ev.returned, "a foul returns a pending queen")

	s = mk.call()
	Rules.apply_result(s, 0, result(s, [0, 1]))
	ev = Rules.apply_result(s, 0, result(s, [2]))
	check(ev.over and s.phase == "over" and s.winners == [0, 2] and s.places == [0, 1], "all men down and queen covered: win")
	s = mk.call()
	Rules.apply_result(s, 0, result(s, [0, 1]))
	ev = Rules.apply_result(s, 0, result(s, [10, 11]))
	check(ev.over and s.winners == [2, 0], "pocketing the opponent's last man once the queen is covered: they win")

	s = board("classic", [0, 1, 2, 3], [coin(1, Vector2(300, 300)), coin(10, Vector2(700, 700)), coin(0, Vector2(500, 500)), coin(2, Vector2(200, 200)), coin(11, Vector2(800, 800)), coin(12, Vector2(600, 250))])
	var order := []
	for k in 5:
		order.append(s.turn)
		Rules.apply_result(s, s.turn, result(s, []))
	check(order == [0, 1, 2, 3, 0], "turns go round the table")
	Rules.apply_result(s, 1, result(s, [10]))
	check(s.pocketed[1] == [10] and s.turn == 1, "partner of black shoots again on black")
	Rules.apply_result(s, 1, result(s, [0, 11]))
	Rules.apply_result(s, 1, result(s, []))
	check(s.queen == "covered:1" and s.turn == 2 and s.phase == "aim", "black covered the queen")
	Rules.apply_result(s, 2, result(s, [1, 2]))
	check(s.phase == "over" and s.winners == [0, 2, 1, 3] and s.places == [0, 0, 1, 1], "white team wins together (queen covered by the other side)")

	# --- freestyle ---
	var fk := func(): return board("freestyle", [0, 1, 2], [coin(0, Vector2(500, 500)), coin(1, Vector2(300, 300)), coin(10, Vector2(700, 700))])
	s = fk.call()
	ev = Rules.apply_result(s, 0, result(s, [1, 10]))
	check(ev.points == 30 and s.scores[0] == 30 and ev.again and s.turn == 0, "white 20 + black 10, shoot again")
	ev = Rules.apply_result(s, 0, result(s, [0]))
	check(s.phase == "over" and s.scores[0] == 80 and ev.queen == "covered", "the queen as the last coin needs no cover")
	check(s.winners[0] == 0 and s.places == [0, 1, 2], "empty board ends it, highest first")
	s = fk.call()
	Rules.apply_result(s, 0, result(s, [0]))
	ev = Rules.apply_result(s, 0, result(s, [10]))
	check(ev.queen == "covered" and s.scores[0] == 60, "any coin covers the queen")
	s = fk.call()
	Rules.apply_result(s, 0, result(s, [0]))
	ev = Rules.apply_result(s, 0, result(s, []))
	check(ev.queen == "returned" and s.scores[0] == 0 and s.turn == 1, "uncovered queen goes back")
	s = fk.call()
	Rules.apply_result(s, 1, result(s, [1]))
	ev = Rules.apply_result(s, 1, result(s, [10], true))
	check(ev.foul == "striker" and s.scores[1] == -10 and 1 in ev.returned and 10 in ev.returned and s.pocketed[1].is_empty(), "striker foul: -10, last coin back, shot undone")
	check(s.turn == 2 and s.pieces.size() == 3, "foul passes the turn")

	# --- untrusted shots ---
	s = Rules.new_state("freestyle", [0, 1])
	var fresh := s.duplicate(true)
	for bad in [null, {}, {"x": 500, "angle": 0}, {"x": "500", "angle": 0, "power": 0.5}, {"x": 100.0, "angle": 0.0, "power": 0.5},
			{"x": 900.0, "angle": 0.0, "power": 0.5}, {"x": 500.0, "angle": 0.0, "power": 1.5}, {"x": 500.0, "angle": 0.0, "power": 0.0},
			{"x": NAN, "angle": 0.0, "power": 0.5}, {"x": 500.0, "angle": INF, "power": 0.5}, {"x": 500.0, "angle": 0.0, "power": NAN}]:
		check(Rules.shoot(s, 0, bad).is_empty(), "rejects %s" % [bad])
	check(Rules.shoot(s, 1, {"x": 500.0, "angle": 0.0, "power": 0.5}).is_empty(), "rejects out of turn")
	check(Rules.shoot(s, 3, {"x": 500.0, "angle": 0.0, "power": 0.5}).is_empty(), "rejects a seat not playing")
	check(s == fresh, "rejected shots change nothing")
	s.pieces.append(coin(0, Rules.striker_at(0, 500)))
	check(Rules.shoot(s, 0, {"x": 500.0, "angle": 0.0, "power": 0.5}).is_empty(), "rejects a striker on a coin")
	s = fresh
	ev = Rules.shoot(s, 0, {"x": 500, "angle": 0, "power": 1})
	check(not ev.is_empty() and ev.sim.frames.size() > 0 and s.shots == 1, "int fields are fine")
	s.phase = "over"
	check(Rules.shoot(s, s.turn, {"x": 500.0, "angle": 0.0, "power": 0.5}).is_empty(), "no shots after the end")

	# --- bots ---
	var t0 := Time.get_ticks_msec()
	var t := Time.get_ticks_msec()
	s = Rules.new_state("classic", [0, 2])
	Ai.pick(s, 0)
	var pick_ms := Time.get_ticks_msec() - t
	for variant in ["classic", "freestyle"]:
		var shots := 0
		var pots := 0
		var longest := 0
		for game in GAMES:
			var seats: Array = [[0, 2], [0, 1, 2, 3]][game % 2] if variant == "classic" else [[0, 2], [0, 1, 2], [0, 1, 2, 3]][game % 3]
			s = Rules.new_state(variant, seats)
			var n := 0
			while s.phase != "over" and n < 600:
				var c: int = s.turn
				var sh := Ai.pick(s, c, 10)
				ev = Rules.shoot(s, c, sh)
				if ev.is_empty():
					check(false, "%s game %d: bot shot rejected %s" % [variant, game, sh])
					break
				pots += ev.pocketed.size()
				n += 1
				if s.pieces.size() + count_off(s) != 19:
					check(false, "%s game %d lost coins" % [variant, game])
					break
				if overlapping(s.pieces):
					check(false, "%s game %d: coins overlap" % [variant, game])
					break
			shots += n
			longest = maxi(longest, n)
			check(s.phase == "over" and s.winners.size() == seats.size(), "%s bot game %d finished (%d shots)" % [variant, game, n])
		print("  %s: avg %d shots/game, longest %d, %.2f pockets/shot" % [variant, shots / GAMES, longest, float(pots) / shots])
	print("  bot pick (40 sims) on the break: %d ms; bot games: %d s" % [pick_ms, (Time.get_ticks_msec() - t0) / 1000])

	print("carrom rules: ", "OK" if fails == 0 else "%d failed" % fails)
	quit(1 if fails else 0)


func QUEEN_IN(ids: Array) -> bool:
	return Rules.QUEEN_ID in ids


## Coins off the board: pocketed by someone, or a queen waiting for her cover.
func count_off(s: Dictionary) -> int:
	var n := 0
	for c in s.colors:
		n += s.pocketed[c].size()
	if s.queen.begins_with("pending"):
		n += 1
	return n


func overlapping(pieces: Array) -> bool:
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var p: Dictionary = pieces[i]
			var q: Dictionary = pieces[j]
			if Vector2(p.x, p.y).distance_to(Vector2(q.x, q.y)) < Physics.COIN_R * 2 - 1.0:
				return true
	return false
