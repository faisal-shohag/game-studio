## Pen Fight desk drawn in code: a wooden school-desk top with warm grain, rounded edges and a
## darker bevel, a pencil groove along the top, old doodles and scratches (a heart, initials,
## tic-tac-toe, a compass-scratch circle), a faint ink stain, and the dark floor round it; then
## the pens and the aim on top. Local coordinates are desk units minus the desk center, so the
## top spans -500..500 across and -700..700 down. The desk never turns.
extends Node2D

const Physics = preload("res://games/penfight/pen_physics.gd")
const HALF := Vector2(Physics.W / 2, Physics.H / 2)
const LIP := 18.0  # bevel round the top
const WOOD := Color("d39a5e")
const WOOD_DARK := Color("8a5530")
const BEVEL := Color("a86b3a")
const FLOOR := Color("221a17")
const CARVE := Color(0.32, 0.17, 0.07, 0.42)  # scratched into the wood
const GRAPHITE := Color(0.25, 0.25, 0.3, 0.38)
const CHROME := Color("c9ced6")

## Pens on the desk: {id, type, x, y, angle, fall} in desk units (0..1000, 0..1400).
var pens := []:
	set(v):
		pens = v
		queue_redraw()
## Pen id -> its player's color.
var colors := {}
## Aim: {id, grab: desk point, dir: desk direction, power 0..1, spin -1..1} or {}.
var aim := {}:
	set(v):
		aim = v
		queue_redraw()
## Real-time: more aims at once, by finger (same shape as `aim`).
var aims := {}
## Real-time: pen id -> cooldown left 0..1 (0 = ready), drawn as a ring round the pen's middle.
var cooldowns := {}
## Real-time: pen id -> 0..1 age of the "ready" pulse.
var pulses := {}
var _grain := []  # [points, color, width]
var _scratches := []  # [a, b, width]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11  # the same desk every game
	for k in 60:
		var x := -HALF.x + rng.randf() * HALF.x * 2
		var pts := PackedVector2Array()
		var amp := rng.randf_range(3, 12)
		var freq := rng.randf_range(0.003, 0.009)
		var ph := rng.randf() * TAU
		for i in 36:
			var y := -HALF.y + i * HALF.y * 2 / 35.0
			pts.append(Vector2(x + sin(y * freq + ph) * amp, y))
		_grain.append([pts, Color(0.45, 0.24, 0.08, rng.randf_range(0.06, 0.16)), rng.randf_range(1.5, 5.0)])
	for k in 22:
		var a := Vector2(rng.randf_range(-460, 460), rng.randf_range(-640, 660))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(14, 60)
		_scratches.append([a, b, rng.randf_range(1.2, 2.5)])


## Global position of a desk point.
func to_screen(p: Vector2) -> Vector2:
	return to_global(p - HALF)


func to_desk(global: Vector2) -> Vector2:
	return to_local(global) + HALF


func _draw() -> void:
	_draw_floor()
	_draw_top()
	_draw_doodles()
	for p in pens:  # pens tipping off go under the desk's edge, so draw them first
		if p.fall > 0.0 and p.fall < 1.0:
			_draw_one(p)
	for p in pens:
		if p.fall <= 0.0:
			_draw_one(p)
			_draw_cooldown(p)
	if not aim.is_empty():
		_draw_aim(aim)
	for a in aims.values():
		_draw_aim(a)


func _draw_cooldown(p: Dictionary) -> void:
	var at := Vector2(p.x, p.y) - HALF
	var col: Color = colors.get(p.id, Color.WHITE)
	var left: float = cooldowns.get(p.id, 0.0)
	if left > 0.0:
		draw_arc(at, 30, 0, TAU, 32, Color(0, 0, 0, 0.35), 9.0, true)
		draw_arc(at, 30, -PI / 2, -PI / 2 + TAU * (1.0 - left), 32, Color(col.lightened(0.3), 0.9), 7.0, true)
	var pulse: float = pulses.get(p.id, 1.0)
	if pulse < 1.0:
		draw_arc(at, 30 + pulse * 60, 0, TAU, 40, Color(col.lightened(0.4), 1.0 - pulse), 8.0 * (1.0 - pulse) + 2.0, true)


