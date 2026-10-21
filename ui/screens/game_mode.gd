## Any board game: pick how to play.
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")

var game := "ludo"


func _ready() -> void:
	title = Games.LIST[game].title
	super()


func build() -> void:
	content.add_child(UI.label("How do you want to play?", 52))
	var next := "res://ui/screens/game_variant.gd" if Games.LIST[game].has("variants") else "res://ui/screens/game_players.gd"
	var bots := UI.tile(UI.COLORS[3], UI.icon("robot", Color.WHITE, 170), "VS COMPUTER", "You against bots")
	bots.pressed.connect(UI.go.bind(next, {"game": game, "mode": "bots"}))
	content.add_child(bots)
	if Games.LIST[game].local:
		var local := UI.tile(UI.COLORS[1], UI.icon("pawns", Color.WHITE, 170, 2), "PASS & PLAY", "Friends on one phone")
		local.pressed.connect(UI.go.bind(next, {"game": game, "mode": "local"}))
		content.add_child(local)
	if Games.LIST[game].lan:
		var lan := UI.tile(UI.COLORS[0], UI.icon("wifi", Color.WHITE, 170), "WITH FRIENDS", "Same Wi-Fi or hotspot")
		lan.pressed.connect(UI.go.bind(next if next.ends_with("variant.gd") else "res://ui/screens/lan_menu.gd", {"game": game, "mode": "lan"}))
		content.add_child(lan)
