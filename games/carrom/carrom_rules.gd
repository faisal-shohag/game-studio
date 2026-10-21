## Pure Carrom rules. No nodes, no UI, no network: state is a plain Dictionary, like
## cards_rules.gd. Nothing is hidden, so every phone may hold the whole state.
##
## Seats are 0..3 and each shoots from its own side of the board: 0 bottom, 1 right, 2 top,
## 3 left (play goes round counter-clockwise, as in real carrom). A shot is given in the shooter's
## own frame, as if they sat at the bottom: {x: striker spot along their baseline, angle: radians
## from straight ahead (positive = to their right), power: 0..1}.
##
## Classic: white against black, 1v1 or 2v2 with partners opposite; the breaker's side is white.
## Pocketing one of your men (or the queen) earns another shot. The queen must be covered by one
## of your men in the same shot or the next one, else she goes back to the center. Fouls: the
## striker goes in, or a shot leaves a side with no men while the queen is still uncovered. A foul
## undoes the shot's pockets, sends one of your pocketed men back to the center and passes the
## turn. A side wins with all its men pocketed and the queen covered.
##
## Freestyle: 2-4 players, each for themselves. Any coin scores for the shooter (white 20, black
## 10, queen 50 once covered by any coin). Pocketing earns another shot. The striker going in
## undoes the shot's pockets, costs 10 and sends your last coin back. Ends when the board is
## empty; the highest score wins.

const Physics = preload("res://games/carrom/carrom_physics.gd")
const WHITE := Physics.WHITE
const BLACK := Physics.BLACK
const QUEEN := Physics.QUEEN
const MEN := 9  # per color
const QUEEN_ID := 0  # whites are 1..9, blacks 10..18
const POINTS := {WHITE: 20, BLACK: 10, QUEEN: 50}
const FOUL_COST := 10
const BASE_Y := 841.5  # baseline center line, in the shooter's frame
const BASE_MIN := 204.0  # striker spots: from one base circle to the other
const BASE_MAX := 796.0
const MIN_POWER := 0.05
const CENTER := Vector2(500, 500)


static func new_state(variant: String, colors: Array) -> Dictionary:
	var s := {
		"variant": variant,
		"colors": colors.duplicate(),
		"teams": {},  # seat -> 0 (white side) or 1; Freestyle: everyone their own
		"turn": colors[0],
		"pieces": start_pieces(),
		"pocketed": {},  # seat -> coin ids that player pocketed and still holds
		"scores": {},  # Freestyle points; Classic: coins pocketed
		"fouls": {},
		"queen": "on_board",  # on_board | pending:<seat> | covered:<seat>
		"phase": "aim",  # aim | over
		"winners": [],  # finishing order once over
		"places": [],  # place (0 = 1st) of each entry in `winners`; partners share one
		"shots": 0,
	}
	for k in colors.size():
		var c: int = colors[k]
		s.teams[c] = k % 2 if variant == "classic" else k
		s.pocketed[c] = []
		s.scores[c] = 0
		s.fouls[c] = 0
	return s


## The queen in the middle, a ring of six around her and twelve around those; colors alternate
## so each side has nine.
static func start_pieces() -> Array:
	var p := [{"id": QUEEN_ID, "kind": QUEEN, "x": CENTER.x, "y": CENTER.y}]
	var d := Physics.COIN_R * 2 + 0.5
	var slots := []
	for k in 6:
		slots.append([Vector2.from_angle(k * PI / 3 - PI / 2) * d, k % 2])
	for k in 6:
		slots.append([Vector2.from_angle(k * PI / 3 - PI / 2) * d * 2, k % 2])
		slots.append([Vector2.from_angle(k * PI / 3 - PI / 2 + PI / 6) * d * sqrt(3.0), (k + 1) % 2])
	var next := {WHITE: 1, BLACK: 10}
	for sl in slots:
		var kind: int = sl[1]
		var at: Vector2 = CENTER + sl[0]
		p.append({"id": next[kind], "kind": kind, "x": at.x, "y": at.y})
		next[kind] += 1
	return p


static func kind_of(id: int) -> int:
	return QUEEN if id == QUEEN_ID else WHITE if id <= MEN else BLACK


## Classic: the color seat c plays (the breaker's side is white). -1 in Freestyle.
static func man_of(s: Dictionary, c: int) -> int:
	if s.variant != "classic":
		return -1
	return WHITE if s.teams[c] == 0 else BLACK


## Board point for a spot in seat c's frame (c sits at the bottom of its own frame).
static func to_board(c: int, local: Vector2) -> Vector2:
	return CENTER + (local - CENTER).rotated(-c * PI / 2)


static func to_local(c: int, board: Vector2) -> Vector2:
	return CENTER + (board - CENTER).rotated(c * PI / 2)


