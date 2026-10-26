## Carrom board drawn in code: an orange lacquered frame with corner brackets round a honey wood
## surface, deep corner pockets, capsule baselines with colored circles, spear arrows and a compass
## rose in the center; then the coins, the striker and the aim guide on top. Local coordinates are
## board units minus 500, so the playing area spans -500..500 and the node's position is the board
## center. Rotate the node by a quarter turn per seat to put that seat at the bottom.
extends Node2D

const Physics = preload("res://games/carrom/carrom_physics.gd")
const HALF := 500.0
const FRAME := 40.0
const WOOD := Color("d4622e")  # orange lacquer
const WOOD_DARK := Color("9c3d18")
const PLY := Color("eec088")  # honey
const PLY_CENTER := Color("f8dcaa")
const LINE := Color("c8763f")  # board markings: soft orange-brown, so the queen stands out
const RED := Color("d65a33")  # side baseline circles
const BASE_GREEN := Color("7d8c5a")  # top and bottom baseline circles
const IVORY := Color("f4ecd6")
const EBONY := Color("2a201c")
const QUEEN_RED := Color("ff1f4b")
const QUEEN_RIM := Color("f5b82e")  # gold
const STRIKER := Color("e9f0fb")
const KIND_COLORS := [IVORY, EBONY, QUEEN_RED, STRIKER]

## Coins on the board: {id, kind, x, y} in board units (0..1000).
var pieces := []:
	set(v):
		pieces = v
		queue_redraw()
## id -> spin angle (radians), for pieces that rolled about.
var spin := {}
## id -> 0..1 how far a pocketed coin has sunk (shrinks and fades), drawn at its x, y.
var sinking := {}
## The striker: {x, y} in board units, or {} to hide it.
var striker := {}:
	set(v):
		striker = v
		queue_redraw()
var striker_spin := 0.0
var striker_bad := false:  # sits on a coin: drawn red
	set(v):
		striker_bad = v
		queue_redraw()
## Recent striker spots (board units, oldest first), drawn as a fading trail while it flies.
var trail := []
## pocket index -> 0..1 how far through its bulge a net is (a coin just dropped in).
var bulge := {}
## Aim guide: {dir: board direction, power: 0..1, path: board points, ghost: board point or null}.
var aim := {}:
	set(v):
		aim = v
		queue_redraw()
var _grain := []  # [points, color, width] plywood streaks


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # the same wood every game
	for k in 46:
		var y := -HALF + rng.randf() * HALF * 2
		var pts := PackedVector2Array()
		var amp := rng.randf_range(2, 7)
		var freq := rng.randf_range(0.004, 0.012)
		var ph := rng.randf() * TAU
		for i in 41:
			var x := -HALF + i * 25.0
			pts.append(Vector2(x, y + sin(x * freq + ph) * amp))
		_grain.append([pts, Color(0.6, 0.35, 0.12, rng.randf_range(0.04, 0.09)), rng.randf_range(1.5, 4.0)])


## Global position of a board point (follows the node's rotation).
func to_screen(p: Vector2) -> Vector2:
	return to_global(p - Vector2(HALF, HALF))


func to_board(global: Vector2) -> Vector2:
	return to_local(global) + Vector2(HALF, HALF)


func _draw() -> void:
	_draw_frame()
	_draw_markings()
	for k in 4:
		_draw_pocket(Physics.POCKETS[k] - Vector2(HALF, HALF), bulge.get(k, 0.0))
	for p in pieces:
		var at := Vector2(p.x, p.y) - Vector2(HALF, HALF)
		var sink: float = sinking.get(p.id, 0.0)
		draw_piece(self, at, p.kind, spin.get(p.id, 0.0), 1.0 - sink * 0.55, 1.0 - sink * 0.8)
	if not aim.is_empty():
		_draw_aim()
	for i in trail.size():
		var f := (i + 1.0) / (trail.size() + 1.0)
		draw_circle(trail[i] - Vector2(HALF, HALF), Physics.STRIKER_R * (0.35 + 0.55 * f), Color(QUEEN_RIM, 0.3 * f))
	if not striker.is_empty():
		var at := Vector2(striker.x, striker.y) - Vector2(HALF, HALF)
		draw_piece(self, at, Physics.STRIKER, striker_spin, 1.0, 1.0, striker_bad, true)