func _draw_one(p: Dictionary) -> void:
	var f: float = p.fall
	draw_pen(self, Vector2(p.x, p.y) - HALF, p.angle, p.type, colors.get(p.id, Color.WHITE), 1.0 - f * 0.7, f, 1.0 - f * 0.35)


func _draw_floor() -> void:
	draw_rect(Rect2(-HALF - Vector2(900, 900), HALF * 2 + Vector2(1800, 1800)), FLOOR)
	for k in range(-12, 13):  # floor boards
		var x := k * 140.0
		draw_line(Vector2(x, -HALF.y - 900), Vector2(x, HALF.y + 900), Color(0, 0, 0, 0.25), 4)
	# the desk's shadow on the floor
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.45)
	shadow.set_corner_radius_all(46)
	draw_style_box(shadow, Rect2(-HALF, HALF * 2).grow(LIP + 10).grow_individual(0, 0, 8, 26))


func _draw_top() -> void:
	var top := Rect2(-HALF, HALF * 2)
	var bevel := StyleBoxFlat.new()
	bevel.bg_color = BEVEL
	bevel.set_corner_radius_all(40)
	bevel.border_width_bottom = 10
	bevel.border_color = WOOD_DARK
	bevel.anti_aliasing = true
	draw_style_box(bevel, top.grow(LIP))
	var wood := StyleBoxFlat.new()
	wood.bg_color = WOOD
	wood.set_corner_radius_all(26)
	wood.anti_aliasing = true
	draw_style_box(wood, top)
	for g in _grain:
		draw_polyline(g[0], g[1], g[2], true)
	for k in 6:  # knots
		var at := Vector2([-330, 250, -120, 380, -390, 160][k], [-420, -230, 160, 420, 560, 620][k])
		for ring in 3:
			draw_arc(at, 10.0 + ring * 9, 0, TAU, 24, Color(0.4, 0.2, 0.06, 0.16 - ring * 0.04), 3.0, true)
	# light from the top-left, a darker rim toward the edges
	for k in 4:
		var w := 16.0 - k * 4
		draw_style_box(_rim(26.0 + k * 2, Color(0.3, 0.15, 0.05, 0.05)), top.grow(-k * 4.0 - w / 2))
	# pencil groove along the top, with a stubby pencil in it
	var groove := Rect2(-HALF.x + 120, -HALF.y + 26, HALF.x * 2 - 240, 34)
	var g := StyleBoxFlat.new()
	g.bg_color = WOOD_DARK.darkened(0.1)
	g.set_corner_radius_all(17)
	g.border_width_top = 6
	g.border_color = Color(0, 0, 0, 0.3)
	g.anti_aliasing = true
	draw_style_box(g, groove)
	draw_line(groove.position + Vector2(17, groove.size.y), groove.end - Vector2(17, 0), Color(1, 0.85, 0.6, 0.35), 2.0, true)
	_draw_pencil(Vector2(-HALF.x + 360, -HALF.y + 43))


func _rim(radius: float, color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_border_width_all(4)
	s.border_color = color
	s.set_corner_radius_all(int(radius))
	s.anti_aliasing = true
	return s


func _draw_pencil(at: Vector2) -> void:
	var yellow := Color("f2c230")
	draw_rect(Rect2(at + Vector2(0, -10), Vector2(130, 20)), yellow)
	draw_line(at + Vector2(0, -3), at + Vector2(130, -3), yellow.darkened(0.15), 3)
	draw_line(at + Vector2(0, 4), at + Vector2(130, 4), yellow.lightened(0.2), 2)
	draw_rect(Rect2(at + Vector2(-16, -10), Vector2(16, 20)), Color("b8bcc4"))  # ferrule
	draw_rect(Rect2(at + Vector2(-30, -10), Vector2(14, 20)), Color("f08a8a"))  # eraser
	draw_colored_polygon(PackedVector2Array([at + Vector2(130, -10), at + Vector2(130, 10), at + Vector2(162, 0)]), Color("f1d3a8"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(152, -3.2), at + Vector2(152, 3.2), at + Vector2(162, 0)]), Color("3a3a40"))


