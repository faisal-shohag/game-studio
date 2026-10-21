## Pen Fight physics: pure static functions, no nodes, no randomness. Desk units: the desk top is
## 0..1000 across and 0..1400 down, origin at the top-left. Pens are rigid capsules (a segment of
## length L with round ends of radius r) that slide with constant friction, spin, and knock each
## other about. A pen whose center of mass leaves the desk goes over: it keeps sliding while it
## tips off (no more contacts) and is then out. The same input always gives the same result on
## the same build.
##
## A world is {"pens": [pen...], "steps": physics steps run so far, "acc": unused step time};
## a pen is {id, type, x, y, angle, vx, vy, w, out, fall, hit_by}: `out` once it went over, `fall`
## 0..1 how far it has tipped off, `hit_by` the id of the last pen that knocked into it (-1 none).
## simulate() never changes its input; step() advances a world in place.

const W := 1000.0
const H := 1400.0
## Pen types. Mass, length L, radius r, grip (sliding friction factor).
const PENS := {
	"gel": {"name": "Gel", "mass": 1.2, "length": 260.0, "radius": 12.0, "grip": 0.95},
	"metal": {"name": "Metal", "mass": 1.8, "length": 240.0, "radius": 13.0, "grip": 1.15},
	"marker": {"name": "Marker", "mass": 1.5, "length": 300.0, "radius": 18.0, "grip": 1.0},
	"highlighter": {"name": "Highlighter", "mass": 1.6, "length": 220.0, "radius": 22.0, "grip": 1.1},
}
const TYPES := ["gel", "metal", "marker", "highlighter"]
const MAX_IMPULSE := 2400.0  # a full-power flick
const FRICTION := 900.0  # sliding deceleration at grip 1, u/s²
const SPIN_FRICTION := 7.0  # spin slowdown at grip 1, rad/s²
const SPIN_DAMP := 1.2  # and a bit more the faster it spins, 1/s
const INERTIA_K := 2.0  # pens resist spinning more than a thin rod would
const E := 0.6  # restitution between pens
const MU := 0.25  # pen-on-pen friction at a contact
const STOP_V := 5.0
const STOP_W := 0.08
const TIP_TIME := 0.4  # seconds from going over to gone
const DT := 1.0 / 240.0
const MAX_MOVE := 6.0  # most a pen point may move in one sub-step
const FRAME_EVERY := 4  # frames at 60 fps
const MAX_TIME := 12.0  # safety cap
const HIT_SOUND := 60.0  # slower contacts don't make an event


static func spec(type: String) -> Dictionary:
	return PENS.get(type, PENS.gel)


static func new_pen(id: int, type: String, at: Vector2, angle: float) -> Dictionary:
	return {"id": id, "type": type, "x": at.x, "y": at.y, "angle": angle, "vx": 0.0, "vy": 0.0, "w": 0.0,
		"out": false, "fall": 0.0, "hit_by": -1}


static func inertia(type: String) -> float:
	var p := spec(type)
	return p.mass * p.length * p.length / 12.0 * INERTIA_K


## Flicks a pen (in place): an impulse of power * MAX_IMPULSE along board angle `angle`, given at
## the point `grab` (-1..1) along its axis. The middle pushes it straight, an end spins it too.
static func flick(pen: Dictionary, grab: float, angle: float, power: float) -> void:
	var p := spec(pen.type)
	var j := Vector2.from_angle(angle) * power * MAX_IMPULSE
	var r: Vector2 = Vector2.from_angle(pen.angle) * grab * p.length / 2.0
	pen.vx += j.x / p.mass
	pen.vy += j.y / p.mass
	pen.w += r.cross(j) / inertia(pen.type)
	pen.hit_by = -1


