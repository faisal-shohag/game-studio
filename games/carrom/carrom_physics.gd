## Carrom physics: pure static functions, no nodes, no randomness. Board units: the playing area
## is 0..1000 on both axes (1 cm is about 13.5 u). Pieces slide with constant friction, bounce off
## each other and the cushions, and drop into a corner pocket once their center is within
## POCKET_R of it. The same input always gives the same result on the same build.
##
## A piece is {"id": int, "kind": int, "x": float, "y": float}; kinds are WHITE, BLACK, QUEEN and
## STRIKER. simulate() never changes its input.

const WHITE := 0
const BLACK := 1
const QUEEN := 2
const STRIKER := 3
const SIZE := 1000.0
const COIN_R := 21.0
const STRIKER_R := 28.0
const POCKET_R := 30.0
const COIN_M := 1.0
const STRIKER_M := 2.8
const E_PIECE := 0.9  # restitution between pieces
const E_CUSHION := 0.75
const FRICTION := 1300.0  # sliding deceleration, u/s²
const STOP_V := 6.0  # slower than this and a piece rests
const MAX_SPEED := 3200.0  # striker speed at full power
const DT := 1.0 / 240.0
const MAX_MOVE := 14.0  # most a piece may move in one sub-step (no tunneling through a coin)
const FRAME_EVERY := 4  # frames at 60 fps
const MAX_TIME := 15.0  # safety cap
const HIT_SOUND := 60.0  # slower contacts don't make an event
const POCKETS := [Vector2(POCKET_R, POCKET_R), Vector2(SIZE - POCKET_R, POCKET_R),
	Vector2(POCKET_R, SIZE - POCKET_R), Vector2(SIZE - POCKET_R, SIZE - POCKET_R)]


static func radius(kind: int) -> float:
	return STRIKER_R if kind == STRIKER else COIN_R