func _draw_doodles() -> void:
	# a carved heart with initials
	var heart := PackedVector2Array()
	for k in 33:
		var t := k / 32.0 * TAU
		heart.append(Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * 4.2 + Vector2(270, 470))
	draw_polyline(heart, CARVE, 3.0, true)
	draw_string(UI.FONT, Vector2(222, 488), "A + R", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, CARVE)
	draw_line(Vector2(330, 420), Vector2(250, 520), CARVE, 2.0, true)  # the arrow through it
	draw_colored_polygon(PackedVector2Array([Vector2(338, 410), Vector2(322, 418), Vector2(332, 428)]), CARVE)
	# tic-tac-toe in pencil
	var o := Vector2(-370, 300)
	for k in [1, 2]:
		draw_line(o + Vector2(k * 40, 0), o + Vector2(k * 40, 120), GRAPHITE, 3.0, true)
		draw_line(o + Vector2(0, k * 40), o + Vector2(120, k * 40), GRAPHITE, 3.0, true)
	for cell in [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)]:
		var c: Vector2 = o + cell * 40 + Vector2(20, 20)
		draw_line(c - Vector2(11, 11), c + Vector2(11, 11), GRAPHITE, 3.0, true)
		draw_line(c + Vector2(-11, 11), c + Vector2(11, -11), GRAPHITE, 3.0, true)
	for cell in [Vector2(2, 0), Vector2(0, 2)]:
		draw_arc(o + cell * 40 + Vector2(20, 20), 12, 0, TAU, 20, GRAPHITE, 3.0, true)
	draw_line(o + Vector2(6, 6), o + Vector2(114, 114), Color(GRAPHITE, 0.5), 2.0, true)  # three in a row
	# a compass-scratch circle
	draw_arc(Vector2(-250, -380), 92, 0.3, TAU - 0.2, 64, CARVE, 2.0, true)
	draw_arc(Vector2(-250, -380), 88, 1.2, 4.0, 40, Color(CARVE, 0.25), 1.5, true)
	draw_circle(Vector2(-250, -380), 4, CARVE)
	# initials and a date, scratched
	draw_string(UI.FONT, Vector2(150, -560), "M.K. was here", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, CARVE)
	for s in _scratches:
		draw_line(s[0], s[1], Color(0.35, 0.18, 0.06, 0.22), s[2], true)
	# a faint ink stain
	var ink := Color(0.12, 0.16, 0.42, 0.13)
	for b in [[Vector2(320, -160), 42.0], [Vector2(350, -138), 26.0], [Vector2(296, -130), 20.0], [Vector2(372, -186), 11.0], [Vector2(262, -186), 7.0]]:
		draw_circle(b[0], b[1], ink)


