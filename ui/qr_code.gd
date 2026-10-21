## A QR code on a white rounded card with the 4-module quiet zone. Modules snap to whole pixels so
## the code stays crisp for cameras. Emits tapped when touched.
extends Control

signal tapped

const Qr = preload("res://core/qr.gd")

var text := "":
	set(v):
		text = v
		_matrix = Qr.encode(v)
		queue_redraw()
var _matrix := []


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var card := StyleBoxFlat.new()
	card.bg_color = Color.WHITE
	card.set_corner_radius_all(int(side * 0.06))
	card.anti_aliasing = true
	card.shadow_color = Color(0, 0, 0, 0.25)
	card.shadow_size = 6
	card.shadow_offset = Vector2(0, 6)
	var at := (size - Vector2(side, side)) / 2
	draw_style_box(card, Rect2(at, Vector2(side, side)))
	if _matrix.is_empty():
		return
	var n := _matrix.size()
	var cell := floorf(side / (n + 8))
	var origin := (at + (Vector2(side, side) - Vector2(n, n) * cell) / 2).floor()
	for y in n:
		var row: PackedByteArray = _matrix[y]
		for x in n:
			if row[x] == 1:
				draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)), UI.INK)
