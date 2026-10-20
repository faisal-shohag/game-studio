## Ludo bot: scores each legal move by simulating it on a copy of the state.

const Rules = preload("res://games/ludo/ludo_rules.gd")


static func pick(s: Dictionary) -> int:
	var moves := Rules.legal_moves(s)
	var best: int = moves[0]
	var best_score := -INF
	for t in moves:
		var sc := _score(s, t)
		if sc > best_score:
			best_score = sc
			best = t
	return best


static func _score(s: Dictionary, t: int) -> float:
	var c: int = s.turn
	var from: int = s.tokens[c][t]
	var sim := s.duplicate(true)
	var ev := Rules.move(sim, t)
	var to: int = ev.to
	var sc := to * 0.5
	if not ev.captured.is_empty():
		sc += 100
	if to == Rules.HOME:
		sc += 80
	if from == -1:
		sc += 60
	if to > Rules.LAST_TRACK and from <= Rules.LAST_TRACK:
		sc += 40
	if Rules.abs_square(c, to) in Rules.SAFE:
		sc += 30
	if _threatened(s, c, from):
		sc += 20
	if _threatened(sim, c, to):
		sc -= 25
	return sc


## True when an opponent sits 1..6 squares behind this token on the shared track.
static func _threatened(s: Dictionary, c: int, progress: int) -> bool:
	var sq := Rules.abs_square(c, progress)
	if sq == -1 or sq in Rules.SAFE:
		return false
	for oc in s.colors:
		if oc == c:
			continue
		for op in s.tokens[oc]:
			var a := Rules.abs_square(oc, op)
			var d := (sq - a + Rules.TRACK_LEN) % Rules.TRACK_LEN
			if a != -1 and d >= 1 and d <= 6:
				return true
	return false
