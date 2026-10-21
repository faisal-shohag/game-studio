## Any board game: how many players. Games with faces start right away (you sit at the bottom;
## pass-and-play friends take the seats bots would).
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
const GameColor = preload("res://ui/screens/game_color.gd")

var game := "ludo"
var mode := "bots"  # bots | local
var variant := ""  # rule set, for games that have them
var rounds := 0  # match length, for games that have them


func _init() -> void:
	title = "PLAYERS"


func build() -> void:
	content.add_child(UI.label("How many players?", 52))
	var faces: bool = Games.LIST[game].faces
	for n in ([2, 4] if variant == "classic" else [2, 3, 4]):  # Classic is 1v1 or 2v2
		var t := UI.tile(UI.COLORS[n - 1], UI.icon("faces" if faces else "pawns", Color.WHITE, 240, n), "%d PLAYERS" % n, "", Vector2(900, 240), 80)
		if faces:
			t.pressed.connect(UI.go.bind(Games.LIST[game].scene, _face_props(n)))
		else:
			t.pressed.connect(UI.go.bind("res://ui/screens/game_color.gd", {"game": game, "mode": mode, "count": n}))
		content.add_child(t)


## Seats for a faces game: you at the bottom, bots (or friends) round the table.
func _face_props(n: int) -> Dictionary:
	var seats := GameColor.bot_seats(0, n)
	var props := {"seats": seats, "me": 0}
	if mode == "local":
		var names := ["", "", "", ""]
		var k := 0
		for c in 4:
			if seats[c] != "off":
				seats[c] = "human"
				k += 1
				names[c] = UI.player_name if c == 0 else "Player %d" % k
		props["names"] = names
	if variant != "":
		props["variant"] = variant
	if rounds > 0:
		props["rounds"] = rounds
	return props
