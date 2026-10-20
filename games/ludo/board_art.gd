## Ludo board artwork + geometry. Drawn once; the game rotates this node so the
## local player's base is bottom-left. Local origin = board center.
extends Node2D

const Rules = preload("res://games/ludo/ludo_rules.gd")
const CELL := 66.0
const BASE_CORNER := [Vector2(0, 0), Vector2(9, 0), Vector2(9, 9), Vector2(0, 9)]
const BASE_SPOT := [Vector2(2, 2), Vector2(4, 2), Vector2(2, 4), Vector2(4, 4)]
# [first cell, direction, length]; 52 cells clockwise starting at red's start square
const TRACK_SEGMENTS := [
	[Vector2i(1, 6), Vector2i(1, 0), 5], [Vector2i(6, 5), Vector2i(0, -1), 6], [Vector2i(7, 0), Vector2i(1, 0), 2],
	[Vector2i(8, 1), Vector2i(0, 1), 5], [Vector2i(9, 6), Vector2i(1, 0), 6], [Vector2i(14, 7), Vector2i(0, 1), 2],
	[Vector2i(13, 8), Vector2i(-1, 0), 5], [Vector2i(8, 9), Vector2i(0, 1), 6], [Vector2i(7, 14), Vector2i(-1, 0), 2],
	[Vector2i(6, 13), Vector2i(0, -1), 5], [Vector2i(5, 8), Vector2i(-1, 0), 6], [Vector2i(0, 7), Vector2i(0, -1), 2],
]

var track: Array[Vector2i] = []


func _init() -> void:
	for seg in TRACK_SEGMENTS:
		for k in seg[2]:
			track.append(seg[0] + seg[1] * k)


## Center of grid cell (0..14, 0..14) in board-local pixels.
func cell_center(cell: Vector2) -> Vector2:
	return (cell - Vector2(7, 7)) * CELL


## Board-local center of a token at progress p (i picks the base spot).
func local_pos(c: int, p: int, i := 0) -> Vector2:
	if p == -1:
		return cell_center(BASE_CORNER[c] + BASE_SPOT[i] - Vector2(0.5, 0.5))
	if p <= Rules.LAST_TRACK:
		return cell_center(Vector2(track[Rules.abs_square(c, p)]))
	var entry := Vector2(track[(Rules.START[c] + Rules.LAST_TRACK) % Rules.TRACK_LEN])
	var dir := (Vector2(7, 7) - entry).sign()
	return cell_center(entry + dir * (p - Rules.LAST_TRACK) if p < Rules.HOME else Vector2(7, 7) - dir * 0.9)


func _corner(x: float, y: float) -> Vector2:
	return (Vector2(x, y) - Vector2(7.5, 7.5)) * CELL


func _rounded(color: Color, radius: int, border := Color(0, 0, 0, 0), width := 0, lip := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if width > 0 or lip > 0:
		s.border_color = border
		s.set_border_width_all(width)
		s.border_width_bottom = width + lip
	return s


func _square(at: Vector2) -> Rect2:
	return Rect2(at - Vector2(CELL, CELL) / 2, Vector2(CELL, CELL)).grow(-2)


func _draw() -> void:
	var board := Rect2(_corner(0, 0), Vector2(15, 15) * CELL)
	draw_style_box(_rounded(Color(0, 0, 0, 0.3), 50), Rect2(board.position + Vector2(0, 22), board.size).grow(18))
	draw_style_box(_rounded(UI.INK, 50), board.grow(18))
	draw_style_box(_rounded(Color("f4f1ff"), 32), board.grow(4))

	var cell := _rounded(Color.WHITE, 12, Color("dcd6f7"), 2)
	for sq in track:
		draw_style_box(cell, _square(cell_center(Vector2(sq))))
	for c in 4:
		var col: Color = UI.COLORS[c]
		var painted := _rounded(col, 12, col.darkened(0.2), 2)
		for p in range(Rules.LAST_TRACK + 1, Rules.HOME):
			draw_style_box(painted, _square(local_pos(c, p)))
		var start := Vector2(track[Rules.START[c]])
		draw_style_box(painted, _square(cell_center(start)))
		_arrow(cell_center(start), (Vector2(track[Rules.START[c] + 1]) - start).normalized(), Color.WHITE)
		# base: colored block, white yard, 4 sunken slots
		var corner: Vector2 = BASE_CORNER[c]
		var base := Rect2(_corner(corner.x, corner.y), Vector2(6, 6) * CELL).grow(-5)
		draw_style_box(_rounded(col, 30, col.darkened(0.25), 0, 10), base)
		draw_style_box(_rounded(Color.WHITE, 24, Color("dcd6f7"), 0, 6), base.grow(-CELL * 0.8))
		for spot in BASE_SPOT:
			var at := cell_center(corner + spot - Vector2(0.5, 0.5))
			draw_circle(at, CELL * 0.44, col.darkened(0.2))
			draw_circle(at + Vector2(0, 3), CELL * 0.38, col.lightened(0.55))
	for sq in Rules.SAFE:
		if not sq in Rules.START:
			_star(cell_center(Vector2(track[sq])), CELL * 0.33, Color("cfc8f2"))

	# home: four triangles meeting at a gold star
	var a := _corner(6, 6)
	var b := _corner(9, 6)
	var d := _corner(9, 9)
	var e := _corner(6, 9)
	var tris := [[a, e], [a, b], [b, d], [e, d]]  # red left, green top, yellow right, blue bottom
	for c in 4:
		var t := PackedVector2Array([tris[c][0], tris[c][1], Vector2.ZERO])
		draw_colored_polygon(t, UI.COLORS[c])
		t.append(t[0])
		draw_polyline(t, Color.WHITE, 3, true)
	draw_circle(Vector2.ZERO, CELL * 0.62, UI.INK)
	draw_circle(Vector2.ZERO, CELL * 0.55, Color.WHITE)
	_star(Vector2.ZERO, CELL * 0.42, UI.COLORS[2])


func _star(center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var rad := r if k % 2 == 0 else r * 0.45
		pts.append(center + Vector2.from_angle(-PI / 2 + k * PI / 5) * rad)
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, color.darkened(0.35), 2.5, true)


func _arrow(center: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([center + dir * CELL * 0.26,
		center - dir * CELL * 0.14 + side * CELL * 0.22, center - dir * CELL * 0.14 - side * CELL * 0.22]), color)
