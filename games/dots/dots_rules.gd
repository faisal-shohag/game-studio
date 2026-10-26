## Pure Dots and Boxes rules. No nodes, no UI, no network: state is a plain Dictionary,
## like snakes_rules.gd, so the same code serves bots, pass-and-play and host-authoritative LAN.
##
## COLS x ROWS boxes. Players take turns drawing one line between two neighboring dots;
## closing a box's fourth side scores it and draws again. Most boxes when the grid is full wins.
## Lines: horizontal first (row y 0..ROWS, x 0..COLS-1), then vertical (row y 0..ROWS-1, x 0..COLS).

const COLS := 5
const ROWS := 6
const H := (ROWS + 1) * COLS  # horizontal line count
const LINES := H + ROWS * (COLS + 1)


static func new_state(colors: Array) -> Dictionary:
	var lines := []
	lines.resize(LINES)
	lines.fill(-1)
	var boxes := []
	boxes.resize(COLS * ROWS)
	boxes.fill(-1)
	return {
		"colors": colors.duplicate(),
		"lines": lines,  # color that drew each line, -1 = not drawn
		"boxes": boxes,  # owner color per box, -1 = open
		"scores": [0, 0, 0, 0],
		"turn": colors[0],
		"phase": "draw",  # draw | over
		"winners": [],  # every color, best first, once over
		"places": [],  # place of each winners entry (ties share)
	}


static func h_line(x: int, y: int) -> int:
	return y * COLS + x


static func v_line(x: int, y: int) -> int:
	return H + y * (COLS + 1) + x


## The four lines round box b: top, bottom, left, right.
static func box_lines(b: int) -> Array:
	var x := b % COLS
	var y := b / COLS
	return [h_line(x, y), h_line(x, y + 1), v_line(x, y), v_line(x + 1, y)]


## Boxes on either side of line l (one or two).
static func line_boxes(l: int) -> Array:
	var out := []
	if l < H:
		var x := l % COLS
		var y := l / COLS
		if y > 0:
			out.append((y - 1) * COLS + x)
		if y < ROWS:
			out.append(y * COLS + x)
	else:
		var x := (l - H) % (COLS + 1)
		var y := (l - H) / (COLS + 1)
		if x > 0:
			out.append(y * COLS + x - 1)
		if x < COLS:
			out.append(y * COLS + x)
	return out


static func sides(s: Dictionary, b: int) -> int:
	return box_lines(b).filter(func(l): return s.lines[l] != -1).size()


static func legal(s: Dictionary) -> Array:
	if s.phase != "draw":
		return []
	var out := []
	for l in LINES:
		if s.lines[l] == -1:
			out.append(l)
	return out


## Draws line l for the player in turn. Returns {} when illegal (untrusted peers), else
## {color, line, boxes (closed box indices)}. Closing a box keeps the turn.
static func draw(s: Dictionary, l: int) -> Dictionary:
	if s.phase != "draw" or l < 0 or l >= LINES or s.lines[l] != -1:
		return {}
	var c: int = s.turn
	s.lines[l] = c
	var closed := []
	for b in line_boxes(l):
		if sides(s, b) == 4:
			s.boxes[b] = c
			closed.append(b)
	s.scores[c] += closed.size()
	if not s.boxes.has(-1):
		_finish(s)
	elif closed.is_empty():
		s.turn = s.colors[(s.colors.find(c) + 1) % s.colors.size()]
	return {"color": c, "line": l, "boxes": closed}


static func _finish(s: Dictionary) -> void:
	s.phase = "over"
	var order: Array = s.colors.duplicate()
	order.sort_custom(func(a, b): return s.scores[a] > s.scores[b])
	s.winners = order
	s.places = []
	for i in order.size():
		s.places.append(s.places[i - 1] if i > 0 and s.scores[order[i]] == s.scores[order[i - 1]] else i)
