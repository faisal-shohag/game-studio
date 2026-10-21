## Carrom board drawn in code: a thick wooden frame round a light plywood surface, corner pockets
## with nets, baselines with red circles, diagonal arrows and the center rosette; then the coins,
## the striker and the aim guide on top. Local coordinates are board units minus 500, so the
## playing area spans -500..500 and the node's position is the board center. Rotate the node by
## a quarter turn per seat to put that seat at the bottom.
extends Node2D

const Physics = preload("res://games/carrom/carrom_physics.gd")
const HALF := 500.0
const FRAME := 40.0
const WOOD := Color("6b3a1f")
const WOOD_DARK := Color("4a2512")
const PLY := Color("f2dcaa")
const LINE := Color("3b2414")
const RED := Color("c8283a")
const IVORY := Color("f4ecd6")
const EBONY := Color("2a201c")
const QUEEN_RED := Color("d7263d")
const STRIKER := Color("e9f0fb")
const STRIKER_RING := Color("2f6bd8")
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
var _frame_grain := []


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
		_grain.append([pts, Color(0.55, 0.36, 0.16, rng.randf_range(0.05, 0.13)), rng.randf_range(1.5, 4.0)])
	for side in 4:
		for k in 7:
			var off := rng.randf_range(4, FRAME - 4)
			var col := WOOD_DARK.lerp(Color("8a4d27"), rng.randf())
			_frame_grain.append([side, off, col, rng.randf_range(1.5, 4.0)])


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
		draw_circle(trail[i] - Vector2(HALF, HALF), Physics.STRIKER_R * (0.35 + 0.55 * f), Color(STRIKER_RING.lightened(0.4), 0.28 * f))
	if not striker.is_empty():
		var at := Vector2(striker.x, striker.y) - Vector2(HALF, HALF)
		draw_piece(self, at, Physics.STRIKER, striker_spin, 1.0, 1.0, striker_bad)


func _draw_frame() -> void:
	var outer := Rect2(-HALF - FRAME, -HALF - FRAME, (HALF + FRAME) * 2, (HALF + FRAME) * 2)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.35)
	shadow.set_corner_radius_all(26)
	draw_style_box(shadow, outer.grow(6).grow_individual(0, 0, 0, 10))
	var wood := StyleBoxFlat.new()
	wood.bg_color = WOOD
	wood.set_corner_radius_all(22)
	wood.anti_aliasing = true
	draw_style_box(wood, outer)
	for g in _frame_grain:  # grain bands running along each side
		var off: float = -HALF - FRAME + g[1]
		var a := Vector2(-HALF - FRAME + 18, off)
		var b := Vector2(HALF + FRAME - 18, off)
		var xf := Transform2D(g[0] * PI / 2, Vector2.ZERO)
		draw_line(xf * a, xf * b, g[2], g[3])
	draw_rect(Rect2(-HALF - 5, -HALF - 5, HALF * 2 + 10, HALF * 2 + 10), WOOD_DARK)  # cushion edge
	draw_rect(Rect2(-HALF, -HALF, HALF * 2, HALF * 2), PLY)
	for g in _grain:
		draw_polyline(g[0], g[1], g[2], true)
	# a soft inner shade along the cushions
	for k in 4:
		var xf := Transform2D(k * PI / 2, Vector2.ZERO)
		draw_colored_polygon(PackedVector2Array([xf * Vector2(-HALF, -HALF), xf * Vector2(HALF, -HALF),
			xf * Vector2(HALF - 14, -HALF + 14), xf * Vector2(-HALF + 14, -HALF + 14)]), Color(0.35, 0.2, 0.08, 0.12))


