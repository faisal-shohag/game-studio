## Classic Ludo pin drawn with polygons. Shared by menu icons and (phase 2) the board.
## `foot` = bottom center on the ground, `s` = scale (pawn is ~95 * s tall).

const OUTLINE := Color("5a3420")


static func ellipse(center: Vector2, rx: float, ry: float, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func draw(ci: CanvasItem, foot: Vector2, s: float, color: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return foot + Vector2(x, y) * s
	var dark := color.darkened(0.3)
	var shade := dark.lerp(color, 0.45)
	var light := color.lightened(0.4)
	var line := 3.5 * s
	ci.draw_colored_polygon(ellipse(foot, 38 * s, 10 * s), Color(0, 0, 0, 0.25))
	# base disc
	var base := ellipse(p.call(0, -9), 33 * s, 12 * s)
	ci.draw_colored_polygon(base, dark)
	base.append(base[0])
	ci.draw_polyline(base, OUTLINE, line, true)
	ci.draw_colored_polygon(ellipse(p.call(0, -14), 31 * s, 10 * s), color)
	# body cone
	var body := PackedVector2Array([p.call(-27, -14), p.call(-19, -32), p.call(-12, -50), p.call(-9, -60),
		p.call(9, -60), p.call(12, -50), p.call(19, -32), p.call(27, -14)])
	ci.draw_colored_polygon(body, color)
	ci.draw_colored_polygon(PackedVector2Array([p.call(3, -60), p.call(9, -60), p.call(12, -50), p.call(19, -32),
		p.call(27, -14), p.call(11, -14)]), shade)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-19, -17), p.call(-14, -32), p.call(-8, -50),
		p.call(-4, -50), p.call(-9, -32), p.call(-12, -17)]), light)
	ci.draw_polyline(body, OUTLINE, line, true)
	# collar
	var collar := ellipse(p.call(0, -60), 14 * s, 5 * s)
	ci.draw_colored_polygon(collar, dark)
	collar.append(collar[0])
	ci.draw_polyline(collar, OUTLINE, line * 0.8, true)
	# head with rim shade + shine
	var head: Vector2 = p.call(0, -76)
	var r := 18.0 * s
	ci.draw_circle(head, r + line * 0.5, OUTLINE)
	ci.draw_circle(head, r, shade)
	ci.draw_circle(head + Vector2(-2, -2) * s, r * 0.82, color)
	ci.draw_circle(head + Vector2(-7, -7) * s, 5.5 * s, Color(1, 1, 1, 0.85))
