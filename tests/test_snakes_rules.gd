## Run: godot --headless --path . --script tests/test_snakes_rules.gd
extends SceneTree

const Rules = preload("res://games/snakes/snakes_rules.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


func _init() -> void:
	var s := Rules.new_state([0, 2])
	var ev := Rules.roll(s, 3)
	check(ev.kind == "wait" and s.pos[0] == 0 and s.turn == 2, "need a 6 to start, turn passes")

	s = Rules.new_state([0, 2])
	ev = Rules.roll(s, 6)
	check(ev.kind == "start" and s.pos[0] == 1 and s.turn == 0, "6 enters on square 1 + bonus roll")

	s = Rules.new_state([0, 2])
	s.pos[0] = 10
	ev = Rules.roll(s, 2)
	check(ev.kind == "walk" and s.pos[0] == 12 and s.turn == 2, "plain walk, turn passes")

	s = Rules.new_state([0, 2])
	s.pos[0] = 1
	ev = Rules.roll(s, 3)
	check(ev.kind == "ladder" and ev.walk_to == 4 and s.pos[0] == 25, "ladder 4 -> 25")

	s = Rules.new_state([0, 2])
	s.pos[0] = 95
	ev = Rules.roll(s, 4)
	check(ev.kind == "snake" and ev.walk_to == 99 and s.pos[0] == 41, "snake 99 -> 41")

	s = Rules.new_state([0, 2])
	s.pos[0] = 96
	ev = Rules.roll(s, 5)
	check(ev.kind == "stay" and s.pos[0] == 96 and s.turn == 2, "overshoot stays put")

	s = Rules.new_state([0, 2])
	s.pos[0] = 98
	ev = Rules.roll(s, 2)
	check(s.pos[0] == 100 and s.winners == [0] and s.phase == "over", "exact finish wins 2-player game")

	s = Rules.new_state([0, 2])
	s.pos[0] = 94
	Rules.roll(s, 6)
	check(s.pos[0] == 100 and s.phase == "over", "finishing on a 6 ends the game, no bonus roll")

	s = Rules.new_state([0, 1, 2])
	s.pos[0] = 94
	Rules.roll(s, 6)
	check(s.winners == [0] and s.turn == 1 and s.phase == "roll", "winner on a 6 gets no bonus roll")

	s = Rules.new_state([0, 2])
	s.pos[0] = 10
	Rules.roll(s, 6)
	Rules.roll(s, 6)
	ev = Rules.roll(s, 6)
	check(ev.kind == "forfeit" and s.pos[0] == 22 and s.turn == 2, "third 6 forfeits, earlier moves stand")

	s = Rules.new_state([0, 2])
	s.turn = 2
	check(Rules.roll(s, 7).is_empty() and Rules.roll(s, 0).is_empty(), "bad dice values rejected")
	s.phase = "over"
	check(Rules.roll(s, 3).is_empty(), "no rolls after game over")

	s = Rules.new_state([0, 1, 2, 3])
	s.pos = [98, 100, 0, 98]
	s.winners = [1]
	Rules.roll(s, 2)
	check(s.winners == [1, 0] and s.phase == "roll" and s.turn == 2, "4 players: play on for places")

	# Board sanity: jumps stay inside 2..99, nothing chains, ladders go up, snakes go down.
	var starts: Array = Rules.LADDERS.keys() + Rules.SNAKES.keys()
	var ends: Array = Rules.LADDERS.values() + Rules.SNAKES.values()
	check(starts.size() == Rules.LADDERS.size() + Rules.SNAKES.size(), "one jump per square")
	for a in starts:
		check(a > 1 and a < Rules.FINISH, "jump start %d inside board" % a)
	for b in ends:
		check(not b in starts, "jump end %d is not another jump's start" % b)
		check(b > 1 and b < Rules.FINISH, "jump end %d inside board" % b)
	for a in Rules.LADDERS:
		check(Rules.LADDERS[a] > a, "ladder %d goes up" % a)
	for a in Rules.SNAKES:
		check(Rules.SNAKES[a] < a, "snake %d goes down" % a)

	# Random games must always end, with everyone but the last placed.
	var turns_total := 0
	for game in 200:
		s = Rules.new_state([0, 1, 2, 3] if game % 2 == 0 else [1, 3])
		var turns := 0
		while s.phase != "over" and turns < 20000:
			Rules.roll(s, randi_range(1, 6))
			turns += 1
		turns_total += turns
		check(s.phase == "over" and s.winners.size() == s.colors.size() - 1, "random game %d finished" % game)

	print("snakes rules: ", "OK" if fails == 0 else "%d failed" % fails, " (avg %d rolls/game)" % (turns_total / 200))
	quit(1 if fails else 0)
