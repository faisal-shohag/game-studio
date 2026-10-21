## Games with rule sets (Carrom): pick one before the player count (or, with friends, before
## creating a room: a room keeps the rules it was made with).
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
## variant -> [color, title, one-line rules]
const INFO := {
	"classic": [3, "CLASSIC", "White vs black. Cover the queen!"],
	"freestyle": [0, "FREESTYLE", "Every coin scores. Queen 50!"],
}

var game := "carrom"
var mode := "bots"  # bots | local | lan


func _init() -> void:
	title = "RULES"


func build() -> void:
	content.add_child(UI.label("Which game?", 52))
	for v in Games.LIST[game].variants:
		var info: Array = INFO[v]
		var t := UI.tile(UI.COLORS[info[0]], UI.icon(game, Color.WHITE, 200), info[1], info[2], Vector2(940, 300), 80)
		if mode == "lan":
			t.pressed.connect(UI.go.bind("res://ui/screens/lan_menu.gd", {"game": game, "variant": v}))
		else:
			t.pressed.connect(UI.go.bind("res://ui/screens/game_players.gd", {"game": game, "mode": mode, "variant": v}))
		content.add_child(t)
