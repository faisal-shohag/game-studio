## Pure Ludo rules. No nodes, no UI, no network: state is a plain Dictionary
## so the same code serves bots, pass-and-play and (later) host-authoritative LAN.
##
## Colors: 0 red, 1 green, 2 yellow, 3 blue (clockwise).
## Token progress: -1 base, 0..50 shared track, 51..55 home column, 56 finished.

const TRACK_LEN := 52
const LAST_TRACK := 50
const HOME := 56
const START := [0, 13, 26, 39]
const SAFE := [0, 8, 13, 21, 26, 34, 39, 47]


static func new_state(colors: Array) -> Dictionary:
	var tokens := []
	for c in 4:
		tokens.append([-1, -1, -1, -1])
	return {
		"colors": colors.duplicate(),
		"tokens": tokens,
		"turn": colors[0],
		"dice": 0,
		"sixes": 0,
		"phase": "roll",  # roll | move | over
		"winners": [],
	}


## Square on the shared 52-track, or -1 when token is in base / home column.
static func abs_square(color: int, progress: int) -> int:
	if progress < 0 or progress > LAST_TRACK:
		return -1
	return (START[color] + progress) % TRACK_LEN


static func legal_moves(s: Dictionary) -> Array:
	var out := []
	if s.phase != "move":
		return out
	var t: Array = s.tokens[s.turn]
	for i in 4:
		if t[i] == -1:
			if s.dice == 6:
				out.append(i)
		elif t[i] + s.dice <= HOME:
			out.append(i)
	return out


static func roll(s: Dictionary, value: int) -> void:
	if s.phase != "roll" or value < 1 or value > 6:
		return
	s.dice = value
	s.sixes = s.sixes + 1 if value == 6 else 0
	if s.sixes == 3:
		_next_player(s)
		return
	s.phase = "move"
	if legal_moves(s).is_empty():
		_end_turn(s, value == 6)


## Returns {} when illegal (move intents will come from untrusted peers later).
static func move(s: Dictionary, token: int) -> Dictionary:
	if not token in legal_moves(s):
		return {}
	var c: int = s.turn
	var from: int = s.tokens[c][token]
	var to: int = 0 if from == -1 else from + s.dice
	s.tokens[c][token] = to
	var captured := []
	var sq := abs_square(c, to)
	if sq != -1 and not sq in SAFE:
		for oc in s.colors:
			if oc == c:
				continue
			for j in 4:
				if abs_square(oc, s.tokens[oc][j]) == sq:
					s.tokens[oc][j] = -1
					captured.append([oc, j])
	if to == HOME and s.tokens[c].all(func(p): return p == HOME):
		s.winners.append(c)
	_end_turn(s, s.dice == 6 or to == HOME or not captured.is_empty())
	return {"from": from, "to": to, "captured": captured}


static func is_over(s: Dictionary) -> bool:
	return s.winners.size() >= s.colors.size() - 1


static func _end_turn(s: Dictionary, extra: bool) -> void:
	if is_over(s):
		s.phase = "over"
	elif extra and not s.turn in s.winners:
		s.phase = "roll"
	else:
		_next_player(s)


static func _next_player(s: Dictionary) -> void:
	var i: int = s.colors.find(s.turn)
	while true:
		i = (i + 1) % s.colors.size()
		if not s.colors[i] in s.winners:
			break
	s.turn = s.colors[i]
	s.sixes = 0
	s.phase = "roll"
