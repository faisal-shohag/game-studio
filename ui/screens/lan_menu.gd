## LAN: create or join a room.
extends "res://ui/screen.gd"

var game := "ludo"  # what a room created here plays; joiners learn it from the host
var variant := ""  # its rule set, for games that have them


func _init() -> void:
	title = "WITH FRIENDS"


func build() -> void:
	UI.reset_network()  # back from a room
	content.add_child(UI.label("Same Wi-Fi or phone hotspot", 48))
	var host := UI.tile(UI.COLORS[1], UI.icon("wifi", Color.WHITE, 170), "CREATE ROOM", "Friends join you")
	host.pressed.connect(UI.go.bind("res://ui/screens/lan_room.gd", {"hosting": true, "game": game, "variant": variant}))
	content.add_child(host)
	var join := UI.tile(UI.COLORS[3], UI.icon("pawns", Color.WHITE, 170, 2), "JOIN ROOM", "Find a friend's room")
	join.pressed.connect(UI.go.bind("res://ui/screens/lan_find.gd"))
	content.add_child(join)
