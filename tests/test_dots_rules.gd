## Run: godot --headless --path . --script tests/test_dots_rules.gd
extends SceneTree

const Rules = preload("res://games/dots/dots_rules.gd")
const AI = preload("res://games/dots/dots_ai.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


func _init() -> void:
	var s := Rules.new_state([0, 2])
	check(Rules.legal(s).size() == Rules.LINES and Rules.LINES == 71, "71 lines on a 5x6 grid")
	var ok := true
	for b in Rules.COLS * Rules.ROWS:
		for l in Rules.box_lines(b):
			ok = ok and b in Rules.line_boxes(l)
	check(ok, "box_lines and line_boxes agree")
	check(Rules.line_boxes(Rules.h_line(0, 0)) == [0] and Rules.line_boxes(Rules.v_line(1, 0)) == [0, 1], "edge lines have one box, inner two")

	# plain line passes the turn, repeat is illegal
	var ev := Rules.draw(s, Rules.h_line(0, 0))
	check(ev.boxes.is_empty() and s.turn == 2, "plain line passes turn")
	check(Rules.draw(s, Rules.h_line(0, 0)).is_empty(), "same line twice is illegal")
	check(Rules.draw(s, -1).is_empty() and Rules.draw(s, Rules.LINES).is_empty(), "out of range is illegal")

	# closing a box scores and keeps the turn
	s = Rules.new_state([0, 2])
	for l in [Rules.h_line(0, 0), Rules.h_line(0, 1), Rules.v_line(0, 0)]:
		s.lines[l] = 2
	ev = Rules.draw(s, Rules.v_line(1, 0))
	check(ev.boxes == [0] and s.boxes[0] == 0 and s.scores[0] == 1 and s.turn == 0, "box closed, scored, turn kept")

	# one line closes two boxes
	s = Rules.new_state([0, 2])
	for b in [0, 1]:
		for l in Rules.box_lines(b):
			s.lines[l] = 2
	var mid := Rules.v_line(1, 0)
	s.lines[mid] = -1
	ev = Rules.draw(s, mid)
	check(ev.boxes.size() == 2 and s.scores[0] == 2, "one line closes two boxes")

	# full grid ends, ties share a place
	s = Rules.new_state([0, 1, 2])
	for l in Rules.LINES - 1:
		s.lines[l] = 0
	for b in s.boxes.size():
		s.boxes[b] = 0 if b < 10 else 1 if b < 20 else 2
	s.boxes[29] = -1
	s.scores = [10, 10, 9, 0]
	s.turn = 2
	Rules.draw(s, Rules.LINES - 1)
	check(s.phase == "over" and s.scores[2] == 10, "last line ends the game")
	check(s.places == [0, 0, 0], "three-way tie shares 1st")

	# bots finish a game
	for g in 10:
		s = Rules.new_state([0, 1, 2, 3])
		for k in 500:
			if s.phase == "over":
				break
			check(not Rules.draw(s, AI.pick(s)).is_empty(), "bot line legal")
		check(s.phase == "over" and s.scores.reduce(func(a, b): return a + b) == 30, "bot game ends with every box owned")

	# bot takes a free box and avoids handing one over
	s = Rules.new_state([0, 2])
	for l in [Rules.h_line(0, 0), Rules.h_line(0, 1), Rules.v_line(0, 0)]:
		s.lines[l] = 2
	check(AI.pick(s) == Rules.v_line(1, 0), "bot closes the open box")

	print("dots rules: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