## Board direction of a shot at `angle` from seat c.
static func shot_dir(c: int, angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle)).rotated(-c * PI / 2)


## Angle (in seat c's frame) that shoots along board direction `dir`.
static func angle_of(c: int, dir: Vector2) -> float:
	var l := dir.rotated(c * PI / 2)
	return atan2(l.x, -l.y)


static func striker_at(c: int, x: float) -> Vector2:
	return to_board(c, Vector2(x, BASE_Y))


## Whether the striker may sit at x on seat c's baseline (not on top of a coin).
static func can_place(s: Dictionary, c: int, x: float) -> bool:
	if not (x >= BASE_MIN and x <= BASE_MAX):  # also false for NaN
		return false
	var at := striker_at(c, x)
	var reach := Physics.STRIKER_R + Physics.COIN_R
	for p in s.pieces:
		if Vector2(p.x, p.y).distance_squared_to(at) < reach * reach:
			return false
	return true


## The striker launch for a shot: {x, y, vx, vy} on the board.
static func launch(c: int, shot: Dictionary) -> Dictionary:
	var at := striker_at(c, shot.x)
	var v: Vector2 = shot_dir(c, shot.angle) * shot.power * Physics.MAX_SPEED
	return {"x": at.x, "y": at.y, "vx": v.x, "vy": v.y}


## Whether a shot from an untrusted source is well formed and allowed now.
static func valid_shot(s: Dictionary, c: int, shot) -> bool:
	if s.phase != "aim" or c != s.turn or typeof(shot) != TYPE_DICTIONARY:
		return false
	for k in ["x", "angle", "power"]:
		var v: Variant = shot.get(k)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
		if is_nan(float(v)) or is_inf(float(v)):
			return false
	if not (shot.power >= MIN_POWER and shot.power <= 1.0) or absf(shot.angle) > TAU:
		return false
	return can_place(s, c, shot.x)


## Seat c shoots. Returns {} when illegal, else an event:
##   {seat, shot, sim (Physics.simulate result), pocketed: coin ids, striker_in, foul: "" | "striker" |
##    "last_man", returned: coin ids put back in the center, queen: "" | "pocketed" | "covered" |
##    "returned", points: score change, again: shoots again, over}
static func shoot(s: Dictionary, c: int, shot) -> Dictionary:
	if not valid_shot(s, c, shot):
		return {}
	shot = {"x": float(shot.x), "angle": float(shot.angle), "power": float(shot.power)}
	var sim := Physics.simulate(s.pieces, launch(c, shot))
	var ev := apply_result(s, c, sim)
	ev.shot = shot
	ev.sim = sim
	return ev


## Applies a finished simulation of seat c's shot to the state; returns the event (without
## shot and sim). Bots use it on copies to score candidate shots.
static func apply_result(s: Dictionary, c: int, sim: Dictionary) -> Dictionary:
	s.pieces = sim.final.duplicate(true)
	s.shots += 1
	var ev := {"seat": c, "pocketed": sim.pocketed.duplicate(), "striker_in": sim.striker_pocketed, "foul": "",
		"returned": [], "queen": "", "points": 0, "again": false, "over": false}
	if s.variant == "classic":
		_classic(s, c, ev)
	else:
		_freestyle(s, c, ev)
	if not ev.returned.is_empty():
		place_returned(s, ev.returned)
	if not ev.again and s.phase != "over":
		s.turn = next_of(s, c)
	ev.over = s.phase == "over"
	return ev


static func _classic(s: Dictionary, c: int, ev: Dictionary) -> void:
	var mine := man_of(s, c)
	var own: Array = ev.pocketed.filter(func(id): return kind_of(id) == mine)
	var queen_in: bool = QUEEN_ID in ev.pocketed
	var had_queen: bool = s.queen == "pending:%d" % c
	var covers := (queen_in or had_queen) and not own.is_empty()
	var covered: bool = s.queen.begins_with("covered") or covers
	if ev.striker_in:
		ev.foul = "striker"
	elif not covered and (_left(s, WHITE) == 0 or _left(s, BLACK) == 0):
		ev.foul = "last_man"
	if ev.foul != "":
		s.fouls[c] += 1
		ev.returned = ev.pocketed.duplicate()  # undo the shot
		if had_queen:
			ev.returned.append(QUEEN_ID)
		if had_queen or queen_in:
			ev.queen = "returned"
			s.queen = "on_board"
		var penalty := _penalty(s, c, mine)
		if penalty != -1:
			ev.returned.append(penalty)
		return
	s.pocketed[c].append_array(ev.pocketed.filter(func(id): return id != QUEEN_ID))
	if covers:
		s.queen = "covered:%d" % c
		s.pocketed[c].append(QUEEN_ID)
		ev.queen = "covered"
	elif queen_in:
		s.queen = "pending:%d" % c
		ev.queen = "pocketed"
	elif had_queen:
		s.queen = "on_board"
		ev.queen = "returned"
		ev.returned.append(QUEEN_ID)
	for seat in s.colors:
		s.scores[seat] = s.pocketed[seat].size()
	ev.again = not own.is_empty() or queen_in
	if covered:
		for kind in [WHITE, BLACK]:
			if _left(s, kind) == 0:
				_finish_classic(s, 0 if kind == WHITE else 1)


