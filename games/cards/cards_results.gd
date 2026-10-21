## Color Cards end screen: ribbon title, the winner's card big on top and everyone else's in a row
## under it. Each card shows the place medal, the player's face and what was left in their hand
## (number, action and wild cards). Same signals and fields as WinOverlay, plus `reveal`.
extends Control

signal play_again
signal home

const Rules = preload("res://games/cards/cards_rules.gd")
const CardArt = preload("res://games/cards/card_art.gd")
const FaceArt = preload("res://games/shared/face_art.gd")
const Fx = preload("res://games/shared/fx.gd")
const PLACE_TEXT := ["1st", "2nd", "3rd", "4th"]
const MEDALS := [Color("ffc312"), Color("c8d1e0"), Color("e08a4c"), Color("8c87b8")]
const REWARD := [100, 50, 25, 10]  # cosmetic stars, as WinOverlay

var ranking := []  # colors, winner first
var names := []
var me := -1
var reveal := {}  # color -> leftover card ids
var can_restart := true
var _ray_angle := 0.0
var _rays_at := Vector2.ZERO


## One player's result card, drawn in code; `s` scales everything from a 300-wide card.
class ResultCard extends Control:
	var color := Color.WHITE
	var variant := 0
	var player_name := ""
	var place := 0
	var hand := []
	var finished := false
	var winner := false

	func _draw() -> void:
		var s := size.x / 300.0
		var r := Rect2(Vector2.ZERO, size)
		var rim := StyleBoxFlat.new()
		rim.bg_color = MEDALS[0] if winner else UI.INK
		rim.set_corner_radius_all(int(30 * s))
		rim.anti_aliasing = true
		draw_style_box(rim, r)
		var face := rim.duplicate()
		face.bg_color = Color.WHITE
		face.set_corner_radius_all(int(24 * s))
		draw_style_box(face, r.grow(-8 * s))
		var band := face.duplicate()
		band.bg_color = color
		band.corner_radius_bottom_left = 0
		band.corner_radius_bottom_right = 0
		draw_style_box(band, Rect2(r.position + Vector2(8, 8) * s, Vector2(size.x - 16 * s, 150 * s)))
		FaceArt.draw(self, Vector2(size.x / 2, 92 * s), 120 * s, color, variant, finished or winner)
		# place medal, top-left
		var m := Vector2(40, 40) * s
		draw_circle(m, 30 * s, UI.INK)
		draw_circle(m, 25 * s, MEDALS[place])
		CardArt.text(self, str(place + 1), m, 34 * s)
		var fs := int(34 * s)
		var name_y := 200 * s
		draw_string_outline(UI.FONT, Vector2(10 * s, name_y), player_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20 * s, fs, int(8 * s), UI.INK)
		draw_string(UI.FONT, Vector2(10 * s, name_y), player_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20 * s, fs, Color.WHITE)
		# leftover cards by kind
		var rows := [["Numbers", 14, 0], ["Actions", 69, 0], ["Wilds", 100, 0]]
		for id in hand:
			var k := Rules.kind_of(id)
			rows[0 if k <= 9 else 1 if k < Rules.WILD else 2][2] += 1
		var y := 232 * s
		for row in rows:
			var line := Rect2(Vector2(18 * s, y), Vector2(size.x - 36 * s, 46 * s))
			draw_rect(line, Color(UI.INK, 0.08))
			CardArt.draw(self, row[1], true, Transform2D(-0.15, line.position + Vector2(24, 23) * s).scaled_local(Vector2(0.17, 0.17) * s))
			draw_string(UI.FONT, line.position + Vector2(52 * s, 33 * s), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), UI.INK)
			draw_string(UI.FONT, line.position + Vector2(0, 33 * s), str(row[2]), HORIZONTAL_ALIGNMENT_RIGHT, line.size.x - 12 * s, int(30 * s), UI.INK)
			y += 52 * s
		var total := "Finished!" if finished else "%d card%s left" % [hand.size(), "" if hand.size() == 1 else "s"]
		draw_string(UI.FONT, Vector2(0, y + 40 * s), total, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(34 * s),
			UI.COLORS[1].darkened(0.2) if finished else UI.COLORS[0].darkened(0.1))


