## Any board game: how many players. Games with faces start right away (you sit at the bottom).
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
const GameColor = preload("res://ui/screens/game_color.gd")

var game := "ludo"
var mode := "bots"  # bots | local


func _init() -> void:
	title = "PLAYERS"


func build() -> void:
	content.add_child(UI.label("How many players?", 52))
	var faces: bool = Games.LIST[game].faces
	for n in [2, 3, 4]:
		var t := UI.tile(UI.COLORS[n - 1], UI.icon("faces" if faces else "pawns", Color.WHITE, 240, n), "%d PLAYERS" % n, "", Vector2(900, 240), 80)
		if faces:
			t.pressed.connect(UI.go.bind(Games.LIST[game].scene, {"seats": GameColor.bot_seats(0, n), "me": 0}))
		else:
			t.pressed.connect(UI.go.bind("res://ui/screens/game_color.gd", {"game": game, "mode": mode, "count": n}))
		content.add_child(t)
