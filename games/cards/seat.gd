## A player at the card table: face portrait with the name under it, a card-count badge, a note
## bubble ("Thinking...", "1st place"), a glow on their turn, and their hand as a fan of backs
## pointing at the table. Shows a CATCH! bubble when they forgot to call their last card.
extends Control

signal catch_pressed

const FaceArt = preload("res://games/shared/face_art.gd")
const CardArt = preload("res://games/cards/card_art.gd")
const Avatar = preload("res://core/avatar.gd")
const PORTRAIT := 150.0
const FAN_MAX := 12
const FAN_SCALE := 0.42

var color := Color.WHITE
var variant := 0
var player_name := ""
var avatar := {}  # the player's own look; {} = this seat's face
var facing := Vector2.DOWN  # from the portrait toward the table: where the fan goes
var fan_visible := true
var count := 0:
	set(v):
		count = v
		queue_redraw()
var note := "":
	set(v):
		note = v
		queue_redraw()
var happy := true:
	set(v):
		happy = v
		queue_redraw()
var active := false:
	set(v):
		if v != active:
			active = v
			_pulse(v)
			queue_redraw()
var _pulse_tw: Tween
var _catch: Button
var _catch_tw: Tween


func _ready() -> void:
	size = Vector2(PORTRAIT, PORTRAIT)
	pivot_offset = size / 2
	mouse_filter = MOUSE_FILTER_IGNORE
	var label := UI.label(player_name, 34)
	label.position = Vector2(-45, PORTRAIT + 2)
	label.size = Vector2(PORTRAIT + 90, 48)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(label)
	_catch = UI.button("CATCH!", UI.COLORS[2], Vector2(230, 96), 42)
	_catch.position = Vector2((PORTRAIT - 230) / 2, -112)
	_catch.pressed.connect(catch_pressed.emit)
	_catch.hide()
	add_child(_catch)


## Where this player's cards fly to and from (global).
func fan_center() -> Vector2:
	return global_position + _fan_at() if fan_visible else global_position + size / 2


## Fan middle in local coords: beside the portrait, past the name when it fans downward.
func _fan_at() -> Vector2:
	return size / 2 + facing * (PORTRAIT * 0.5 + 80 + (55 if facing.y > 0.5 else 0))


func show_catch(on: bool) -> void:
	if on == _catch.visible:
		return
	_catch.visible = on
	if _catch_tw:
		_catch_tw.kill()
		_catch_tw = null
	if on:
		var w := _catch.size.x
		_catch.position.x = clampf((PORTRAIT - w) / 2, 16 - position.x, 1064 - position.x - w)  # stay on screen
		_catch.scale = Vector2.ZERO
		_catch.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(_catch, "scale", Vector2.ONE, 0.25)
		_catch_tw = _catch.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_catch_tw.tween_property(_catch, "position:y", -124.0, 0.3)
		_catch_tw.tween_property(_catch, "position:y", -112.0, 0.3)


func _pulse(on: bool) -> void:
	if _pulse_tw:
		_pulse_tw.kill()
		_pulse_tw = null
		scale = Vector2.ONE
	if on:
		_pulse_tw = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse_tw.tween_property(self, "scale", Vector2(1.06, 1.06), 0.45)
		_pulse_tw.tween_property(self, "scale", Vector2.ONE, 0.45)


func _draw() -> void:
	var c := size / 2
	if fan_visible:
		_draw_fan(_fan_at())
	if active:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(UI.COLORS[2], 0.9)
		glow.set_corner_radius_all(34)
		glow.anti_aliasing = true
		draw_style_box(glow, Rect2(Vector2.ZERO, size).grow(12))
	if not Avatar.draw(self, c, PORTRAIT * 0.92, avatar, color, false, happy):
		FaceArt.draw(self, c, PORTRAIT * 0.92, color, variant, happy)
	# card-count badge on the top-right corner
	var at := Vector2(PORTRAIT - 6, 8)
	draw_circle(at, 30, UI.INK)
	draw_circle(at, 25, UI.COLORS[0] if count == 1 else UI.ACCENT)
	CardArt.text(self, str(count), at, 36)
	if note != "":
		var w := UI.FONT.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 36
		var pill := StyleBoxFlat.new()
		pill.bg_color = UI.INK
		pill.set_corner_radius_all(24)
		pill.anti_aliasing = true
		var r := Rect2(Vector2(c.x - w / 2, PORTRAIT - 40), Vector2(w, 46))
		draw_style_box(pill, r)
		draw_string(UI.FONT, Vector2(r.position.x, r.position.y + 33), note, HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color.WHITE)


## The hand as backs fanned across `at`, standing on the player's side of it.
func _draw_fan(at: Vector2) -> void:
	var n := mini(count, FAN_MAX)
	var side := facing.orthogonal()
	var step := minf(30.0, 260.0 / maxf(n - 1, 1))
	var base := facing.angle() - PI / 2  # card tops point back at the player
	for i in n:
		var t := i - (n - 1) / 2.0
		var xf := Transform2D(base + t * 0.1, at + side * t * step - facing * t * t * 1.6)  # a held fan curves back
		CardArt.draw(self, -1, false, xf.scaled_local(Vector2(FAN_SCALE, FAN_SCALE)))