## Runs a world to rest (or for at most max_time) after the given flicks ({id, grab, angle, power} each).
## With `record`, also returns frames (one PackedFloat32Array of x, y, angle, fall per pen, in
## world order, every 1/60 s) and events ({t: frame, type: "hit", a, b, speed} / {t, type: "edge",
## id} / {t, type: "out", id}).
## Returns {final: world at rest, fallen: ids in the order they went over, fall_step: id -> step it
## went over, hit_by: id -> who knocked it last (fallen pens), frames, events, time}.
static func simulate(world: Dictionary, flicks: Array, record := true, max_time := MAX_TIME) -> Dictionary:
	var w := world.duplicate(true)
	for f in flicks:
		for pen in w.pens:
			if pen.id == f.id and not pen.out:
				flick(pen, f.grab, f.angle, f.power)
	var sim := Sim.new(w, record)
	var frames := []
	if record:
		frames.append(sim.frame())
	var max_steps := int(max_time / DT)
	var n := 0
	while n < max_steps and sim.tick():
		n += 1
		if record and n % FRAME_EVERY == 0:
			frames.append(sim.frame())
	if record and n % FRAME_EVERY != 0:
		frames.append(sim.frame())
	sim.settle()
	sim.store(w)
	return {"final": w, "fallen": sim.fallen, "fall_step": sim.fall_step, "hit_by": sim.knocked,
		"frames": frames, "events": sim.events, "time": n * DT}


## Advances a world in place by dt (fixed steps; the rest carries over). Returns the events, with
## `t` counted in steps since the world began.
static func step(world: Dictionary, dt: float) -> Array:
	var sim := Sim.new(world, true)
	var acc: float = world.get("acc", 0.0) + dt
	while acc >= DT:
		acc -= DT
		sim.tick()
	world.acc = acc
	sim.store(world)
	return sim.events


## Whether anything in the world still moves (or is still tipping off).
static func moving(world: Dictionary) -> bool:
	for pen in world.pens:
		if pen.fall < 1.0 and (pen.out or pen.vx != 0.0 or pen.vy != 0.0 or pen.w != 0.0):
			return true
	return false


static func on_desk(x: float, y: float) -> bool:
	return x >= 0.0 and x <= W and y >= 0.0 and y <= H


## Distance from a point to the nearest desk edge (negative off the desk).
static func edge_distance(x: float, y: float) -> float:
	return minf(minf(x, W - x), minf(y, H - y))


## The two ends of a pen's axis.
static func ends(pen: Dictionary) -> Array:
	var half: Vector2 = Vector2.from_angle(pen.angle) * spec(pen.type).length / 2.0
	var c := Vector2(pen.x, pen.y)
	return [c - half, c + half]


