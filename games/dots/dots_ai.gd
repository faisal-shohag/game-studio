## Dots and Boxes bot: closes any box it can; else draws a line that hands nobody a box;
## else gives away the shortest chain (counted by letting the next player grab greedily).

const Rules = preload("res://games/dots/dots_rules.gd")


static func pick(s: Dictionary) -> int:
	var free := Rules.legal(s)
	free.shuffle()
	for l in free:
		if Rules.line_boxes(l).any(func(b): return Rules.sides(s, b) == 3):
			return l
	var safe := free.filter(func(l): return Rules.line_boxes(l).all(func(b): return Rules.sides(s, b) < 2))
	if not safe.is_empty():
		return safe[0]
	var best: int = free[0]
	var least := INF
	for l in free:
		var t := s.duplicate(true)
		Rules.draw(t, l)
		var given := _grab_all(t)
		if given < least:
			least = given
			best = l
	return best


## Boxes the player now in turn takes by closing every box they can, one after another.
static func _grab_all(t: Dictionary) -> int:
	var n := 0
	var found := true
	while found and t.phase == "draw":
		found = false
		for b in t.boxes.size():
			if t.boxes[b] == -1 and Rules.sides(t, b) == 3:
				for l in Rules.box_lines(b):
					if t.lines[l] == -1:
						n += Rules.draw(t, l).boxes.size()
						found = true
						break
	return n