func _draw_markings() -> void:
	var outer_line := 1000.0 - 137.0 - HALF
	var inner_line := 1000.0 - 180.0 - HALF
	var end := 317.5
	var circle_r := 21.5
	for k in 4:
		var xf := Transform2D(k * PI / 2, Vector2.ZERO)
		draw_line(xf * Vector2(-end + circle_r, outer_line), xf * Vector2(end - circle_r, outer_line), LINE, 3.0, true)
		draw_line(xf * Vector2(-end + circle_r, inner_line), xf * Vector2(end - circle_r, inner_line), LINE, 2.0, true)
		for sx in [-1.0, 1.0]:
			var c: Vector2 = xf * Vector2(sx * (end - circle_r), (outer_line + inner_line) / 2)
			draw_circle(c, circle_r + 2, LINE)
			draw_circle(c, circle_r - 1, RED)
			draw_circle(c, circle_r * 0.45, Color(1, 1, 1, 0.25))
		# diagonal arrow from the pocket toward the center, ending in an arc
		var dirv: Vector2 = xf * Vector2(1, 1).normalized()
		var tail := dirv * 470.0 * 0.66
		var tip := dirv * (HALF * 1.414 - 95)
		draw_line(tail, tip, LINE, 2.5, true)
		var side := dirv.orthogonal() * 9
		draw_colored_polygon(PackedVector2Array([tip + dirv * 4, tip - dirv * 18 + side, tip - dirv * 18 - side]), LINE)
		draw_arc(tail - dirv * 26, 26, dirv.angle() - 1.25, dirv.angle() + 1.25, 16, LINE, 2.5, true)
	# center: outer circle and a red rosette round the queen's spot
	draw_arc(Vector2.ZERO, 115, 0, TAU, 72, LINE, 2.5, true)
	draw_arc(Vector2.ZERO, 108, 0, TAU, 72, LINE, 1.2, true)
	var star := PackedVector2Array()
	for k in 16:
		star.append(Vector2.from_angle(k * PI / 8) * (98.0 if k % 2 == 0 else 38.0))
	draw_colored_polygon(star, Color(RED, 0.85))
	star.append(star[0])
	draw_polyline(star, LINE, 2.0, true)
	draw_circle(Vector2.ZERO, 30, PLY)
	draw_arc(Vector2.ZERO, 30, 0, TAU, 36, RED, 3.0, true)
	draw_arc(Vector2.ZERO, 22, 0, TAU, 36, LINE, 1.5, true)


## A pocket; `bulge` 0..1 swells the net once and lets it settle (sin bump).
func _draw_pocket(at: Vector2, bulge := 0.0) -> void:
	var r := Physics.POCKET_R + 3
	var swell := sin(bulge * PI) * (1.0 - bulge * 0.5)
	draw_circle(at, r + 4, WOOD_DARK)
	draw_circle(at, r, Color("16110e"))
	var net := Color(1, 1, 1, 0.12 + 0.18 * swell)
	for k in 3:  # net rings and threads, stretched toward the rim while it bulges
		draw_arc(at, r * (0.3 + k * 0.25) * (1.0 + 0.3 * swell), 0, TAU, 24, net, 1.5, true)
	for k in 6:
		var d := Vector2.from_angle(k * PI / 3 + 0.3)
		draw_line(at + d * r * 0.15, at + d * (r - 2), net, 1.5, true)
	if swell > 0.0:
		draw_circle(at, r * 0.32 * swell, Color(0, 0, 0, 0.5))


## One carrom piece with its shadow. `rot` turns its pattern (pieces spin while they slide).
static func draw_piece(ci: CanvasItem, at: Vector2, kind: int, rot := 0.0, scale := 1.0, alpha := 1.0, bad := false) -> void:
	var r := Physics.radius(kind) * scale
	var body: Color = Color("ff5a5a") if bad else KIND_COLORS[kind]
	var dark := body.darkened(0.35) if kind != Physics.BLACK else Color("120c0a")
	var mark := body.darkened(0.2) if kind in [Physics.WHITE, Physics.STRIKER] else body.lightened(0.25)
	ci.draw_circle(at + Vector2(3, 5) * scale, r + 1, Color(0, 0, 0, 0.28 * alpha))
	ci.draw_circle(at, r, Color(dark, alpha))
	ci.draw_circle(at, r - 2.5 * scale, Color(body, alpha))
	ci.draw_circle(at + Vector2(-r * 0.22, -r * 0.25), r * 0.55, Color(1, 1, 1, 0.12 * alpha))  # shine
	if kind == Physics.STRIKER:
		var ring: Color = Color("b3122a") if bad else STRIKER_RING
		ci.draw_arc(at, r * 0.72, 0, TAU, 32, Color(ring, alpha), 4.0 * scale, true)
		ci.draw_arc(at, r * 0.42, 0, TAU, 24, Color(ring, alpha), 2.5 * scale, true)
		for k in 4:
			ci.draw_circle(at + Vector2.from_angle(rot + k * PI / 2) * r * 0.57, 2.6 * scale, Color(ring, alpha))
		ci.draw_circle(at, r * 0.16, Color(ring, alpha))
		return
	ci.draw_arc(at, r * 0.62, 0, TAU, 28, Color(mark, alpha), 2.5 * scale, true)
	for k in 6:  # grooves between the rings show the spin
		var d := Vector2.from_angle(rot + k * PI / 3)
		ci.draw_line(at + d * r * 0.66, at + d * r * 0.82, Color(mark, alpha), 2.0 * scale, true)
	ci.draw_circle(at, r * 0.22, Color(mark, alpha))


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