static func _freestyle(s: Dictionary, c: int, ev: Dictionary) -> void:
	var queen_in: bool = QUEEN_ID in ev.pocketed
	var had_queen: bool = s.queen == "pending:%d" % c
	var coins: Array = ev.pocketed.filter(func(id): return id != QUEEN_ID)
	if ev.striker_in:
		ev.foul = "striker"
		s.fouls[c] += 1
		ev.returned = ev.pocketed.duplicate()
		if had_queen:
			ev.returned.append(QUEEN_ID)
		if had_queen or queen_in:
			ev.queen = "returned"
			s.queen = "on_board"
		ev.points = -FOUL_COST
		if not s.pocketed[c].is_empty():
			var back: int = s.pocketed[c].pop_back()
			ev.returned.append(back)
			ev.points -= POINTS[kind_of(back)]
		s.scores[c] += ev.points
		return
	for id in coins:
		ev.points += POINTS[kind_of(id)]
	s.pocketed[c].append_array(coins)
	# the queen needs a cover; when she is the last coin there's nothing to cover her with
	if (queen_in or had_queen) and (not coins.is_empty() or s.pieces.is_empty()):
		s.queen = "covered:%d" % c
		s.pocketed[c].append(QUEEN_ID)
		ev.points += POINTS[QUEEN]
		ev.queen = "covered"
	elif queen_in:
		s.queen = "pending:%d" % c
		ev.queen = "pocketed"
	elif had_queen:
		s.queen = "on_board"
		ev.queen = "returned"
		ev.returned.append(QUEEN_ID)
	s.scores[c] += ev.points
	ev.again = not ev.pocketed.is_empty()
	if s.pieces.is_empty() and ev.returned.is_empty():
		var order: Array = s.colors.duplicate()
		order.sort_custom(func(a, b): return s.scores[a] > s.scores[b] or (s.scores[a] == s.scores[b] and s.fouls[a] < s.fouls[b]))
		s.winners = order
		s.places = range(order.size())
		s.phase = "over"


## Classic penalty: the most recently pocketed man of c's color (whoever pocketed it) comes back.
static func _penalty(s: Dictionary, c: int, kind: int) -> int:
	var best := -1
	var owner := -1
	for seat in s.colors:
		for id in s.pocketed[seat]:
			if kind_of(id) == kind:
				best = id
				owner = seat
	if best == -1:
		return -1
	s.pocketed[owner].erase(best)
	for seat in s.colors:
		s.scores[seat] = s.pocketed[seat].size()
	return best


static func _left(s: Dictionary, kind: int) -> int:
	var n := 0
	for p in s.pieces:
		if p.kind == kind:
			n += 1
	return n


static func _finish_classic(s: Dictionary, team: int) -> void:
	var win: Array = s.colors.filter(func(c): return s.teams[c] == team)
	var lose: Array = s.colors.filter(func(c): return s.teams[c] != team)
	s.winners = win + lose
	s.places = win.map(func(_c): return 0) + lose.map(func(_c): return 1)
	s.phase = "over"


static func next_of(s: Dictionary, c: int) -> int:
	return s.colors[(s.colors.find(c) + 1) % s.colors.size()]


## Coins sent back go to the center, each nudged outward until it touches nothing.
static func place_returned(s: Dictionary, ids: Array) -> void:
	for id in ids:
		var at := _free_spot(s.pieces)
		s.pieces.append({"id": id, "kind": kind_of(id), "x": at.x, "y": at.y})


static func _free_spot(pieces: Array) -> Vector2:
	var reach := Physics.COIN_R * 2 + 0.5
	for ring in 40:
		var r := ring * 6.0
		var steps := maxi(1, ring * 6)
		for k in steps:
			var at := CENTER + Vector2.from_angle(k * TAU / steps) * r
			var free := true
			for p in pieces:
				if Vector2(p.x, p.y).distance_squared_to(at) < reach * reach:
					free = false
					break
			if free:
				return at
	return CENTER


## Stats line for the results screen.
static func stats(s: Dictionary, c: int) -> String:
	if s.variant == "classic":
		var queen := "    Queen ✓" if s.queen == "covered:%d" % c else ""
		return "Coins %d%s    Fouls %d" % [s.pocketed[c].filter(func(id): return id != QUEEN_ID).size(), queen, s.fouls[c]]
	return "Score %d    Fouls %d" % [s.scores[c], s.fouls[c]]
