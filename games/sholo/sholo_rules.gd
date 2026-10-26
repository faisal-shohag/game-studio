## Pure Sholo Guti (16 beads) rules. No nodes, no UI, no network: state is a plain Dictionary,
## like snakes_rules.gd, so the same code serves bots, pass-and-play and host-authoritative LAN.
##
## 37 points: a 5x5 square with a triangle on the top and bottom, on a 5 x 9 grid (y 0-1 top
## triangle, 2-6 square, 7-8 bottom triangle). Beads move along lines to the next empty point,
## or jump an enemy bead next to them onto the empty point beyond, capturing it. After a capture
## the same bead may keep jumping (phase "chain") or stop. colors[0] starts at the bottom and
## moves first. You win when the other side has no beads or no move; DRAW_MOVES moves in a row
## without a capture is a draw.

const DRAW_MOVES := 60
## Every straight line of the board, point to point in order.
const LINES := [
	[Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)],
	[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
	[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)],
	[Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)],
	[Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
	[Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)],
	[Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6)],
	[Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7)],
	[Vector2i(0, 8), Vector2i(2, 8), Vector2i(4, 8)],
	[Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6)],
	[Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6)],
	[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8)],
	[Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6)],
	[Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6)],
	[Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 4), Vector2i(3, 5), Vector2i(4, 6)],
	[Vector2i(4, 2), Vector2i(3, 3), Vector2i(2, 4), Vector2i(1, 5), Vector2i(0, 6)],
	[Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)],
	[Vector2i(4, 0), Vector2i(3, 1), Vector2i(2, 2), Vector2i(1, 3), Vector2i(0, 4)],
	[Vector2i(0, 8), Vector2i(1, 7), Vector2i(2, 6), Vector2i(3, 5), Vector2i(4, 4)],
	[Vector2i(4, 8), Vector2i(3, 7), Vector2i(2, 6), Vector2i(1, 5), Vector2i(0, 4)],
]

static var _points := []  # Vector2i per point index, sorted top to bottom, left to right
static var _steps := []  # per point: neighbor indices
static var _jumps := []  # per point: [over, to] index pairs


## Point index -> grid spot (x 0..4, y 0..8).
static func points() -> Array:
	_init_board()
	return _points


static func _init_board() -> void:
	if not _points.is_empty():
		return
	for line in LINES:
		for p in line:
			if not p in _points:
				_points.append(p)
	_points.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for i in _points.size():
		_steps.append([])
		_jumps.append([])
	for line in LINES:
		var ids: Array = line.map(func(p): return _points.find(p))
		for k in ids.size():
			for d in [-1, 1]:
				if k + d >= 0 and k + d < ids.size():
					_steps[ids[k]].append(ids[k + d])
				if k + 2 * d >= 0 and k + 2 * d < ids.size():
					_jumps[ids[k]].append([ids[k + d], ids[k + 2 * d]])


static func new_state(colors: Array) -> Dictionary:
	_init_board()
	var board := []
	for p in _points:
		board.append(colors[1] if p.y <= 3 else colors[0] if p.y >= 5 else -1)
	return {
		"colors": colors.duplicate(),
		"board": board,  # color per point, -1 = empty
		"turn": colors[0],
		"phase": "move",  # move | chain | over
		"chain_at": -1,  # the bead that may keep jumping
		"quiet": 0,  # moves since the last capture
		"captured": [0, 0, 0, 0],  # beads taken, per color
		"winners": [],  # [winner], or [] for a draw once over
	}


static func encode(from: int, to: int) -> int:
	return from * 64 + to


static func from_of(m: int) -> int:
	return m / 64


static func to_of(m: int) -> int:
	return m % 64


## Moves for the player in turn (encoded). In a chain: only more jumps by that bead.
static func legal_moves(s: Dictionary) -> Array:
	if s.phase == "chain":
		return _jumps_from(s, s.chain_at)
	if s.phase != "move":
		return []
	return moves_for(s, s.turn)


static func moves_for(s: Dictionary, c: int) -> Array:
	_init_board()
	var out := []
	for i in s.board.size():
		if s.board[i] != c:
			continue
		for j in _steps[i]:
			if s.board[j] == -1:
				out.append(encode(i, j))
		out.append_array(_jumps_from(s, i))
	return out


static func _jumps_from(s: Dictionary, i: int) -> Array:
	_init_board()
	var c: int = s.board[i]
	var out := []
	for j in _jumps[i]:
		if s.board[j[1]] == -1 and s.board[j[0]] != -1 and s.board[j[0]] != c:
			out.append(encode(i, j[1]))
	return out


## The captured point if `m` is a jump, else -1.
static func jumped(m: int) -> int:
	_init_board()
	for j in _jumps[from_of(m)]:
		if j[1] == to_of(m):
			return j[0]
	return -1


## Plays move `m` for the player in turn. Returns {} when illegal (untrusted peers), else
## {color, from, to, over (captured point or -1), chain (may jump again)}.
static func move(s: Dictionary, m: int) -> Dictionary:
	if not m in legal_moves(s):
		return {}
	var c: int = s.turn
	var from := from_of(m)
	var to := to_of(m)
	var over := jumped(m)
	s.board[to] = c
	s.board[from] = -1
	var ev := {"color": c, "from": from, "to": to, "over": over, "chain": false}
	if over != -1:
		s.board[over] = -1
		s.captured[c] += 1
		s.quiet = 0
		if not s.board.has(_other(s, c)):
			_finish(s, [c])
		elif not _jumps_from(s, to).is_empty():
			s.phase = "chain"
			s.chain_at = to
			ev.chain = true
		else:
			_end_turn(s)
	else:
		s.quiet += 1
		_end_turn(s)
	return ev


## Stops a jump chain; the turn passes. False when there's no chain to stop.
static func end_chain(s: Dictionary) -> bool:
	if s.phase != "chain":
		return false
	_end_turn(s)
	return true


static func is_over(s: Dictionary) -> bool:
	return s.phase == "over"


static func left(s: Dictionary, c: int) -> int:
	return s.board.count(c)


static func _other(s: Dictionary, c: int) -> int:
	return s.colors[1] if c == s.colors[0] else s.colors[0]


static func _end_turn(s: Dictionary) -> void:
	var c: int = s.turn
	s.turn = _other(s, c)
	s.phase = "move"
	s.chain_at = -1
	if s.quiet >= DRAW_MOVES:
		_finish(s, [])
	elif moves_for(s, s.turn).is_empty():
		_finish(s, [c])


static func _finish(s: Dictionary, winners: Array) -> void:
	s.phase = "over"
	s.chain_at = -1
	s.winners = winners
