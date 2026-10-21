## Cartoon player portrait drawn with shapes: a rounded tile in the seat color with a head and
## shoulders. Eight looks (0-3 are the card-table seats' own faces), happy or sad.
## `center` = middle of the tile, `size` = tile side.

const OUTLINE := Color("23194d")
const SKIN := [Color("f6c9a4"), Color("c98d62"), Color("f9dcc4"), Color("8e5b3c"),
	Color("e8b48c"), Color("f3c7a0"), Color("b07850"), Color("f7d2b6")]
const HAIR := [Color("4a2f22"), Color("1f1b2e"), Color("e8a93c"), Color("7a3b1c"),
	Color("2b2b3a"), Color("c0392b"), Color("3a2418"), Color("9a6b4a")]
const PawnArt = preload("res://games/shared/pawn_art.gd")


static func draw(ci: CanvasItem, center: Vector2, size: float, color: Color, variant: int, happy := true) -> void:
	var u := size / 100.0
	var v := posmod(variant, SKIN.size())
	var p := func(x: float, y: float) -> Vector2: return center + Vector2(x, y) * u
	var tile := Rect2(center - Vector2(50, 50) * u, Vector2(100, 100) * u)
	var bg := StyleBoxFlat.new()
	bg.bg_color = color.lightened(0.45)
	bg.set_corner_radius_all(int(20 * u))
	bg.set_border_width_all(maxi(2, int(5 * u)))
	bg.border_color = Color.WHITE
	bg.anti_aliasing = true
	var rim := bg.duplicate()
	rim.bg_color = OUTLINE
	rim.set_border_width_all(0)
	ci.draw_style_box(rim, tile.grow(3 * u))
	ci.draw_style_box(bg, tile)
	# shoulders: shirt in the seat color, cut off by the tile's bottom edge
	var shirt := PackedVector2Array()
	for pt in PawnArt.ellipse(p.call(0, 52), 36 * u, 22 * u, 24):
		shirt.append(Vector2(pt.x, minf(pt.y, tile.end.y - 5 * u)))
	ci.draw_colored_polygon(shirt, color)
	ci.draw_polyline(_closed(shirt), OUTLINE, 2.5 * u, true)
	var head: Vector2 = p.call(0, -4)
	var r := 25.0 * u
	var hair: Color = HAIR[v]
	if v == 3:  # bun on top
		ci.draw_circle(p.call(0, -34), 10 * u + 2.5 * u, OUTLINE)
		ci.draw_circle(p.call(0, -34), 10 * u, hair)
	if v == 6:  # curls all round, behind the head
		for k in 11:
			ci.draw_circle(head + Vector2.from_angle(0.75 * PI + k * 1.5 * PI / 10) * r * 1.05, 9 * u, hair)
	if v == 0:  # long hair falls behind the head
		ci.draw_colored_polygon(PackedVector2Array([p.call(-29, -12), p.call(-31, 22), p.call(-17, 22),
			p.call(17, 22), p.call(31, 22), p.call(29, -12)]), hair)
	ci.draw_circle(head, r + 2.5 * u, OUTLINE)
	ci.draw_circle(head, r, SKIN[v])
	# hair on top of the head
	match v:
		0, 3, 4:
			var cap := PackedVector2Array()
			for k in 13:
				cap.append(head + Vector2.from_angle(PI + k * PI / 12) * (r + 1.5 * u))
			cap.append(head + Vector2(r * 0.6, -r * 0.35))
			cap.append(head + Vector2(-r * 0.2, -r * 0.55))
			cap.append(head + Vector2(-r * 0.7, -r * 0.2))
			ci.draw_colored_polygon(cap, hair)
		1:  # short spikes
			var cap := PackedVector2Array()
			for k in 13:
				cap.append(head + Vector2.from_angle(PI + k * PI / 12) * (r + 1.5 * u))
			cap.append(head + Vector2(0, -r * 0.45))
			ci.draw_colored_polygon(cap, hair)
			for k in 5:
				var a := PI + (k + 0.5) * PI / 5
				ci.draw_colored_polygon(PackedVector2Array([head + Vector2.from_angle(a - 0.25) * r,
					head + Vector2.from_angle(a) * (r + 10 * u), head + Vector2.from_angle(a + 0.25) * r]), hair)
		2, 6:  # curls
			for k in 7:
				ci.draw_circle(head + Vector2.from_angle(PI + 0.2 + k * (PI - 0.4) / 6) * r * 0.92, 8 * u, hair)
		5:  # cap with a brim
			var dome := PackedVector2Array()
			for k in 13:
				dome.append(head + Vector2.from_angle(PI + k * PI / 12) * (r + 2 * u) + Vector2(0, -2 * u))
			ci.draw_colored_polygon(dome, hair)
			ci.draw_polyline(dome, OUTLINE, 2.5 * u, true)
			ci.draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 0.2, -3 * u), head + Vector2(r * 1.45, -3 * u),
				head + Vector2(r * 1.35, 2 * u), head + Vector2(-r * 0.2, 2 * u)]), hair.darkened(0.3))
			ci.draw_circle(head + Vector2(0, -r - 1 * u), 3 * u, Color.WHITE)
	# eyes, cheeks, mouth
	for side in [-1, 1]:
		ci.draw_circle(head + Vector2(side * 9, 2) * u, 3.6 * u, OUTLINE)
		ci.draw_circle(head + Vector2(side * 9 - 1, 1) * u, 1.2 * u, Color.WHITE)
		ci.draw_colored_polygon(PawnArt.ellipse(head + Vector2(side * 15, 10) * u, 4.5 * u, 2.8 * u, 12), Color(1, 0.4, 0.45, 0.35))
	if v == 4:  # round glasses
		for side in [-1, 1]:
			ci.draw_arc(head + Vector2(side * 9, 2) * u, 7 * u, 0, TAU, 20, OUTLINE, 2.4 * u, true)
		ci.draw_line(head + Vector2(-2, 1) * u, head + Vector2(2, 1) * u, OUTLINE, 2.4 * u, true)
	var mouth := head + Vector2(0, 11) * u
	if v == 7:  # beard round the chin, mouth showing through
		var beard := PackedVector2Array()
		for k in 13:
			beard.append(head + Vector2.from_angle(k * PI / 12) * (r + 1 * u))
		beard.append(head + Vector2(-r * 0.6, 6 * u))
		beard.append(head + Vector2(r * 0.6, 6 * u))
		ci.draw_colored_polygon(beard, hair)
		ci.draw_circle(mouth + Vector2(0, 2) * u, 6 * u, SKIN[v].darkened(0.35))
	if happy:
		ci.draw_arc(mouth, 7 * u, 0.15 * PI, 0.85 * PI, 10, OUTLINE, 2.6 * u, true)
	else:
		ci.draw_arc(mouth + Vector2(0, 6) * u, 6 * u, 1.2 * PI, 1.8 * PI, 10, OUTLINE, 2.6 * u, true)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
