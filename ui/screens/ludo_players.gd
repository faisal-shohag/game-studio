## Ludo: how many players.
extends "res://ui/screen.gd"

var mode := "bots"  # bots | local


func _init() -> void:
	title = "PLAYERS"


func build() -> void:
	content.add_child(UI.label("How many players?", 52))
	for n in [2, 3, 4]:
		var t := UI.tile(UI.COLORS[n - 1], UI.icon("pawns", Color.WHITE, 240, n), "%d PLAYERS" % n, "", Vector2(900, 240), 80)
		t.pressed.connect(UI.go.bind("res://ui/screens/ludo_color.gd", {"mode": mode, "count": n}))
		content.add_child(t)
