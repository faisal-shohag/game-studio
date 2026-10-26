## Dots and Boxes board: framed cream panel, dot grid, drawn lines in the drawer's color and
## closed boxes tinted with their owner's. Reads lines and boxes from `state`.
extends Node2D

const Rules = preload("res://games/dots/dots_rules.gd")
const GAP := 180.0
const HIT := 75.0  # how close a tap must be to a line's middle

var state := {}:
	set(v):
		state = v
		queue_redraw()
var last := -1:  # newest line, drawn thicker
	set(v):
		last = v
		queue_redraw()
var grow := {}:  # line being drawn in: {line, color, k 0..1}
	set(v):
		grow = v
		queue_redraw()
var marks := ["", "", "", ""]  # letter shown in each color's boxes (player initials)
var pop := {}:  # box index -> 0..1 fill-in scale
	set(v):
		pop = v
		queue_redraw()


func dot_pos(x: int, y: int) -> Vector2:
	return Vector2((x - Rules.COLS / 2.0) * GAP, (y - Rules.ROWS / 2.0) * GAP)


## Line l's two end dots.
func ends(l: int) -> Array:
	if l < Rules.H:
		var x := l % Rules.COLS
		var y := l / Rules.COLS
		return [dot_pos(x, y), dot_pos(x + 1, y)]
	var x := (l - Rules.H) % (Rules.COLS + 1)
	var y := (l - Rules.H) / (Rules.COLS + 1)
	return [dot_pos(x, y), dot_pos(x, y + 1)]


## Undrawn line nearest local position `at`, or -1 when none is close.
func line_at(at: Vector2) -> int:
	var best := -1
	var best_d := HIT
	for l in Rules.LINES:
		if state.lines[l] != -1:
			continue
		var e := ends(l)
		var d := at.distance_to((e[0] + e[1]) / 2)
		if d < best_d:
			best_d = d
			best = l
	return best


func _draw() -> void:
	var half := Vector2(Rules.COLS, Rules.ROWS) * GAP / 2 + Vector2(70, 70)
	UI.draw_frame(self, Rect2(-half, half * 2), 14.0, 36)
	if state.is_empty():
		return
	for b in state.boxes.size():
		var who: int = state.boxes[b]
		if who == -1:
			continue
		var k: float = pop.get(b, 1.0)
		var tl := dot_pos(b % Rules.COLS, b / Rules.COLS)
		var r := Rect2(tl, Vector2(GAP, GAP)).grow(-10)
		r = Rect2(r.get_center() - r.size * k / 2, r.size * k)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UI.COLORS[who].lightened(0.25)
		fill.set_corner_radius_all(18)
		fill.anti_aliasing = true
		draw_style_box(fill, r)
		draw_string(UI.FONT, r.get_center() + Vector2(-GAP / 2, 24 * k), marks[who], HORIZONTAL_ALIGNMENT_CENTER, GAP, maxi(1, int(70 * k)), Color(UI.INK, 0.5))
	for l in Rules.LINES:
		var c: int = state.lines[l]
		if c == -1:
			draw_line(ends(l)[0], ends(l)[1], Color(UI.INK, 0.08), 6, true)
			continue
		var e := ends(l)
		draw_line(e[0], e[1], UI.COLORS[c].darkened(0.2), 18 if l == last else 13, true)
	if not grow.is_empty():
		var e := ends(grow.line)
		var mid: Vector2 = (e[0] + e[1]) / 2
		draw_line(mid.lerp(e[0], grow.k), mid.lerp(e[1], grow.k), UI.COLORS[grow.color].darkened(0.2), 18, true)
	for y in Rules.ROWS + 1:
		for x in Rules.COLS + 1:
			draw_circle(dot_pos(x, y), 15, UI.INK)
