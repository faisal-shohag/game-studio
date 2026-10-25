## Color Cards faces and backs, drawn in code (no image files). Draws one card centered on the
## origin of `xf` onto any CanvasItem, so cards, piles, fans and icons share it.
##
## Face: white rim, colored body (dark for wilds), a ringed medallion with the big symbol, corner
## indices. Wilds show four colored quadrants. Back: orange with a faint "GS" pattern and a badge.

const Rules = preload("res://games/cards/cards_rules.gd")
const SIZE := Vector2(170, 250)
const BACK := Color("e8743b")


static func draw(ci: CanvasItem, id: int, face_up: bool, xf := Transform2D.IDENTITY, lift := 0.0) -> void:
	xf = xf * Transform2D(0.0, Vector2(0, -lift))
	ci.draw_set_transform_matrix(xf)
	var r := Rect2(-SIZE / 2, SIZE)
	ci.draw_style_box(_box(Color(0, 0, 0, 0.3), 18), Rect2(r.position + Vector2(0, 6), r.size))  # shadow
	var rim := _box(Color.WHITE, 18)
	rim.set_border_width_all(3)
	rim.border_color = UI.INK
	ci.draw_style_box(rim, r)
	if face_up:
		_face(ci, id, r.grow(-10), xf)
	else:
		_back(ci, r.grow(-10))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func color_of(id: int) -> Color:
	var c := Rules.color_of(id)
	return UI.INK.lightened(0.15) if c == -1 else UI.COLORS[c]


static func _face(ci: CanvasItem, id: int, r: Rect2, xf: Transform2D) -> void:
	var k := Rules.kind_of(id)
	var body := color_of(id)
	ci.draw_style_box(_box(body, 12), r)
	for i in 3:  # soft diagonal bands for texture
		var y := r.position.y + 40 + i * 70
		ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, y), Vector2(r.end.x, y - 60),
			Vector2(r.end.x, y - 40), Vector2(r.position.x, y + 20)]), Color(1, 1, 1, 0.07))
	ci.draw_circle(Vector2.ZERO, 62, Color.WHITE)
	ci.draw_circle(Vector2.ZERO, 55, body.lightened(0.2) if k < Rules.WILD else UI.INK)
	symbol(ci, k, Vector2.ZERO, 1.0)
	ci.draw_set_transform_matrix(xf * Transform2D(0.0, r.position + Vector2(22, 26)))
	symbol(ci, k, Vector2.ZERO, 0.36)
	ci.draw_set_transform_matrix(xf * Transform2D(PI, r.end - Vector2(22, 26)))
	symbol(ci, k, Vector2.ZERO, 0.36)
	ci.draw_set_transform_matrix(xf)


## The big mark for card kind k at `at`, `s` = 1 for the center of a card.
static func symbol(ci: CanvasItem, k: int, at: Vector2, s: float) -> void:
	var ink: Color = UI.INK
	if k >= Rules.WILD:
		var rad := 44.0 * s
		for q in 4:
			var pts := PackedVector2Array([at])
			for j in 9:
				pts.append(at + Vector2.from_angle(-PI / 2 + (q + j / 8.0) * PI / 2) * rad)
			ci.draw_colored_polygon(pts, UI.COLORS[q])
		ci.draw_arc(at, rad, 0, TAU, 32, Color.WHITE, 5 * s, true)
		if k == Rules.WILD4:
			text(ci, "+4", at, 70 * s)
	elif k == Rules.SKIP:
		ci.draw_arc(at, 32 * s, 0, TAU, 32, ink, 22 * s, true)
		ci.draw_line(at + Vector2(-22, 22) * s, at + Vector2(22, -22) * s, ink, 22 * s, true)
		ci.draw_arc(at, 32 * s, 0, TAU, 32, Color.WHITE, 12 * s, true)
		ci.draw_line(at + Vector2(-22, 22) * s, at + Vector2(22, -22) * s, Color.WHITE, 12 * s, true)
	elif k == Rules.REVERSE:
		for pass_ in 2:
			var w := (22.0 if pass_ == 0 else 11.0) * s
			var col: Color = ink if pass_ == 0 else Color.WHITE
			for side in [-1, 1]:
				var y: float = side * 15 * s
				var tip := at + Vector2(side * -30 * s, y)
				ci.draw_line(at + Vector2(side * 24 * s, y), tip + Vector2(side * 10 * s, 0), col, w, true)
				ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(side * -10 * s, 0),
					tip + Vector2(side * 14 * s, -16 * s - w * 0.3), tip + Vector2(side * 14 * s, 16 * s + w * 0.3)]), col)
	else:
		text(ci, "+2" if k == Rules.DRAW2 else str(k), at, 92 * s)


static func text(ci: CanvasItem, text: String, at: Vector2, size: float) -> void:
	var fs := maxi(8, int(size))
	var w := 200.0
	var pos := at + Vector2(-w / 2, fs * 0.36)
	ci.draw_string_outline(UI.FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, maxi(4, int(fs * 0.22)), UI.INK)
	ci.draw_string(UI.FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color.WHITE)


static func _back(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_style_box(_box(BACK, 12), r)
	var faint := Color(1, 1, 1, 0.1)
	for row in 6:
		for col in 3:
			var at := r.position + Vector2(25 + col * 50 + (row % 2) * 25, 26 + row * 39)
			if at.x < r.end.x - 10:
				ci.draw_string(UI.FONT, at + Vector2(-25, 8), "GS", HORIZONTAL_ALIGNMENT_CENTER, 50, 22, faint)
	ci.draw_circle(Vector2.ZERO, 50, UI.INK)
	ci.draw_circle(Vector2.ZERO, 44, UI.COLORS[2])
	ci.draw_circle(Vector2.ZERO, 36, BACK.darkened(0.2))
	text(ci, "GS", Vector2(0, 0), 46)


static func _box(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s