## Aim: an arrow from the grab point along the flick, a power ring round the grab point and a
## curved spin hint when grabbing near an end.
func _draw_aim(g: Dictionary) -> void:
	var at: Vector2 = g.grab - HALF
	var dir: Vector2 = g.dir
	var p: float = g.power
	var col := Color(1, 1, 1).lerp(Color("ffc312"), clampf(p * 1.6, 0, 1)).lerp(Color("ff4757"), clampf(p * 2.5 - 1.5, 0, 1))
	var length := 90.0 + 330.0 * p
	var tip := at + dir * length
	var t := 0.0
	while t < length - 30:  # dashed shaft
		draw_line(at + dir * t, at + dir * minf(t + 22, length - 30), Color(0, 0, 0, 0.35), 13.0, true)
		draw_line(at + dir * t, at + dir * minf(t + 22, length - 30), col, 8.0, true)
		t += 34
	var side := dir.orthogonal() * 26
	var head := PackedVector2Array([tip, tip - dir * 44 + side, tip - dir * 44 - side])
	draw_colored_polygon(head, col)
	head.append(head[0])
	draw_polyline(head, Color(0, 0, 0, 0.35), 3.0, true)
	draw_arc(at, 34, 0, TAU, 40, Color(0, 0, 0, 0.3), 10.0, true)
	draw_arc(at, 34, -PI / 2, -PI / 2 + TAU * p, 40, col, 10.0, true)
	draw_circle(at, 8, col)
	var spin: float = g.get("spin", 0.0)
	if absf(spin) > 0.25:  # which way the pen will turn
		var c: Vector2 = g.get("center", g.grab) - HALF
		var r := 70.0 + 40.0 * absf(spin)
		var a0 := (at - c).angle()
		var sweep := 1.6 * signf(spin)
		draw_arc(c, r, a0, a0 + sweep, 24, Color(1, 1, 1, 0.75), 5.0, true)
		var end := c + Vector2.from_angle(a0 + sweep) * r
		var along := Vector2.from_angle(a0 + sweep + PI / 2 * signf(spin))
		draw_colored_polygon(PackedVector2Array([end + along * 16, end - along * 4 + along.orthogonal() * 11, end - along * 4 - along.orthogonal() * 11]), Color(1, 1, 1, 0.75))


