## Games with rule sets (Carrom): pick one before the player count.
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
## variant -> [color, title, one-line rules]
const INFO := {
	"classic": [3, "CLASSIC", "White vs black. Cover the queen!"],
	"freestyle": [0, "FREESTYLE", "Every coin scores. Queen 50!"],
}

var game := "carrom"
var mode := "bots"


func _init() -> void:
	title = "RULES"


func build() -> void:
	content.add_child(UI.label("Which game?", 52))
	for v in Games.LIST[game].variants:
		var info: Array = INFO[v]
		var t := UI.tile(UI.COLORS[info[0]], UI.icon(game, Color.WHITE, 200), info[1], info[2], Vector2(940, 300), 80)
		t.pressed.connect(UI.go.bind("res://ui/screens/game_players.gd", {"game": game, "mode": mode, "variant": v}))
		content.add_child(t)
