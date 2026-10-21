## Carrom bot. Lines up cut shots by the ghost-ball method (where the striker must touch a coin
## to send it at a pocket) from several baseline spots, keeps the most promising ones, adds a few
## random shots, then simulates each with the real physics and plays the one that scores best,
## with a little aiming noise so it isn't perfect.

const Rules = preload("res://games/carrom/carrom_rules.gd")
const Physics = preload("res://games/carrom/carrom_physics.gd")
const SPOTS := 9  # baseline spots tried
const RANDOM_SHOTS := 6
const MAX_CUT := 1.2  # radians: thinner cuts are too risky
const ANGLE_NOISE := 0.016
const POWER_NOISE := 0.06


## Best shot for seat c, from up to `budget` simulations.
static func pick(s: Dictionary, c: int, budget := 40) -> Dictionary:
	var best := {}
	var best_score := -INF
	for shot in candidates(s, c, budget):
		var sc := evaluate(s, c, shot)
		if sc > best_score:
			best_score = sc
			best = shot
	return noisy(s, c, best)


## Shots worth simulating, best guesses first.
static func candidates(s: Dictionary, c: int, budget := 40) -> Array:
	var aimed := []
	var mine := Rules.man_of(s, c)
	var queen_wanted: bool = s.queen == "pending:%d" % c
	for k in SPOTS:
		var x := lerpf(Rules.BASE_MIN, Rules.BASE_MAX, k / float(SPOTS - 1))
		if not Rules.can_place(s, c, x):
			continue
		var from := Rules.striker_at(c, x)
		for p in s.pieces:
			var value := _value(s, mine, p.kind, queen_wanted)
			if value <= 0.0:
				continue
			var at := Vector2(p.x, p.y)
			for pocket in Physics.POCKETS:
				var go: Vector2 = (pocket - at)
				var coin_run := go.length()
				go /= coin_run
				var ghost := at - go * (Physics.COIN_R + Physics.STRIKER_R)
				var aim := ghost - from
				var run := aim.length()
				if run < 1.0:
					continue
				aim /= run
				var cut := acos(clampf(aim.dot(go), -1.0, 1.0))
				if cut > MAX_CUT:
					continue
				if not _clear(s.pieces, from, ghost, Physics.STRIKER_R, p.id) or not _clear(s.pieces, at, pocket, Physics.COIN_R, p.id):
					continue
				# striker speed so the coin still has pace at the pocket
				var coin_v := sqrt(2.0 * Physics.FRICTION * coin_run) + 150.0
				var hit_v := coin_v / (cos(cut) * (1.0 + Physics.E_PIECE) * Physics.STRIKER_M / (Physics.STRIKER_M + Physics.COIN_M))
				var v := sqrt(hit_v * hit_v + 2.0 * Physics.FRICTION * run)
				if v > Physics.MAX_SPEED:
					continue
				var shot := {"x": x, "angle": Rules.angle_of(c, aim), "power": maxf(Rules.MIN_POWER, v / Physics.MAX_SPEED)}
				aimed.append([value * (1.2 - cut / MAX_CUT) - (run + coin_run) / 2000.0, shot])
	aimed.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	var randoms := RANDOM_SHOTS if budget > RANDOM_SHOTS * 2 else 1
	for a in aimed.slice(0, maxi(0, budget - randoms)):
		out.append(a[1])
	var tries := 0
	while out.size() < budget and tries < 200:
		tries += 1
		var x := randf_range(Rules.BASE_MIN, Rules.BASE_MAX)
		if Rules.can_place(s, c, x):
			out.append({"x": x, "angle": randf_range(-1.2, 1.2), "power": randf_range(0.35, 0.95)})
	return out


## How much pocketing a coin of `kind` is worth to the shooter; 0 = leave it alone.
static func _value(s: Dictionary, mine: int, kind: int, queen_wanted: bool) -> float:
	if mine == -1:  # Freestyle
		return Rules.POINTS[kind] / 20.0
	if kind == Rules.QUEEN:
		return 0.0 if queen_wanted else 1.3
	return 1.0 if kind == mine else 0.0


## Whether a disc of radius r can slide from a to b without touching any coin but `skip`.
static func _clear(pieces: Array, a: Vector2, b: Vector2, r: float, skip: int) -> bool:
	var ab := b - a
	var len2 := ab.length_squared()
	var reach := r + Physics.COIN_R
	for p in pieces:
		if p.id == skip:
			continue
		var q := Vector2(p.x, p.y)
		var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_squared_to(q) < reach * reach:
			return false
	return true


## Simulates the shot on a copy of the state and scores the outcome for seat c.
static func evaluate(s: Dictionary, c: int, shot: Dictionary) -> float:
	var sim := Physics.simulate(s.pieces, Rules.launch(c, shot), false)
	var t := s.duplicate(true)
	var ev := Rules.apply_result(t, c, sim)
	var sc := randf() * 0.5
	if t.phase == "over":
		return 1000.0 if t.places[t.winners.find(c)] == 0 else -1000.0
	if ev.foul != "":
		return sc - 40.0
	if s.variant == "classic":
		var mine := Rules.man_of(s, c)
		for id in ev.pocketed:
			var k := Rules.kind_of(id)
			sc += 12.0 if k == mine else 6.0 if k == Rules.QUEEN else -8.0
		if ev.queen == "covered":
			sc += 25.0
		elif ev.queen == "returned":
			sc -= 8.0
	else:
		sc += ev.points * 0.5
		if ev.queen == "returned":
			sc -= 10.0
	return sc


## The shot as a slightly unsteady hand plays it (still a legal shot).
static func noisy(s: Dictionary, c: int, shot: Dictionary) -> Dictionary:
	if shot.is_empty():
		var x := Rules.BASE_MIN
		while x < Rules.BASE_MAX and not Rules.can_place(s, c, x):
			x += 8.0
		return {"x": x, "angle": 0.0, "power": 0.5}
	return {"x": shot.x, "angle": shot.angle + randfn(0.0, ANGLE_NOISE),
		"power": clampf(shot.power * (1.0 + randfn(0.0, POWER_NOISE)), Rules.MIN_POWER, 1.0)}