func _draw_frame() -> void:
	var outer := Rect2(-HALF - FRAME, -HALF - FRAME, (HALF + FRAME) * 2, (HALF + FRAME) * 2)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.35)
	shadow.set_corner_radius_all(26)
	draw_style_box(shadow, outer.grow(6).grow_individual(0, 0, 0, 10))
	var wood := StyleBoxFlat.new()
	wood.bg_color = WOOD
	wood.border_color = WOOD_DARK
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(22)
	wood.anti_aliasing = true
	draw_style_box(wood, outer)
	var sheen := StyleBoxFlat.new()  # lacquer catching the light along the outer edge
	sheen.draw_center = false
	sheen.border_color = Color(1, 0.85, 0.65, 0.3)
	sheen.set_border_width_all(3)
	sheen.set_corner_radius_all(18)
	sheen.anti_aliasing = true
	draw_style_box(sheen, outer.grow(-6))
	_draw_brackets()
	draw_rect(Rect2(-HALF - 12, -HALF - 12, HALF * 2 + 24, HALF * 2 + 24), WOOD_DARK)  # inner step
	draw_rect(Rect2(-HALF - 4, -HALF - 4, HALF * 2 + 8, HALF * 2 + 8), WOOD.darkened(0.45))  # cushion edge
	# honey surface, lighter toward the middle: a fan of triangles with vertex colors
	var n := 64
	for k in n:
		var a := _square_point(k * TAU / n)
		var b := _square_point((k + 1) * TAU / n)
		draw_polygon(PackedVector2Array([Vector2.ZERO, a, b]), PackedColorArray([PLY_CENTER, PLY, PLY]))
	for g in _grain:
		draw_polyline(g[0], g[1], g[2], true)
	# a soft inner shade along the cushions
	for k in 4:
		var xf := Transform2D(k * PI / 2, Vector2.ZERO)
		draw_colored_polygon(PackedVector2Array([xf * Vector2(-HALF, -HALF), xf * Vector2(HALF, -HALF),
			xf * Vector2(HALF - 16, -HALF + 16), xf * Vector2(-HALF + 16, -HALF + 16)]), Color(0.45, 0.2, 0.05, 0.16))


## Where a ray from the center at `angle` meets the playing area's edge.
func _square_point(angle: float) -> Vector2:
	var d := Vector2.from_angle(angle)
	return d * HALF / maxf(absf(d.x), absf(d.y))


## Raised L-shaped plates on the frame corners, each with a little scroll past its ends.
func _draw_brackets() -> void:
	var plate := StyleBoxFlat.new()
	plate.bg_color = WOOD.darkened(0.08)
	plate.border_color = WOOD.lightened(0.25)
	plate.border_width_top = 3
	plate.set_corner_radius_all(8)
	plate.shadow_color = Color(0, 0, 0, 0.25)
	plate.shadow_size = 4
	plate.shadow_offset = Vector2(2, 3)
	plate.anti_aliasing = true
	var e := -HALF - FRAME
	for k in 4:
		draw_set_transform(Vector2.ZERO, k * PI / 2)
		draw_style_box(plate, Rect2(e, e, 150, FRAME - 10))
		draw_style_box(plate, Rect2(e, e, FRAME - 10, 150))
		draw_arc(Vector2(e + 172, e + 15), 7, -PI * 0.2, PI * 1.3, 14, WOOD_DARK, 2.5, true)
		draw_arc(Vector2(e + 183, e + 4), 5, PI * 0.8, PI * 2.3, 12, WOOD_DARK, 2.5, true)
		draw_arc(Vector2(e + 15, e + 172), 7, -PI * 0.2, PI * 1.3, 14, WOOD_DARK, 2.5, true)
		draw_arc(Vector2(e + 4, e + 183), 5, PI * 0.8, PI * 2.3, 12, WOOD_DARK, 2.5, true)
	draw_set_transform(Vector2.ZERO)


