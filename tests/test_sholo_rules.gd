## Run: godot --headless --path . --script tests/test_sholo_rules.gd
extends SceneTree

const Rules = preload("res://games/sholo/sholo_rules.gd")
const AI = preload("res://games/sholo/sholo_ai.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


func at(x: int, y: int) -> int:
	return Rules.points().find(Vector2i(x, y))


func empty_state() -> Dictionary:
	var s := Rules.new_state([0, 2])
	s.board.fill(-1)
	return s


func _init() -> void:
	var s := Rules.new_state([0, 2])
	check(Rules.points().size() == 37, "37 points")
	check(Rules.left(s, 0) == 16 and Rules.left(s, 2) == 16, "16 beads each")
	check(s.board[at(2, 4)] == -1 and s.board[at(0, 4)] == -1, "middle row empty")
	var ok := true
	for i in 37:
		for m in Rules.moves_for(empty_state_with(i), 0):
			ok = ok and Rules.to_of(m) != i
	check(ok, "no step onto itself")
	# opening: bottom moves first, only into the middle row
	var opening := Rules.legal_moves(s)
	check(opening.size() > 0 and opening.all(func(m): return Rules.points()[Rules.to_of(m)].y == 4), "opening moves land in the middle row")
	check(s.turn == 0, "bottom moves first")

	# step passes the turn
	var m := Rules.encode(at(2, 5), at(2, 4))
	var ev := Rules.move(s, m)
	check(not ev.is_empty() and ev.over == -1 and s.turn == 2 and s.quiet == 1, "step passes turn")
	check(Rules.move(s, m).is_empty(), "moving the other side's bead is illegal")

	# capture and chain
	s = empty_state()
	s.board[at(2, 6)] = 0
	s.board[at(2, 5)] = 2
	s.board[at(2, 3)] = 2
	s.board[at(0, 0)] = 2  # keeps 2 alive after the chain
	ev = Rules.move(s, Rules.encode(at(2, 6), at(2, 4)))
	check(ev.over == at(2, 5) and s.board[at(2, 5)] == -1 and ev.chain and s.phase == "chain" and s.turn == 0, "jump captures, chain offered")
	check(Rules.legal_moves(s) == [Rules.encode(at(2, 4), at(2, 2))], "chain: only that bead's jumps")
	ev = Rules.move(s, Rules.encode(at(2, 4), at(2, 2)))
	check(ev.over == at(2, 3) and s.captured[0] == 2 and s.turn == 2 and s.phase == "move", "second jump, chain ends, turn passes")

	# stopping a chain
	s = empty_state()
	s.board[at(2, 6)] = 0
	s.board[at(2, 5)] = 2
	s.board[at(2, 3)] = 2
	s.board[at(4, 0)] = 2
	Rules.move(s, Rules.encode(at(2, 6), at(2, 4)))
	check(Rules.end_chain(s) and s.turn == 2 and s.phase == "move", "end chain passes turn")
	check(not Rules.end_chain(s), "no chain to end")

	# triangle row jump: (0,0) over (2,0) to (4,0)
	s = empty_state()
	s.board[at(0, 0)] = 0
	s.board[at(2, 0)] = 2
	s.board[at(4, 4)] = 2
	check(Rules.encode(at(0, 0), at(4, 0)) in Rules.legal_moves(s), "jump along triangle row")

	# no diagonal from an odd point
	s = empty_state()
	s.board[at(1, 4)] = 0
	s.board[at(4, 0)] = 2
	check(not Rules.encode(at(1, 4), at(0, 3)) in Rules.legal_moves(s), "no diagonal on odd point")

	# last bead taken wins
	s = empty_state()
	s.board[at(2, 6)] = 0
	s.board[at(2, 5)] = 2
	Rules.move(s, Rules.encode(at(2, 6), at(2, 4)))
	check(s.phase == "over" and s.winners == [0], "capturing the last bead wins")

	# blocked side loses
	s = empty_state()
	s.board[at(0, 0)] = 2
	s.board[at(2, 0)] = 0
	s.board[at(1, 1)] = 0
	s.board[at(4, 0)] = 0
	s.board[at(2, 2)] = 0
	s.board[at(4, 8)] = 0
	Rules.move(s, Rules.encode(at(4, 8), at(3, 7)))
	check(s.phase == "over" and s.winners == [0], "no move left loses")

	# quiet moves draw
	s = Rules.new_state([0, 2])
	s.quiet = Rules.DRAW_MOVES - 1
	Rules.move(s, Rules.legal_moves(s)[0])
	check(s.phase == "over" and s.winners.is_empty(), "draw after quiet moves")

	# bots finish a game
	var games := 0
	for g in 20:
		s = Rules.new_state([0, 2])
		for k in 2000:
			if s.phase == "over":
				break
			var pick := AI.pick(s)
			if pick == -1:
				check(Rules.end_chain(s), "bot -1 only to stop a chain")
			else:
				check(not Rules.move(s, pick).is_empty(), "bot move legal")
		games += 1 if s.phase == "over" else 0
	check(games == 20, "bot games end")

	print("sholo rules: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)


## One bead of color 0 on point i, nothing else.
func empty_state_with(i: int) -> Dictionary:
	var s := empty_state()
	s.board[i] = 0
	return s
