## Sholo Guti bot: three plies of captures. Scores each move by beads it takes, minus the most the
## other side can take next turn, plus what it can take back; then favors moves that threaten jumps and push forward.

const Rules = preload("res://games/sholo/sholo_rules.gd")


## A legal move for the player in turn, or -1 to stop a jump chain.
static func pick(s: Dictionary) -> int:
	var moves := Rules.legal_moves(s)
	if moves.is_empty():
		return -1
	var c: int = s.turn
	var them: int = s.colors[1] if c == s.colors[0] else s.colors[0]
	var risk := 9.0 if s.quiet < 16 else 6.0  # a long standoff: accept trades to break it
	var best := -1
	var best_score := -INF
	for m in moves:
		var t := s.duplicate(true)
		Rules.move(t, m)
		_greedy_chain(t)
		var score: float = (t.captured[c] - s.captured[c]) * 10.0 + randf()
		if t.phase == "over":
			score += 1000.0 if c in t.winners else -20.0
		else:
			var reply := _best_take(t, them)
			score -= reply[0] * risk
			if reply[0] > 0:
				score += _best_take(reply[1], c)[0] * risk * 0.8  # we take back
			score += Rules.moves_for(t, c).filter(func(o): return Rules.jumped(o) != -1).size() * 1.5
			var dy: int = Rules.points()[Rules.to_of(m)].y - Rules.points()[Rules.from_of(m)].y
			score += 1.5 * (dy if c == s.colors[1] else -dy)  # colors[1] heads down the board
			if s.quiet >= 16 or Rules.left(s, c) > Rules.left(s, them):  # hunt the beads that are left
				score -= 0.8 * _nearest(t, Rules.to_of(m), them)
		if score > best_score:
			best_score = score
			best = m
	if s.phase == "chain" and best_score < 0.0:
		return -1  # jumping on would only walk into a bigger loss
	return best


## Most beads `who` can take in one turn on `t` (a jump plus its greedy chain), and the board after.
static func _best_take(t: Dictionary, who: int) -> Array:
	var best := [0, t]
	var u := t.duplicate(true)
	u.turn = who
	u.phase = "move"
	for m in Rules.moves_for(u, who):
		if Rules.jumped(m) == -1:
			continue
		var v := u.duplicate(true)
		Rules.move(v, m)
		_greedy_chain(v)
		if v.captured[who] - u.captured[who] > best[0]:
			best = [v.captured[who] - u.captured[who], v]
	return best


static func _greedy_chain(t: Dictionary) -> void:
	while t.phase == "chain":
		Rules.move(t, Rules.legal_moves(t)[0])


## Grid distance from point i to the closest bead of `who`.
static func _nearest(t: Dictionary, i: int, who: int) -> float:
	var at: Vector2i = Rules.points()[i]
	var best := INF
	for j in t.board.size():
		if t.board[j] == who:
			best = minf(best, Vector2(Rules.points()[j] - at).length())
	return best
