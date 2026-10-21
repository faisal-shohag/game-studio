## Pen Fight bot. Turns: for each opponent pen, aims at its middle and ends from its own pen,
## favoring flicks that push the target toward its nearest desk edge, tries a few grab points and
## powers, adds some random flicks, simulates each with the real physics and plays the best one
## with a little aiming noise. Real-time: the same idea with only a handful of short simulations.

const Rules = preload("res://games/penfight/pen_rules.gd")
const Physics = preload("res://games/penfight/pen_physics.gd")
const GRABS := [0.0, -0.45, 0.45]
const POWERS := [0.45, 0.7, 1.0]
const RANDOM_FLICKS := 4
const ANGLE_NOISE := 0.03
const POWER_NOISE := 0.08
const QUICK := 6  # Real-time: simulations per decision
const QUICK_TIME := 1.5  # Real-time: seconds simulated ahead
const REACTION := [0.4, 1.0]  # Real-time: seconds a bot waits once its pen is ready


## Best flick for seat c (Turns), from up to `budget` simulations.
static func pick(s: Dictionary, c: int, budget := 30) -> Dictionary:
	var best := {}
	var best_score := -INF
	for f in candidates(s, c, budget):
		var sc := evaluate(s, c, f)
		if sc > best_score:
			best_score = sc
			best = f
	return noisy(best)


## Flicks worth simulating, best guesses first.
static func candidates(s: Dictionary, c: int, budget := 30) -> Array:
	var me := Rules.pen_of(s, c)
	var from := Vector2(me.x, me.y)
	var aimed := []
	for o in s.world.pens:
		if o.id == c or o.out:
			continue
		var push := _edge_dir(o)
		var edge := Physics.edge_distance(o.x, o.y)
		var ends := Physics.ends(o)
		for target in [Vector2(o.x, o.y), ends[0].lerp(ends[1], 0.2), ends[0].lerp(ends[1], 0.8)]:
			var d: Vector2 = target - from
			var run := d.length()
			if run < 1.0:
				continue
			d /= run
			var guess := d.dot(push) * 2.0 - edge / 500.0 - run / 2000.0
			for grab in GRABS:
				for p in POWERS:
					aimed.append([guess - absf(grab) * 0.3 - absf(p - 0.7), {"grab": grab, "angle": d.angle(), "power": p}])
	aimed.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	var randoms := RANDOM_FLICKS if budget > RANDOM_FLICKS * 2 else 1
	for a in aimed.slice(0, maxi(0, budget - randoms)):
		out.append(a[1])
	while out.size() < budget:
		out.append({"grab": randf_range(-1.0, 1.0), "angle": randf_range(-PI, PI), "power": randf_range(0.3, 1.0)})
	return out


## Outward direction of the desk edge nearest to a pen.
static func _edge_dir(pen: Dictionary) -> Vector2:
	var gaps := [pen.x, Physics.W - pen.x, pen.y, Physics.H - pen.y]
	var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var k := 0
	for i in 4:
		if gaps[i] < gaps[k]:
			k = i
	return dirs[k]


## Simulates the flick on a copy of the state and scores the outcome for seat c.
static func evaluate(s: Dictionary, c: int, f: Dictionary) -> float:
	var fl := f.duplicate()
	fl.id = c
	var sim := Physics.simulate(s.world, [fl], false)
	return score(c, sim.final, sim.fallen)


## How good a world is for seat c, given the pens that just went over.
static func score(c: int, world: Dictionary, fell: Array) -> float:
	var sc := randf() * 0.5
	if c in fell:
		return sc - 1000.0
	var rivals := 0
	for pen in world.pens:
		if pen.id in fell:
			sc += 100.0
		elif pen.out:
			continue
		elif pen.id == c:
			sc -= maxf(0.0, 260.0 - Physics.edge_distance(pen.x, pen.y)) * 0.3
		else:
			rivals += 1
			sc += maxf(0.0, 300.0 - Physics.edge_distance(pen.x, pen.y)) * 0.1
	if rivals == 0:
		sc += 500.0
	return sc


## The flick as a slightly unsteady hand plays it (still a legal flick).
static func noisy(f: Dictionary) -> Dictionary:
	if f.is_empty():
		return {"grab": 0.0, "angle": -PI / 2, "power": 0.5}
	return {"grab": clampf(f.grab + randfn(0.0, 0.05), -1.0, 1.0), "angle": wrapf(f.angle + randfn(0.0, ANGLE_NOISE), -PI, PI),
		"power": clampf(f.power * (1.0 + randfn(0.0, POWER_NOISE)), Rules.MIN_POWER, 1.0)}


## Real-time: a quick flick for seat c from the world as it is now (pens may still be moving).
static func quick_pick(s: Dictionary, c: int) -> Dictionary:
	var best := {}
	var best_score := -INF
	for f in quick_candidates(s, c):
		var sc := quick_eval(s, c, f)
		if sc > best_score:
			best_score = sc
			best = f
	return noisy(best)


## Real-time: the few flicks worth a short simulation.
static func quick_candidates(s: Dictionary, c: int) -> Array:
	return candidates(s, c, QUICK + 2).slice(0, QUICK)


## Real-time: simulates the next QUICK_TIME seconds after the flick and scores them for seat c.
static func quick_eval(s: Dictionary, c: int, f: Dictionary) -> float:
	var fl := f.duplicate()
	fl.id = c
	var sim := Physics.simulate(s.world, [fl], false, QUICK_TIME)
	return score(c, sim.final, sim.fallen)