## One pen with its shadow, tip toward +x of `angle`. `lift` 0..1 moves the shadow away (falling),
## `scale` shrinks it as it drops.
static func draw_pen(ci: CanvasItem, at: Vector2, angle: float, type: String, color: Color, alpha := 1.0, lift := 0.0, scale := 1.0) -> void:
	var spec := Physics.spec(type)
	var h: float = spec.length / 2.0
	var r: float = spec.radius
	ci.draw_set_transform(at + Vector2(5, 9) * (1.0 + lift * 4.0) * scale, angle, Vector2(scale, scale))
	_capsule(ci, -h, h, r + 1, Color(0, 0, 0, 0.3 * alpha * (1.0 - lift * 0.5)))
	ci.draw_set_transform(at, angle, Vector2(scale, scale))
	var a := func(c: Color) -> Color: return Color(c, c.a * alpha)
	var ink: Color = Color("23194d")
	match type:
		"gel":
			_tip(ci, h - 22, h, r * 0.75, a.call(CHROME), a.call(ink))
			_capsule(ci, -h, h - 22, r, a.call(Color(0.86, 0.93, 1.0, 0.75)))  # clear barrel
			ci.draw_line(Vector2(-h + 40, 0), Vector2(h - 40, 0), a.call(color), r * 0.55, true)  # ink tube
			ci.draw_rect(Rect2(h - 62, -r, 40, r * 2), a.call(color.darkened(0.25)))  # rubber grip
			for k in 4:
				ci.draw_line(Vector2(h - 58 + k * 10, -r), Vector2(h - 58 + k * 10, r), a.call(color.darkened(0.5)), 2.0)
			_capsule(ci, -h, -h + 52, r + 1, a.call(color))  # cap
			ci.draw_rect(Rect2(-h + 12, -r - 7, 84, 7), a.call(color.darkened(0.2)))  # clip
			ci.draw_line(Vector2(-h + 4, -r * 0.45), Vector2(h - 30, -r * 0.45), a.call(Color(1, 1, 1, 0.55)), 3.0, true)
		"metal":
			_tip(ci, h - 24, h, r * 0.7, a.call(CHROME.darkened(0.1)), a.call(ink))
			_capsule(ci, -h, h - 24, r, a.call(CHROME))
			ci.draw_rect(Rect2(-h + 4, r * 0.25, h * 2 - 30, r * 0.7), a.call(CHROME.darkened(0.25)))
			ci.draw_line(Vector2(-h + 8, -r * 0.45), Vector2(h - 28, -r * 0.45), a.call(Color.WHITE), 4.0, true)
			for x in [-h + 34, -h + 46, h - 70]:  # colored bands
				ci.draw_rect(Rect2(x, -r, 8, r * 2), a.call(color))
			ci.draw_rect(Rect2(-h + 8, -r - 6, 92, 6), a.call(CHROME.lightened(0.2)))  # clip
			ci.draw_circle(Vector2(-h + 100, -r - 3), 4, a.call(CHROME.lightened(0.2)))
		"marker":
			_tip(ci, h - 8, h + 6, r * 0.5, a.call(ink), a.call(ink))
			_capsule(ci, -h, h - 4, r, a.call(Color("f3f1ea")))
			_capsule(ci, h - 96, h, r + 2, a.call(color))  # big cap over the tip
			ci.draw_rect(Rect2(h - 104, -r - 2, 10, (r + 2) * 2), a.call(color.darkened(0.3)))
			ci.draw_rect(Rect2(-h + 60, -r * 0.6, 110, r * 1.2), a.call(color.lightened(0.15)))  # label
			ci.draw_line(Vector2(-h + 70, 0), Vector2(-h + 160, 0), a.call(Color(1, 1, 1, 0.8)), 4.0)
			_capsule(ci, -h, -h + 16, r, a.call(color))  # end plug
			ci.draw_line(Vector2(-h + 10, -r * 0.5), Vector2(h - 110, -r * 0.5), a.call(Color(1, 1, 1, 0.6)), 4.0, true)
		_:  # highlighter: chunky, bright, flat cap
			var bright := color.lightened(0.35)
			var body := StyleBoxFlat.new()
			body.bg_color = a.call(bright)
			body.set_corner_radius_all(int(r * 0.5))
			body.anti_aliasing = true
			ci.draw_style_box(body, Rect2(-h, -r, h * 2 - 64, r * 2))
			ci.draw_rect(Rect2(-h + 40, -r * 0.35, 90, r * 0.7), a.call(color.lightened(0.6)))  # ink window
			var cap := StyleBoxFlat.new()
			cap.bg_color = a.call(color.darkened(0.15))
			cap.set_corner_radius_all(int(r * 0.3))
			cap.anti_aliasing = true
			ci.draw_style_box(cap, Rect2(h - 72, -r - 2, 72, r * 2 + 4))
			ci.draw_rect(Rect2(h - 64, -r - 8, 48, 7), a.call(color.darkened(0.35)))  # clip
			ci.draw_line(Vector2(-h + 8, -r * 0.55), Vector2(h - 80, -r * 0.55), a.call(Color(1, 1, 1, 0.5)), 5.0, true)
	ci.draw_set_transform(Vector2.ZERO)


## A rounded bar from x0 to x1 along the pen, one polygon so see-through ones don't double up.
static func _capsule(ci: CanvasItem, x0: float, x1: float, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var a := x0 + r
	var b := maxf(a, x1 - r)
	for k in 9:
		pts.append(Vector2(b, 0) + Vector2.from_angle(-PI / 2 + k * PI / 8) * r)
	for k in 9:
		pts.append(Vector2(a, 0) + Vector2.from_angle(PI / 2 + k * PI / 8) * r)
	ci.draw_colored_polygon(pts, color)


static func _tip(ci: CanvasItem, x0: float, x1: float, r: float, color: Color, point: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, -r), Vector2(x1 - 4, -2.5), Vector2(x1 - 4, 2.5), Vector2(x0, r)]), color)
	ci.draw_circle(Vector2(x1 - 3, 0), 3.0, point)