func _draw_markings() -> void:
	var outer_line := 1000.0 - 137.0 - HALF
	var inner_line := 1000.0 - 180.0 - HALF
	var mid := (outer_line + inner_line) / 2
	var end := 317.5
	var circle_r := 21.5
	for k in 4:
		var xf := Transform2D(k * PI / 2, Vector2.ZERO)
		# baseline lane: a capsule between the two lines with a colored circle at each end
		var lane := PackedVector2Array()
		for i in 13:
			lane.append(xf * (Vector2(end - circle_r, mid) + Vector2.from_angle(-PI / 2 + i * PI / 12) * circle_r))
		for i in 13:
			lane.append(xf * (Vector2(-end + circle_r, mid) + Vector2.from_angle(PI / 2 + i * PI / 12) * circle_r))
		draw_colored_polygon(lane, Color(1, 0.97, 0.88, 0.3))
		lane.append(lane[0])
		draw_polyline(lane, LINE, 2.5, true)
		var dot: Color = BASE_GREEN if k % 2 == 0 else RED
		for sx in [-1.0, 1.0]:
			var c: Vector2 = xf * Vector2(sx * (end - circle_r), mid)
			draw_circle(c, circle_r - 2, dot.darkened(0.3))
			draw_circle(c, circle_r - 5, dot)
			draw_arc(c, circle_r - 8, PI * 0.9, PI * 1.6, 10, Color(1, 1, 1, 0.3), 2.5, true)
		# diagonal arrow from the middle toward the pocket: fletching, shaft, spear head
		var dirv: Vector2 = xf * Vector2(1, 1).normalized()
		var side := dirv.orthogonal() * 10
		var tail := dirv * 300.0
		var tip := dirv * (HALF * 1.414 - 100)
		draw_line(tail, tip, LINE, 2.5, true)
		draw_colored_polygon(PackedVector2Array([tip + dirv * 16, tip - dirv * 4 + side, tip - dirv * 22, tip - dirv * 4 - side]), LINE)
		for f in [14.0, 26.0]:
			var at: Vector2 = tail + dirv * f
			draw_polyline(PackedVector2Array([at - dirv * 12 + side, at, at - dirv * 12 - side]), LINE, 2.5, true)
	# center: ring with compass ticks, a band of diamonds, and a faceted compass rose
	draw_arc(Vector2.ZERO, 118, 0, TAU, 72, LINE, 2.5, true)
	for k in 8:
		var d := Vector2.from_angle(k * PI / 4 - PI / 2)
		var o := d.orthogonal() * 7
		draw_colored_polygon(PackedVector2Array([d * 134, d * 118 + o, d * 118 - o]), LINE)
	for k in 16:
		var d := Vector2.from_angle((k + 0.5) * PI / 8)
		var c := d * 98
		var o := d.orthogonal() * 3.5
		draw_colored_polygon(PackedVector2Array([c + d * 7, c + o, c - d * 7, c - o]), Color(LINE, 0.75))
	for k in [1, 3, 5, 7, 0, 2, 4, 6]:  # short points first so the long ones lie on top
		var d := Vector2.from_angle(k * PI / 4 - PI / 2)
		var o := d.orthogonal() * (17.0 if k % 2 == 0 else 12.0)
		var tip := d * (88.0 if k % 2 == 0 else 54.0)
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, tip, o]), LINE.lightened(0.3))
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, tip, -o]), LINE)
	draw_circle(Vector2.ZERO, 12, PLY_CENTER)
	draw_arc(Vector2.ZERO, 12, 0, TAU, 24, LINE, 2.0, true)


## A pocket; `bulge` 0..1 swells a dark ring once and lets it settle (sin bump) as a coin drops.
func _draw_pocket(at: Vector2, bulge := 0.0) -> void:
	var r := Physics.POCKET_R + 3
	var swell := sin(bulge * PI) * (1.0 - bulge * 0.5)
	draw_circle(at, r + 6, Color(0.4, 0.18, 0.05, 0.3))  # worn wood round the hole
	draw_circle(at, r + 1, Color("3a1d0e"))
	for i in 4:  # deeper toward the middle, the lip's shadow falling down into it
		draw_circle(at + Vector2(0, i * 1.5), r * (1.0 - i * 0.18), Color("24130a").lerp(Color("050302"), i / 3.0))
	draw_arc(at, r, PI * 0.15, PI * 0.85, 16, Color(1, 0.85, 0.6, 0.3), 2.0, true)
	if swell > 0.0:
		draw_arc(at, r * (0.5 + 0.35 * swell), 0, TAU, 24, Color(0, 0, 0, 0.6 * swell), 5.0, true)


