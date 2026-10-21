## Vector icons drawn in code, so the app needs no image assets.
extends Control

const PawnArt = preload("res://games/shared/pawn_art.gd")
const CardArt = preload("res://games/cards/card_art.gd")
const FaceArt = preload("res://games/shared/face_art.gd")
const Avatar = preload("res://core/avatar.gd")
const CarromBoard = preload("res://games/carrom/carrom_board.gd")
const PenDesk = preload("res://games/penfight/penfight_desk.gd")

var kind := ""
var color := Color.WHITE
var count := 1  # "pawns"/"faces": how many; "face": which look
var sad := false  # "face": frowning
var avatar := {}  # "avatar": what to show (a pawn if empty)
var round := false  # "avatar": circle instead of a rounded tile
var disc := Color(0, 0, 0, 0)  # optional backdrop circle for contrast
var bob := false:  # gentle float up and down
	set(v):
		bob = v
		set_process(v)
		queue_redraw()


func _ready() -> void:
	set_process(bob)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var u := minf(size.x, size.y) / 100.0
	var c := size / 2
	if bob:
		c.y += sin(Time.get_ticks_msec() / 220.0) * 5 * u
	var ink: Color = UI.INK
	if disc.a > 0:
		draw_circle(size / 2, 44 * u, disc)
	match kind:
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(10, -24) * u, c + Vector2(-12, 0) * u, c + Vector2(10, 24) * u]), color, 11 * u, true)
		"pawn":
			PawnArt.draw(self, c + Vector2(0, 46) * u, u * 0.95, color)
		"pawns":
			var s := minf(u * 1.8 / count, u * 0.8)
			for i in count:
				var x := size.x * (i + 0.5) / count
				PawnArt.draw(self, Vector2(x, c.y + 46 * s), s, UI.COLORS[i])
		"face":
			FaceArt.draw(self, c, 92 * u, color, count, not sad)
		"avatar":
			var col: Color = UI.COLORS[avatar.face % 4] if avatar.has("face") else color
			if not Avatar.draw(self, c, 92 * u, avatar, col, round, not sad):
				PawnArt.draw(self, c + Vector2(0, 46) * u, u * 0.95, color)
		"qr":  # three finder squares and a few modules
			var s := 76 * u
			var o := c - Vector2(s, s) / 2
			var q := s / 7.0 * 2.6
			for corner in [Vector2.ZERO, Vector2(s - q, 0), Vector2(0, s - q)]:
				draw_rect(Rect2(o + corner, Vector2(q, q)), color)
				draw_rect(Rect2(o + corner + Vector2(q, q) * 0.18, Vector2(q, q) * 0.64), disc if disc.a > 0 else ink)
				draw_rect(Rect2(o + corner + Vector2(q, q) * 0.32, Vector2(q, q) * 0.36), color)
			for d in [Vector2(0.62, 0.62), Vector2(0.84, 0.62), Vector2(0.62, 0.84), Vector2(0.84, 0.84), Vector2(0.45, 0.1), Vector2(0.1, 0.45), Vector2(0.73, 0.4)]:
				draw_rect(Rect2(o + d * s, Vector2(s, s) * 0.12), color)
		"camera":
			var body := Rect2(c + Vector2(-38, -22) * u, Vector2(76, 52) * u)
			draw_rect(Rect2(c + Vector2(-14, -32) * u, Vector2(28, 14) * u), color)
			var box := StyleBoxFlat.new()
			box.bg_color = color
			box.set_corner_radius_all(int(10 * u))
			draw_style_box(box, body)
			draw_circle(body.get_center(), 18 * u, ink)
			draw_circle(body.get_center(), 12 * u, color)
			draw_circle(body.get_center(), 6 * u, ink)
		"faces":
			var s := minf(size.x / count, size.y) * 0.86
			for i in count:
				FaceArt.draw(self, Vector2(size.x * (i + 0.5) / count, c.y), s, UI.COLORS[i], i)
		"dice":
			draw_rect(Rect2(c - Vector2(34, 34) * u, Vector2(68, 68) * u), ink)
			draw_rect(Rect2(c - Vector2(30, 30) * u, Vector2(60, 60) * u), Color.WHITE)
			for d in [Vector2(-15, -15), Vector2(0, 0), Vector2(15, 15), Vector2(15, -15), Vector2(-15, 15)]:
				draw_circle(c + d * u, 6 * u, ink)
		"wifi":
			var o := c + Vector2(0, 26) * u
			for r in [1, 2, 3]:
				draw_arc(o, r * 17 * u, -PI * 0.78, -PI * 0.22, 20, color, 9 * u)
			draw_circle(o, 7 * u, color)
		"sound", "mute":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-30, -10) * u, c + Vector2(-16, -10) * u, c + Vector2(2, -28) * u,
				c + Vector2(2, 28) * u, c + Vector2(-16, 10) * u, c + Vector2(-30, 10) * u]), color)
			if kind == "sound":
				draw_arc(c + Vector2(4, 0) * u, 16 * u, -PI / 3, PI / 3, 12, color, 6 * u)
				draw_arc(c + Vector2(4, 0) * u, 28 * u, -PI / 3, PI / 3, 12, color, 6 * u)
			else:
				draw_line(c + Vector2(12, -12) * u, c + Vector2(34, 12) * u, color, 7 * u)
				draw_line(c + Vector2(12, 12) * u, c + Vector2(34, -12) * u, color, 7 * u)
		"crown":
			var crown := PackedVector2Array([c + Vector2(-40, 30) * u, c + Vector2(-44, -24) * u, c + Vector2(-20, 0) * u,
				c + Vector2(0, -36) * u, c + Vector2(20, 0) * u, c + Vector2(44, -24) * u, c + Vector2(40, 30) * u])
			draw_colored_polygon(crown, UI.COLORS[2])
			crown.append(crown[0])
			draw_polyline(crown, ink, 6 * u, true)
			for d in [Vector2(-22, 16), Vector2(0, 16), Vector2(22, 16)]:
				draw_circle(c + d * u, 6 * u, UI.COLORS[0])
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * (44 if k % 2 == 0 else 20) * u)
			draw_colored_polygon(pts, color)
			pts.append(pts[0])
			draw_polyline(pts, ink, 5 * u, true)
		"lock":
			draw_arc(c + Vector2(0, -6) * u, 16 * u, PI, TAU, 16, color, 8 * u)
			draw_rect(Rect2(c + Vector2(-25, -6) * u, Vector2(50, 40) * u), color)
			draw_circle(c + Vector2(0, 12) * u, 6 * u, ink)
		"robot":
			draw_line(c + Vector2(0, -30) * u, c + Vector2(0, -44) * u, color, 5 * u)
			draw_circle(c + Vector2(0, -46) * u, 6 * u, color)
			draw_rect(Rect2(c + Vector2(-34, -30) * u, Vector2(68, 54) * u), color)
			draw_circle(c + Vector2(-14, -6) * u, 8 * u, ink)
			draw_circle(c + Vector2(14, -6) * u, 8 * u, ink)
			draw_rect(Rect2(c + Vector2(-14, 10) * u, Vector2(28, 6) * u), ink)
		"ladder":  # leaning ladder with a little snake curled around its foot
			var a := c + Vector2(-22, 40) * u
			var b := c + Vector2(22, -42) * u
			var dir := (b - a).normalized()
			var side := dir.orthogonal() * 15 * u
			for pass_ in 2:
				var w := (10.0 if pass_ == 0 else 5.0) * u
				var col: Color = ink if pass_ == 0 else color
				for k in range(1, 5):
					var m := a.lerp(b, k / 5.0)
					draw_line(m - side, m + side, col, w - 2 * u, true)
				draw_line(a - side, b - side, col, w, true)
				draw_line(a + side, b + side, col, w, true)
			var body := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				body.append(c + Vector2(lerpf(-40, 34, t), 34 + sin(t * TAU * 1.3) * 9) * u)
			draw_polyline(body, ink, 15 * u, true)
			draw_polyline(body, UI.COLORS[1], 9 * u, true)
			draw_circle(body[body.size() - 1], 10 * u, ink)
			draw_circle(body[body.size() - 1], 7 * u, UI.COLORS[1])
		"cards":  # three fanned cards: red 7, yellow skip, a wild on top
			for k in 3:
				var a := (k - 1) * 0.32
				var xf := Transform2D(a, c + Vector2((k - 1) * 22, 4 + absf(k - 1) * 6) * u).scaled_local(Vector2(0.3, 0.3) * u)
				CardArt.draw(self, [14, 69, 104][k], true, xf)
		"carrom":  # a board corner: frame, pocket, baseline circle, a few coins and the striker
			var b := Rect2(c - Vector2(44, 44) * u, Vector2(88, 88) * u)
			draw_rect(b.grow(5 * u), ink)
			draw_rect(b, CarromBoard.WOOD)
			var ply := b.grow(-10 * u)
			draw_rect(ply, CarromBoard.PLY)
			var pocket := ply.position + Vector2(9, 9) * u
			draw_circle(pocket, 9 * u, Color("16110e"))
			draw_line(ply.position + Vector2(20, 58) * u, ply.position + Vector2(68, 58) * u, CarromBoard.LINE, 2 * u)
			draw_circle(ply.position + Vector2(16, 58) * u, 5 * u, CarromBoard.RED)
			for coin in [[Vector2(40, 22), 0], [Vector2(27, 35), 1], [Vector2(50, 38), 2], [Vector2(58, 20), 1]]:
				CarromBoard.draw_piece(self, ply.position + coin[0] * u, coin[1], 0.0, u * 0.38)
			CarromBoard.draw_piece(self, ply.position + Vector2(42, 58) * u, 3, 0.4, u * 0.38)
		"pen", "penfight":  # two pens crossed on a desk corner
			var b := Rect2(c - Vector2(44, 44) * u, Vector2(88, 88) * u)
			var desk := StyleBoxFlat.new()
			desk.bg_color = PenDesk.WOOD
			desk.set_corner_radius_all(int(14 * u))
			desk.border_width_bottom = int(7 * u)
			desk.border_color = PenDesk.WOOD_DARK
			draw_style_box(desk, b)
			for k in 3:
				draw_line(b.position + Vector2(18 + k * 26, 6) * u, b.position + Vector2(14 + k * 26, 80) * u, Color(0.45, 0.24, 0.08, 0.18), 3 * u)
			var s := u * 0.3
			PenDesk.draw_pen(self, c + Vector2(-2, 6) * u, -0.75, "marker", UI.COLORS[3], 1.0, 0.0, s)
			PenDesk.draw_pen(self, c + Vector2(2, -4) * u, 0.75 + PI, "gel", UI.COLORS[0], 1.0, 0.0, s)
		"board":
			var b := Rect2(c - Vector2(42, 42) * u, Vector2(84, 84) * u)
			draw_rect(b.grow(4 * u), ink)
			draw_rect(b, Color.WHITE)
			var q := 34 * u
			for i in 4:
				var corner: Vector2 = [b.position, b.position + Vector2(b.size.x - q, 0), b.end - Vector2(q, q), b.position + Vector2(0, b.size.y - q)][i]
				draw_rect(Rect2(corner, Vector2(q, q)), UI.COLORS[i])
				draw_circle(corner + Vector2(q, q) / 2, q * 0.28, Color.WHITE)
			var m := c
			var h := 8 * u
			draw_colored_polygon(PackedVector2Array([m + Vector2(-h, -h), m + Vector2(-h, h), m]), UI.COLORS[0])
			draw_colored_polygon(PackedVector2Array([m + Vector2(-h, -h), m + Vector2(h, -h), m]), UI.COLORS[1])
			draw_colored_polygon(PackedVector2Array([m + Vector2(h, -h), m + Vector2(h, h), m]), UI.COLORS[2])
			draw_colored_polygon(PackedVector2Array([m + Vector2(-h, h), m + Vector2(h, h), m]), UI.COLORS[3])