func _ready() -> void:
	size = get_viewport_rect().size
	mouse_filter = MOUSE_FILTER_STOP  # the table underneath no longer reacts
	var oy := maxf(0.0, (size.y - 1920.0) / 2)
	_rays_at = Vector2(540, oy + 560)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	var winner: int = ranking[0]
	var won := winner == me
	Sfx.play("win" if won or me == -1 else "lose", 0.0)

	var ribbon := Panel.new()
	var style := UI.box(UI.COLORS[winner], 16, 40)
	style.border_color = UI.INK
	style.set_border_width_all(6)
	style.border_width_bottom = 18
	ribbon.add_theme_stylebox_override("panel", style)
	ribbon.size = Vector2(980, 170)
	ribbon.position = Vector2(50, -260)
	var title := UI.label("YOU WIN!" if won else "%s WINS!" % names[winner].to_upper(), 80)
	title.size = Vector2(980, 150)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ribbon.add_child(title)
	add_child(ribbon)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(ribbon, "position:y", oy + 90, 0.6)
	if me != -1 and not won:
		var sub := UI.label("You finished %s" % PLACE_TEXT[ranking.find(me)], 48, Color(1, 1, 1, 0.9))
		sub.size = Vector2(1080, 64)
		sub.position = Vector2(0, oy + 275)
		add_child(sub)

	# winner's card big on top, the rest in a row under it; they rise last place first
	var others := ranking.size() - 1
	for place in range(ranking.size() - 1, -1, -1):
		var c: int = ranking[place]
		var card := ResultCard.new()
		card.color = UI.COLORS[c]
		card.variant = c
		card.player_name = names[c]
		card.place = place
		card.hand = reveal.get(c, [])
		card.finished = card.hand.is_empty()
		card.winner = place == 0
		var w := 300.0 if place > 0 else 360.0
		var gap := (1080.0 - others * 300.0) / (others + 1)
		var at := Vector2(540 - w / 2, oy + 352) if place == 0 else Vector2(gap + (place - 1) * (300 + gap), oy + 950)
		card.size = Vector2(w, w * 1.6)
		card.position = at + Vector2(0, 700)
		card.modulate.a = 0.0
		add_child(card)
		var tw := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.3 + (ranking.size() - 1 - place) * 0.25)
		tw.tween_property(card, "position", at, 0.5)
		tw.parallel().tween_property(card, "modulate:a", 1.0, 0.2)

	# reward count-up for the local player
	if me != -1:
		var y := oy + 1455
		var star := UI.icon("star", UI.COLORS[2], 90)
		star.position = Vector2(380, y)
		add_child(star)
		var stars := UI.label("+0", 64, UI.COLORS[2], HORIZONTAL_ALIGNMENT_LEFT)
		stars.size = Vector2(300, 100)
		stars.position = Vector2(485, y - 4)
		add_child(stars)
		var tw := create_tween()
		tw.tween_interval(1.6)
		tw.tween_method(func(v: int): stars.text = "+%d" % v, 0, REWARD[ranking.find(me)], 1.0)

	var by := size.y - oy - 230
	var again := UI.button("PLAY AGAIN" if can_restart else "WAITING...", UI.COLORS[1], Vector2(480, 150), 54)
	again.disabled = not can_restart
	again.position = Vector2(40, by)
	again.pressed.connect(play_again.emit)
	add_child(again)
	var leave := UI.button("HOME", UI.ACCENT, Vector2(480, 150), 54)
	leave.position = Vector2(560, by)
	leave.pressed.connect(home.emit)
	add_child(leave)
	Fx.confetti(self, oy)


func _process(delta: float) -> void:
	_ray_angle += delta * 0.25
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.15, 0.88))
	for i in 12:
		var a := _ray_angle + i * TAU / 12
		draw_colored_polygon(PackedVector2Array([_rays_at, _rays_at + Vector2.from_angle(a) * 1600,
			_rays_at + Vector2.from_angle(a + TAU / 24) * 1600]), Color(1, 1, 1, 0.06))
