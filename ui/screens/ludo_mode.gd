## Ludo: pick how to play.
extends "res://ui/screen.gd"


func _init() -> void:
	title = "LUDO"


func build() -> void:
	content.add_child(UI.label("How do you want to play?", 52))
	var bots := UI.tile(UI.COLORS[3], UI.icon("robot", Color.WHITE, 170), "VS COMPUTER", "You against bots")
	bots.pressed.connect(UI.go.bind("res://ui/screens/ludo_players.gd", {"mode": "bots"}))
	content.add_child(bots)
	var local := UI.tile(UI.COLORS[1], UI.icon("pawns", Color.WHITE, 170, 2), "PASS & PLAY", "Friends on one phone")
	local.pressed.connect(UI.go.bind("res://ui/screens/ludo_players.gd", {"mode": "local"}))
	content.add_child(local)
	var lan := UI.tile(UI.COLORS[0], UI.icon("wifi", Color.WHITE, 170), "WITH FRIENDS", "Same Wi-Fi or hotspot")
	lan.pressed.connect(UI.go.bind("res://ui/screens/lan_menu.gd"))
	content.add_child(lan)
