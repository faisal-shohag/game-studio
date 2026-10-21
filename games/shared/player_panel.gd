## Player card beside the board: avatar pawn, name, pawns-home dots or a short note.
## Glows and pulses while it's this player's turn.
extends Control

signal tapped

const PawnArt = preload("res://games/shared/pawn_art.gd")

var color := Color.WHITE
var player_name := ""
var home := 0:
	set(v):
		home = v
		queue_redraw()
var note := "":  # "Thinking...", "No moves", ... replaces the dots
	set(v):
		note = v
		queue_redraw()
var status := "":  # games without home dots ("Square 37"); shown when there's no note
	set(v):
		status = v
		queue_redraw()
var active := false:
	set(v):
		active = v
		_pulse(v)
		queue_redraw()
var _pulse_tw: Tween
var _name := Label.new()


func _ready() -> void:
	pivot_offset = size / 2
	_name.position = Vector2(160, 24)
	_name.size = Vector2(size.x - 175, 64)
	_name.text = player_name
	_name.add_theme_font_size_override("font_size", 34)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_name)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()


func _pulse(on: bool) -> void:
	if _pulse_tw:
		_pulse_tw.kill()
		_pulse_tw = null
		scale = Vector2.ONE
	if on:
		_pulse_tw = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse_tw.tween_property(self, "scale", Vector2(1.05, 1.05), 0.45)
		_pulse_tw.tween_property(self, "scale", Vector2.ONE, 0.45)


func _draw() -> void:
	var bg := UI.box(color if active else UI.INK.lightened(0.25), 10, 36)
	if active:
		bg.set_border_width_all(6)
		bg.border_width_bottom = 14
		bg.border_color = Color.WHITE
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var av := Vector2(84, size.y / 2 - 6)
	draw_circle(av, 64, Color.WHITE)
	draw_circle(av, 58, color.lightened(0.55))
	PawnArt.draw(self, av + Vector2(0, 40), 0.85, color)
	var text := note if note != "" else status
	if text != "":
		draw_string_outline(UI.FONT, Vector2(162, 130), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 175, 34, 10, UI.INK)
		draw_string(UI.FONT, Vector2(162, 130), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 175, 34, Color.WHITE)
	else:
		for i in 4:
			var at := Vector2(180 + i * 42, 118)
			draw_circle(at, 15, UI.INK)
			draw_circle(at, 11, Color.WHITE if i < home else Color(1, 1, 1, 0.25))
