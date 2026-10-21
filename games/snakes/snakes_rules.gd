## Pure Snakes & Ladders rules. No nodes, no UI, no network: state is a plain Dictionary,
## like ludo_rules.gd, so the same code serves bots, pass-and-play and host-authoritative LAN.
##
## One pawn per color. Position 0 = waiting off the board, 1..100 = squares.
## A 6 is needed to enter (onto square 1), a 6 rolls again, three 6s end the turn,
## and the finish needs an exact roll (too high = stay put). There is no move choice:
## a roll plays the whole turn.

const FINISH := 100
const LADDERS := {4: 25, 13: 46, 33: 49, 42: 63, 50: 69, 62: 81, 74: 92}
const SNAKES := {27: 5, 40: 3, 43: 18, 54: 31, 66: 45, 76: 58, 89: 53, 97: 61, 99: 41}


static func new_state(colors: Array) -> Dictionary:
	return {
		"colors": colors.duplicate(),
		"pos": [0, 0, 0, 0],
		"turn": colors[0],
		"dice": 0,
		"sixes": 0,
		"phase": "roll",  # roll | over
		"winners": [],
	}


## Plays one roll for the player in turn. Returns {} when illegal (untrusted peers), else
## {color, from, walk_to, to, kind}: the pawn walks from -> walk_to, then a ladder/snake takes it to `to`.
## kind: start | wait (needs a 6) | stay (too high) | walk | ladder | snake | forfeit (third 6)
static func roll(s: Dictionary, value: int) -> Dictionary:
	if s.phase != "roll" or value < 1 or value > 6:
		return {}
	var c: int = s.turn
	var from: int = s.pos[c]
	var ev := {"color": c, "from": from, "walk_to": from, "to": from, "kind": "stay"}
	s.dice = value
	s.sixes = s.sixes + 1 if value == 6 else 0
	if s.sixes == 3:
		ev.kind = "forfeit"
		_next_player(s)
		return ev
	if from == 0:
		if value != 6:
			ev.kind = "wait"
		else:
			ev.kind = "start"
			ev.walk_to = 1
			ev.to = 1
	elif from + value <= FINISH:
		ev.walk_to = from + value
		ev.to = LADDERS.get(ev.walk_to, SNAKES.get(ev.walk_to, ev.walk_to))
		ev.kind = "ladder" if ev.walk_to in LADDERS else "snake" if ev.walk_to in SNAKES else "walk"
	s.pos[c] = ev.to
	if ev.to == FINISH:
		s.winners.append(c)
	_end_turn(s, value == 6)
	return ev


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