## One carrom piece with its shadow: rim, bevel, a carved flower and a shine. `rot` turns the
## carving (pieces spin while they slide). `glow` puts a gold halo round it (the striker in play).
static func draw_piece(ci: CanvasItem, at: Vector2, kind: int, rot := 0.0, scale := 1.0, alpha := 1.0, bad := false, glow := false) -> void:
	var r := Physics.radius(kind) * scale
	var body: Color = Color("ff5a5a") if bad else KIND_COLORS[kind]
	var rim := body.darkened(0.3)
	var carve := body.darkened(0.2)
	if kind == Physics.BLACK:
		rim = Color("120c0a")
		carve = body.lightened(0.22)
	elif kind == Physics.QUEEN:  # gold rim and white flower: never mistaken for a board marking
		rim = QUEEN_RIM
		carve = Color(1, 1, 1, 0.85)
	if glow:
		ci.draw_circle(at, r + 12 * scale, Color(QUEEN_RIM, 0.2 * alpha))
		ci.draw_arc(at, r + 6 * scale, 0, TAU, 40, Color(QUEEN_RIM, 0.9 * alpha), 3.0 * scale, true)
	ci.draw_circle(at + Vector2(2, 5) * scale, r + 2 * scale, Color(0, 0, 0, 0.12 * alpha))  # soft shadow
	ci.draw_circle(at + Vector2(1.5, 3) * scale, r, Color(0, 0, 0, 0.25 * alpha))
	ci.draw_circle(at, r, Color(rim, alpha))
	ci.draw_circle(at, r - (4.0 if kind == Physics.QUEEN else 2.5) * scale, Color(body, alpha))
	# bevel: lit top-left edge, shaded bottom-right
	ci.draw_arc(at, r - 4 * scale, PI * 0.75, PI * 1.75, 20, Color(1, 1, 1, 0.35 * alpha), 2.0 * scale, true)
	ci.draw_arc(at, r - 4 * scale, -PI * 0.25, PI * 0.75, 20, Color(0, 0, 0, 0.18 * alpha), 2.0 * scale, true)
	if kind == Physics.STRIKER:  # a green and red mandala
		var green := Color("b3122a") if bad else Color("2e8b57")
		var red := Color("d8402f")
		ci.draw_arc(at, r * 0.8, 0, TAU, 36, Color(green.darkened(0.25), alpha), 2.0 * scale, true)
		for k in 8:
			var d := Vector2.from_angle(rot + k * PI / 4)
			ci.draw_circle(at + d * r * 0.42, r * 0.15, Color(green, alpha))  # teardrop petal
			ci.draw_circle(at + d * r * 0.58, r * 0.1, Color(green, alpha))
			ci.draw_circle(at + Vector2.from_angle(rot + (k + 0.5) * PI / 4) * r * 0.66, r * 0.05, Color(red, alpha))
		ci.draw_circle(at, r * 0.24, Color(red, alpha))
		ci.draw_circle(at, r * 0.11, Color(QUEEN_RIM, alpha))
	else:
		ci.draw_arc(at, r * 0.8, 0, TAU, 32, Color(carve, alpha), 1.5 * scale, true)  # groove
		if kind == Physics.BLACK:
			ci.draw_arc(at, r * 0.66, 0, TAU, 28, Color(carve, 0.6 * alpha), 1.5 * scale, true)
		for k in 8:
			ci.draw_circle(at + Vector2.from_angle(rot + k * PI / 4) * r * 0.42, r * 0.13, Color(carve, 0.9 * alpha))
		ci.draw_circle(at, r * 0.22, Color(body, alpha))
		ci.draw_circle(at, r * 0.13, Color(carve, alpha))
	ci.draw_circle(at + Vector2(-r * 0.2, -r * 0.22), r * 0.55, Color(1, 1, 1, 0.08 * alpha))  # shine
	ci.draw_circle(at + Vector2(-r * 0.38, -r * 0.42), r * 0.16, Color(1, 1, 1, 0.35 * alpha))


func _draw_aim() -> void:
	var path: Array = aim.get("path", [])
	var col := Color(1, 1, 1, 0.85)
	for i in path.size() - 1:
		var a: Vector2 = path[i] - Vector2(HALF, HALF)
		var b: Vector2 = path[i + 1] - Vector2(HALF, HALF)
		var len := a.distance_to(b)
		var dirv := (b - a) / maxf(len, 0.001)
		var t := 0.0
		while t < len:  # dashed
			draw_line(a + dirv * t, a + dirv * minf(t + 16, len), Color(col, col.a * (1.0 if i == 0 else 0.55)), 4.0, true)
			t += 28
	var ghost = aim.get("ghost")
	if ghost is Vector2:
		draw_arc(ghost - Vector2(HALF, HALF), Physics.STRIKER_R, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0, true)
	if striker.is_empty():
		return
	var at := Vector2(striker.x, striker.y) - Vector2(HALF, HALF)
	var p: float = aim.get("power", 0.0)
	var ring := Color(1, 1, 1).lerp(UI.COLORS[2], clampf(p * 1.6, 0, 1)).lerp(UI.COLORS[0], clampf(p * 2.5 - 1.5, 0, 1))
	draw_arc(at, Physics.STRIKER_R + 14, 0, TAU, 48, Color(0, 0, 0, 0.25), 9.0, true)
	draw_arc(at, Physics.STRIKER_R + 14, -PI / 2, -PI / 2 + TAU * p, 48, ring, 9.0, true)
