## Snakes & Ladders board, drawn in code: 10x10 checkered squares numbered back and forth
## (1 bottom-left, 100 top-left), wooden ladders and curvy striped snakes.
## Origin = board center. Waiting pawns (position 0) stand on their player's card, not on the board.
extends Node2D

const Rules = preload("res://games/snakes/snakes_rules.gd")
const CELL := 102.0
const HALF := CELL * 5  # board is 1020 x 1020
const TILES := [Color("fff5e4"), Color("fbe3c2"), Color("fdebd8"), Color("f7d3bd"), Color("fdf2cf"), Color("f4dfa6")]
const WOOD := Color("c98b4b")
const SNAKE_COLORS := [Color("6cc551"), Color("ff7a9c"), Color("a77be0"), Color("f59a3c"), Color("4aa3ff")]


## Center of square n (1..100) in board coords.
func square_pos(n: int) -> Vector2:
	var row := (n - 1) / 10
	var col := (n - 1) % 10
	if row % 2 == 1:
		col = 9 - col
	return Vector2(-HALF + CELL * (col + 0.5), HALF - CELL * (row + 0.5))


## Points along a snake's body from head to tail, for drawing (and sliding pawns along it).
func snake_path(head: int) -> PackedVector2Array:
	var a := square_pos(head)
	var b := square_pos(Rules.SNAKES[head])
	var d := b - a
	var side := d.orthogonal().normalized() * clampf(d.length() * 0.28, 50.0, 110.0)
	if head % 2 == 0:
		side = -side
	var c1 := a + d * 0.33 + side
	var c2 := a + d * 0.66 - side
	var pts := PackedVector2Array()
	var n := maxi(60, int(d.length() / 5))  # dense, so the round segments read as one smooth body
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		pts.append(a * u * u * u + c1 * 3 * u * u * t + c2 * 3 * u * t * t + b * t * t * t)
	return pts


## Direction a snake's head faces (away from its body).
static func head_dir(pts: PackedVector2Array) -> Vector2:
	return (pts[0] - pts[6]).normalized()


## Forked tongues that flick out now and then. Its own node, so only these few lines
## redraw each frame, not the whole board.
class Tongues extends Node2D:
	const FLICK := 0.45  # seconds out and back
	var heads := []  # [at, fwd, next flick time]

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		for h in heads:
			if t > h[2] + FLICK:
				h[2] = t + randf_range(1.5, 4.5)
			var k: float = (t - h[2]) / FLICK
			if k < 0.0:
				continue
			var out := sin(k * PI) * 22.0
			var fwd: Vector2 = h[1].rotated(sin(t * 40.0) * 0.12)  # quick flutter
			var side := fwd.orthogonal()
			var base: Vector2 = h[0] + h[1] * 20
			var tip := base + fwd * out
			draw_line(base, tip, Color("ff4757"), 4, true)
			draw_line(tip, tip + (fwd + side * 0.6).normalized() * out * 0.4, Color("ff4757"), 3, true)
			draw_line(tip, tip + (fwd - side * 0.6).normalized() * out * 0.4, Color("ff4757"), 3, true)


func _ready() -> void:
	var tongues := Tongues.new()
	var t := Time.get_ticks_msec() / 1000.0
	for head in Rules.SNAKES:
		var pts := snake_path(head)
		tongues.heads.append([pts[0], head_dir(pts), t + randf_range(0.3, 4.0)])
	add_child(tongues)


func _draw() -> void:
	# frame + squares
	UI.draw_frame(self, Rect2(-HALF - 18, -HALF - 18, HALF * 2 + 36, HALF * 2 + 36), 14.0, 36)
	for n in range(1, Rules.FINISH + 1):
		var p := square_pos(n)
		var row := (n - 1) / 10
		var tint: Color = TILES[(row / 2 % 3) * 2 + (n % 2)]
		draw_rect(Rect2(p - Vector2(CELL, CELL) / 2, Vector2(CELL, CELL)), tint)
		var text := str(n)
		draw_string(UI.FONT, p + Vector2(-CELL / 2 + 8, -CELL / 2 + 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(UI.INK, 0.45))
	_draw_goal(square_pos(Rules.FINISH))
	for foot in Rules.LADDERS:
		_draw_ladder(square_pos(foot), square_pos(Rules.LADDERS[foot]))
	var k := 0
	for head in Rules.SNAKES:
		_draw_snake(snake_path(head), SNAKE_COLORS[k % SNAKE_COLORS.size()])
		k += 1


func _draw_goal(p: Vector2) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		pts.append(p + Vector2(0, 6) + Vector2.from_angle(-PI / 2 + k * PI / 5) * (34.0 if k % 2 == 0 else 15.0))
	draw_colored_polygon(pts, UI.COLORS[2])
	pts.append(pts[0])
	draw_polyline(pts, UI.INK, 4, true)


func _draw_ladder(a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var side := dir.orthogonal() * 17.0
	a -= dir * 18
	b += dir * 18
	var len := a.distance_to(b)
	for pass_ in 2:  # outline first, wood on top
		var w := 13.0 if pass_ == 0 else 7.0
		var col: Color = UI.INK if pass_ == 0 else WOOD
		var rung := 22.0
		while rung < len - 8:
			var m := a + dir * rung
			draw_line(m - side, m + side, col, w - 2, true)
			rung += 30.0
		draw_line(a - side, b - side, col, w, true)
		draw_line(a + side, b + side, col, w, true)
	draw_line(a - side * 1.15 + dir * 4, b - side * 1.15, WOOD.lightened(0.35), 2.5, true)


func _draw_snake(pts: PackedVector2Array, color: Color) -> void:
	var n := pts.size()
	var r := func(i: int) -> float: return lerpf(17.0, 6.0, float(i) / (n - 1))
	for i in range(n - 1, -1, -1):  # outline pass, tail first so the head sits on top
		draw_circle(pts[i], r.call(i) + 4, UI.INK)
	for i in range(n - 1, -1, -1):
		var stripe := (i / 8) % 2 == 0
		draw_circle(pts[i], r.call(i), color if stripe else color.darkened(0.25))
	for i in range(n - 1, 0, -6):  # belly shine
		draw_circle(pts[i] + Vector2(-3, -3), r.call(i) * 0.35, Color(1, 1, 1, 0.25))
	# head: wider, eyes looking away from the body (the tongue is animated by Tongues)
	var head := pts[0]
	var fwd := head_dir(pts)
	var side := fwd.orthogonal()
	draw_circle(head, 25, UI.INK)
	draw_circle(head, 21, color)
	for s in [-1, 1]:
		var eye: Vector2 = head + side * 9 * s + fwd * 6
		draw_circle(eye, 7, Color.WHITE)
		draw_circle(eye + fwd * 2, 3.5, UI.INK)