## Runs one shot to rest. `pieces`: the coins on the board; `striker`: {x, y, vx, vy}.
## With `record`, also returns frames (one PackedFloat32Array of x, y pairs per 1/60 s, coins in
## input order then the striker; a pocketed piece stays at its pocket) and contact events.
## Returns {final: coins left on the board, pocketed: coin ids in order, striker_pocketed,
## first_hit: id of the first coin the striker touched or -1, frames, events, time}.
## Events: {t: frame, type: "hit", a, b, speed} / {t, type: "cushion", id, speed} /
## {t, type: "pocket", id, pocket}.
static func simulate(pieces: Array, striker: Dictionary, record := true) -> Dictionary:
	var n := pieces.size() + 1
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var vx := PackedFloat64Array()
	var vy := PackedFloat64Array()
	var rad := PackedFloat64Array()
	var inv_m := PackedFloat64Array()
	var ids := PackedInt32Array()
	var live := PackedByteArray()
	for p in pieces:
		px.append(p.x)
		py.append(p.y)
		vx.append(0.0)
		vy.append(0.0)
		rad.append(COIN_R)
		inv_m.append(1.0 / COIN_M)
		ids.append(p.id)
		live.append(1)
	var si := n - 1
	px.append(striker.x)
	py.append(striker.y)
	vx.append(striker.vx)
	vy.append(striker.vy)
	rad.append(STRIKER_R)
	inv_m.append(1.0 / STRIKER_M)
	ids.append(-1)
	live.append(1)

	var frames := []
	var events := []
	var pocketed := []
	var striker_in := false
	var first_hit := -1
	var moving := PackedInt32Array()
	var mov := PackedByteArray()  # 1 = in `moving`
	mov.resize(n)
	var step := 0
	var max_steps := int(MAX_TIME / DT)
	if record:
		frames.append(_frame(px, py))
	while step < max_steps:
		moving.clear()
		var fastest := 0.0
		for i in n:
			mov[i] = 0
			if live[i] == 1 and (vx[i] != 0.0 or vy[i] != 0.0):
				moving.append(i)
				mov[i] = 1
				fastest = maxf(fastest, absf(vx[i]) + absf(vy[i]))
		if moving.is_empty():
			break
		var subs := maxi(1, ceili(fastest * DT / MAX_MOVE))
		var h := DT / subs
		var t := (step + FRAME_EVERY) / FRAME_EVERY  # the frame this step shows up in
		for sub in subs:
			# move, slow down, fall in a pocket or bounce off a cushion
			for i in moving:
				if live[i] == 0:
					continue
				var sp := sqrt(vx[i] * vx[i] + vy[i] * vy[i])
				if sp == 0.0:
					continue
				px[i] += vx[i] * h
				py[i] += vy[i] * h
				var slow := sp - FRICTION * h
				if slow < STOP_V:
					vx[i] = 0.0
					vy[i] = 0.0
				else:
					vx[i] *= slow / sp
					vy[i] *= slow / sp
				var pocket := _pocket_at(px[i], py[i])
				if pocket != -1:
					live[i] = 0
					px[i] = POCKETS[pocket].x
					py[i] = POCKETS[pocket].y
					vx[i] = 0.0
					vy[i] = 0.0
					if i == si:
						striker_in = true
					else:
						pocketed.append(ids[i])
					if record:
						events.append({"t": t, "type": "pocket", "id": ids[i], "pocket": pocket})
					continue
				var r := rad[i]
				var hit := 0.0
				if px[i] < r and vx[i] < 0.0:
					px[i] = r + (r - px[i])
					hit = -vx[i]
					vx[i] = -vx[i] * E_CUSHION
				elif px[i] > SIZE - r and vx[i] > 0.0:
					px[i] = (SIZE - r) - (px[i] - (SIZE - r))
					hit = vx[i]
					vx[i] = -vx[i] * E_CUSHION
				if py[i] < r and vy[i] < 0.0:
					py[i] = r + (r - py[i])
					hit = maxf(hit, -vy[i])
					vy[i] = -vy[i] * E_CUSHION
				elif py[i] > SIZE - r and vy[i] > 0.0:
					py[i] = (SIZE - r) - (py[i] - (SIZE - r))
					hit = maxf(hit, vy[i])
					vy[i] = -vy[i] * E_CUSHION
				if record and hit > HIT_SOUND:
					events.append({"t": t, "type": "cushion", "id": ids[i], "speed": hit})
			# contacts: every moving piece against everything else (resting pairs can't touch)
			var woke := false
			for i in moving:
				if live[i] == 0:
					continue
				for j in n:
					if j == i or live[j] == 0:
						continue
					if j < i and mov[j] == 1:
						continue  # this pair was handled from j's side
					var dx := px[j] - px[i]
					var dy := py[j] - py[i]
					var reach := rad[i] + rad[j]
					var d2 := dx * dx + dy * dy
					if d2 >= reach * reach or d2 == 0.0:
						continue
					var d := sqrt(d2)
					var nx := dx / d
					var ny := dy / d
					var wi := inv_m[i]
					var wj := inv_m[j]
					var push := (reach - d) / (wi + wj)
					px[i] -= nx * push * wi
					py[i] -= ny * push * wi
					px[j] += nx * push * wj
					py[j] += ny * push * wj
					var closing := (vx[i] - vx[j]) * nx + (vy[i] - vy[j]) * ny
					if closing <= 0.0:
						continue
					var imp := (1.0 + E_PIECE) * closing / (wi + wj)
					vx[i] -= imp * wi * nx
					vy[i] -= imp * wi * ny
					vx[j] += imp * wj * nx
					vy[j] += imp * wj * ny
					if mov[j] == 0:
						woke = true
					if first_hit == -1 and (i == si or j == si):
						first_hit = ids[j] if i == si else ids[i]
					if record and closing > HIT_SOUND:
						events.append({"t": t, "type": "hit", "a": ids[i], "b": ids[j], "speed": closing})
			if woke:
				moving.clear()
				for i in n:
					mov[i] = 0
					if live[i] == 1 and (vx[i] != 0.0 or vy[i] != 0.0):
						moving.append(i)
						mov[i] = 1
		step += 1
		if record and step % FRAME_EVERY == 0:
			frames.append(_frame(px, py))
	if record and step % FRAME_EVERY != 0:
		frames.append(_frame(px, py))

	var final := []
	for i in pieces.size():
		if live[i] == 1:
			final.append({"id": ids[i], "kind": pieces[i].kind, "x": px[i], "y": py[i]})
	return {"final": final, "pocketed": pocketed, "striker_pocketed": striker_in, "first_hit": first_hit,
		"frames": frames, "events": events, "time": step * DT,
		"striker_end": Vector2(px[si], py[si])}


static func _frame(px: PackedFloat64Array, py: PackedFloat64Array) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(px.size() * 2)
	for i in px.size():
		f[i * 2] = px[i]
		f[i * 2 + 1] = py[i]
	return f


static func _pocket_at(x: float, y: float) -> int:
	var far := POCKET_R * 2.0
	if (x > far and x < SIZE - far) or (y > far and y < SIZE - far):
		return -1  # nowhere near a corner
	for k in 4:
		var p: Vector2 = POCKETS[k]
		if (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) < POCKET_R * POCKET_R:
			return k
	return -1