## Closest points [on segment p1-q1, on segment p2-q2]. Nearly parallel segments take the middle
## of their overlap, so two pens lying side by side touch along their middle, not at one end.
static func closest(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> Array:
	return Sim.closest(p1, q1, p2, q2)


## Whether two pens touch (or overlap).
static func touching(a: Dictionary, b: Dictionary, margin := 0.0) -> bool:
	var ea := ends(a)
	var eb := ends(b)
	var cp: Array = closest(ea[0], ea[1], eb[0], eb[1])
	var reach: float = spec(a.type).radius + spec(b.type).radius + margin
	return cp[0].distance_squared_to(cp[1]) < reach * reach


## The working copy of a world, in packed arrays.
class Sim:
	var n := 0
	var record := true
	var ids := PackedInt32Array()
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var pa := PackedFloat64Array()
	var vx := PackedFloat64Array()
	var vy := PackedFloat64Array()
	var w := PackedFloat64Array()
	var half := PackedFloat64Array()
	var rad := PackedFloat64Array()
	var inv_m := PackedFloat64Array()
	var inv_i := PackedFloat64Array()
	var grip := PackedFloat64Array()
	var out := PackedByteArray()
	var fall := PackedFloat64Array()
	var hit_by := PackedInt32Array()
	var steps := 0
	var events := []
	var fallen := []
	var fall_step := {}
	var knocked := {}

	func _init(world: Dictionary, rec: bool) -> void:
		record = rec
		steps = world.get("steps", 0)
		for pen in world.pens:
			var p: Dictionary = PENS.get(pen.type, PENS.gel)
			ids.append(pen.id)
			px.append(pen.x)
			py.append(pen.y)
			pa.append(pen.angle)
			vx.append(pen.vx)
			vy.append(pen.vy)
			w.append(pen.w)
			half.append(p.length / 2.0)
			rad.append(p.radius)
			inv_m.append(1.0 / p.mass)
			inv_i.append(1.0 / (p.mass * p.length * p.length / 12.0 * INERTIA_K))
			grip.append(p.grip)
			out.append(1 if pen.out else 0)
			fall.append(pen.fall)
			hit_by.append(pen.hit_by)
		n = ids.size()

	func store(world: Dictionary) -> void:
		world.steps = steps
		for i in n:
			var pen: Dictionary = world.pens[i]
			pen.x = px[i]
			pen.y = py[i]
			pen.angle = pa[i]
			pen.vx = vx[i]
			pen.vy = vy[i]
			pen.w = w[i]
			pen.out = out[i] == 1
			pen.fall = fall[i]
			pen.hit_by = hit_by[i]

	func frame() -> PackedFloat32Array:
		var f := PackedFloat32Array()
		f.resize(n * 4)
		for i in n:
			f[i * 4] = px[i]
			f[i * 4 + 1] = py[i]
			f[i * 4 + 2] = pa[i]
			f[i * 4 + 3] = fall[i]
		return f

	static func closest(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> Array:
		var d1 := q1 - p1
		var d2 := q2 - p2
		var r := p1 - p2
		var a := d1.dot(d1)
		var e := d2.dot(d2)
		var f := d2.dot(r)
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var denom := a * e - b * b
		var s := 0.0
		var t := 0.0
		if denom > 1e-4 * a * e:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
		else:
			var sa := (p2 - p1).dot(d1) / a
			var sb := (q2 - p1).dot(d1) / a
			var lo := clampf(minf(sa, sb), 0.0, 1.0)
			var hi := clampf(maxf(sa, sb), 0.0, 1.0)
			s = (lo + hi) / 2.0
			t = clampf((p1 + d1 * s - p2).dot(d2) / e, 0.0, 1.0)
		return [p1 + d1 * s, p2 + d2 * t]

	## Pens still tipping when the run stops are gone.
	func settle() -> void:
		for i in n:
			if out[i] == 1 and fall[i] < 1.0:
				fall[i] = 1.0
				vx[i] = 0.0
				vy[i] = 0.0
				w[i] = 0.0

	## One fixed step. Returns false when nothing moves (nothing was done).
	func tick() -> bool:
		var fastest := 0.0
		var any := false
		for i in n:
			if fall[i] >= 1.0:
				continue
			if vx[i] != 0.0 or vy[i] != 0.0 or w[i] != 0.0 or out[i] == 1:
				any = true
				fastest = maxf(fastest, absf(vx[i]) + absf(vy[i]) + absf(w[i]) * half[i])
		if not any:
			return false
		var subs := maxi(1, ceili(fastest * DT / MAX_MOVE))
		var h := DT / subs
		var t := (steps + FRAME_EVERY) / FRAME_EVERY  # the frame this step shows up in
		for sub in subs:
			_move(h, t)
			_contacts(t)
		steps += 1
		return true

	func _move(h: float, t: int) -> void:
		for i in n:
			if fall[i] >= 1.0:
				continue
			px[i] += vx[i] * h
			py[i] += vy[i] * h
			pa[i] += w[i] * h
			if out[i] == 1:  # tipping off: keeps sliding, nothing slows it
				fall[i] = minf(1.0, fall[i] + h / TIP_TIME)
				if fall[i] >= 1.0:
					vx[i] = 0.0
					vy[i] = 0.0
					w[i] = 0.0
					if record:
						events.append({"t": t, "type": "out", "id": ids[i]})
				continue
			var sp := sqrt(vx[i] * vx[i] + vy[i] * vy[i])
			if sp != 0.0:
				var slow := sp - FRICTION * grip[i] * h
				if slow < STOP_V:
					vx[i] = 0.0
					vy[i] = 0.0
				else:
					vx[i] *= slow / sp
					vy[i] *= slow / sp
			if w[i] != 0.0:
				var spin := absf(w[i])
				var less := spin - (SPIN_FRICTION * grip[i] + SPIN_DAMP * spin) * h
				w[i] = 0.0 if less < STOP_W else signf(w[i]) * less
			if not (px[i] >= 0.0 and px[i] <= W and py[i] >= 0.0 and py[i] <= H):
				out[i] = 1
				fall_step[ids[i]] = steps
				fallen.append(ids[i])
				knocked[ids[i]] = hit_by[i]
				if record:
					events.append({"t": t, "type": "edge", "id": ids[i]})

	## Every moving pen against every other pen still on the desk (resting pairs can't touch).
	func _contacts(t: int) -> void:
		for i in n:
			if out[i] == 1:
				continue
			var i_moves := vx[i] != 0.0 or vy[i] != 0.0 or w[i] != 0.0
			for j in range(i + 1, n):
				if out[j] == 1:
					continue
				if not i_moves and vx[j] == 0.0 and vy[j] == 0.0 and w[j] == 0.0:
					continue
				var dx := px[j] - px[i]
				var dy := py[j] - py[i]
				var far := half[i] + half[j] + rad[i] + rad[j]
				if dx * dx + dy * dy >= far * far:
					continue
				_collide(i, j, t)

	func _collide(i: int, j: int, t: int) -> void:
		var ci := Vector2(px[i], py[i])
		var cj := Vector2(px[j], py[j])
		var ai := Vector2(cos(pa[i]), sin(pa[i])) * half[i]
		var aj := Vector2(cos(pa[j]), sin(pa[j])) * half[j]
		var cp: Array = closest(ci - ai, ci + ai, cj - aj, cj + aj)
		var a: Vector2 = cp[0]
		var b: Vector2 = cp[1]
		var reach := rad[i] + rad[j]
		var d := a.distance_to(b)
		if d >= reach:
			return
		var nrm := (b - a) / d if d > 1e-6 else Vector2(-ai.y, ai.x).normalized()
		var wi := inv_m[i]
		var wj := inv_m[j]
		var push := (reach - d) / (wi + wj)
		px[i] -= nrm.x * push * wi
		py[i] -= nrm.y * push * wi
		px[j] += nrm.x * push * wj
		py[j] += nrm.y * push * wj
		var at := (a + nrm * rad[i] + b - nrm * rad[j]) / 2.0
		var ri := at - ci
		var rj := at - cj
		var vi := Vector2(vx[i] - w[i] * ri.y, vy[i] + w[i] * ri.x)
		var vj := Vector2(vx[j] - w[j] * rj.y, vy[j] + w[j] * rj.x)
		var vn := (vj - vi).dot(nrm)
		if vn >= 0.0:
			return  # already separating
		# who knocked whom: the one coming in faster along the contact normal
		if vi.dot(nrm) >= -vj.dot(nrm):
			hit_by[j] = ids[i]
		else:
			hit_by[i] = ids[j]
		var rni := ri.cross(nrm)
		var rnj := rj.cross(nrm)
		var jn := -(1.0 + E) * vn / (wi + wj + rni * rni * inv_i[i] + rnj * rnj * inv_i[j])
		var tan := Vector2(-nrm.y, nrm.x)
		var vt := (vj - vi).dot(tan)
		var rti := ri.cross(tan)
		var rtj := rj.cross(tan)
		var jt := clampf(-vt / (wi + wj + rti * rti * inv_i[i] + rtj * rtj * inv_i[j]), -MU * jn, MU * jn)
		var imp := nrm * jn + tan * jt
		vx[i] -= imp.x * wi
		vy[i] -= imp.y * wi
		w[i] -= ri.cross(imp) * inv_i[i]
		vx[j] += imp.x * wj
		vy[j] += imp.y * wj
		w[j] += rj.cross(imp) * inv_i[j]
		if record and -vn > HIT_SOUND:
			events.append({"t": t, "type": "hit", "a": ids[i], "b": ids[j], "speed": -vn})
