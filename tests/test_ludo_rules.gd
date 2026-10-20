## Run: godot --headless --path . --script tests/test_ludo_rules.gd
extends SceneTree

const Rules = preload("res://games/ludo/ludo_rules.gd")
const AI = preload("res://games/ludo/ludo_ai.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


func _init() -> void:
	var s := Rules.new_state([0, 2])
	Rules.roll(s, 3)
	check(s.turn == 2 and s.phase == "roll", "need 6 to leave base, turn passes")

	s = Rules.new_state([0, 2])
	Rules.roll(s, 6)
	check(Rules.legal_moves(s) == [0, 1, 2, 3], "6 frees any token")
	Rules.move(s, 0)
	check(s.tokens[0][0] == 0 and s.turn == 0 and s.phase == "roll", "leave base + extra turn on 6")

	s = Rules.new_state([0, 2])
	s.tokens[0][0] = 4
	s.tokens[2][0] = 32  # yellow abs (26+32)%52 = 6
	Rules.roll(s, 2)
	var ev := Rules.move(s, 0)
	check(ev.captured == [[2, 0]] and s.tokens[2][0] == -1, "capture sends home")
	check(s.turn == 0, "capture gives extra turn")

	s = Rules.new_state([0, 2])
	s.tokens[0][0] = 4
	s.tokens[2][0] = 34  # yellow abs 8 = star
	Rules.roll(s, 4)
	Rules.move(s, 0)
	check(s.tokens[2][0] == 34 and s.turn == 2, "no capture on safe square")

	s = Rules.new_state([0, 2])
	s.tokens[0][0] = 54
	Rules.roll(s, 3)
	check(s.turn == 2, "overshoot home is illegal")
	s.turn = 0
	Rules.roll(s, 2)
	Rules.move(s, 0)
	check(s.tokens[0][0] == Rules.HOME and s.turn == 0, "exact finish + extra turn")

	s = Rules.new_state([0, 2])
	s.tokens[0][0] = 0
	Rules.roll(s, 6); Rules.move(s, 0)
	Rules.roll(s, 6); Rules.move(s, 0)
	Rules.roll(s, 6)
	check(s.turn == 2 and s.tokens[0][0] == 12, "third six forfeits turn")

	s = Rules.new_state([0, 2])
	s.tokens[0] = [56, 56, 56, 55]
	Rules.roll(s, 1)
	Rules.move(s, 3)
	check(s.winners == [0] and s.phase == "over", "win ends 2-player game")

	s = Rules.new_state([0, 2])
	check(Rules.move(s, 0).is_empty(), "illegal move rejected")

	s = Rules.new_state([0, 2])
	s.tokens[0] = [4, 20, -1, -1]
	s.tokens[2][0] = 32  # capturable from token 0 with a 2
	Rules.roll(s, 2)
	check(AI.pick(s) == 0, "AI prefers capture")

	# Full bot game must always end.
	for game in 50:
		s = Rules.new_state([0, 1, 2, 3])
		var turns := 0
		while s.phase != "over" and turns < 5000:
			if s.phase == "roll":
				Rules.roll(s, randi_range(1, 6))
			else:
				Rules.move(s, AI.pick(s))
			turns += 1
		check(s.phase == "over", "bot game %d finished" % game)

	print("ludo rules: ", "OK" if fails == 0 else "%d failed" % fails)
	quit(1 if fails else 0)
