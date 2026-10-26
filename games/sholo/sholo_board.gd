## Sholo Guti board: framed cream panel with carved lines, point dots and the beads.
## Draws beads from `board` (color per point); a bead in flight is drawn from `flying`.
## Rotated by PI when the local player starts at the top, so they always sit at the bottom.
extends Node2D

const Rules = preload("res://games/sholo/sholo_rules.gd")
const GAP := 150.0  # between grid lines
const BEAD := 50.0

var board := []:
	set(v):
		board = v
		queue_redraw()
var selected := -1:  # point whose bead is picked up
	set(v):
		selected = v
		queue_redraw()
var targets := []:  # points the picked bead can go to
	set(v):
		targets = v
		queue_redraw()
var movable := []:  # points of beads that can move this turn (soft ring)
	set(v):
		movable = v
		queue_redraw()
var flying := {}:  # {color, at (local), scale} for the bead being animated
	set(v):
		flying = v
		queue_redraw()


## Local position of point i (board centered on the origin).
func point_pos(i: int) -> Vector2:
	var p: Vector2i = Rules.points()[i]
	return Vector2((p.x - 2) * GAP, (p.y - 4) * GAP)


## Point under local position `at`, or -1.
func point_at(at: Vector2) -> int:
	var best := -1
	var best_d := GAP * 0.45
	for i in Rules.points().size():
		var d := at.distance_to(point_pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


func _draw() -> void:
	var half := Vector2(2 * GAP + 90, 4 * GAP + 90)
	UI.draw_frame(self, Rect2(-half, half * 2), 14.0, 36)
	var line := Color(UI.INK, 0.55)
	for l in Rules.LINES:
		var a := point_pos(Rules.points().find(l[0]))
		var b := point_pos(Rules.points().find(l[l.size() - 1]))
		draw_line(a, b, line, 7, true)
	for i in Rules.points().size():
		draw_circle(point_pos(i), 13, UI.INK)
	for i in targets:
		draw_circle(point_pos(i), BEAD * 0.7, Color(UI.ACCENT, 0.45))
		draw_circle(point_pos(i), BEAD * 0.32, UI.ACCENT)
	for i in board.size():
		if board[i] == -1:
			continue
		if i in movable and selected == -1:
			draw_arc(point_pos(i), BEAD + 9, 0, TAU, 40, Color(UI.ACCENT, 0.8), 6, true)
		_bead(point_pos(i) + (Vector2(0, -14) if i == selected else Vector2.ZERO), board[i], 1.15 if i == selected else 1.0)
	if not flying.is_empty():
		_bead(flying.at, flying.color, flying.get("scale", 1.0))


## A glossy marble: dark rim, body, highlight. Counter-rotated so the shine stays top-left.
func _bead(at: Vector2, c: int, s: float) -> void:
	var col: Color = UI.COLORS[c]
	var up := Vector2(-1, -1).rotated(-rotation).normalized()
	draw_circle(at - up * 6, BEAD * s, Color(0, 0, 0, 0.18))  # shadow
	draw_circle(at, BEAD * s, col.darkened(0.35))
	draw_circle(at, BEAD * s - 6, col)
	draw_circle(at + up * BEAD * s * 0.35, BEAD * s * 0.28, Color(1, 1, 1, 0.55))
