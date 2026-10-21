## Home: logo, playable game cards, locked "coming soon" cards, name chip.
extends "res://ui/screen.gd"

const SOON := ["Carrom", "Penfight"]


func _init() -> void:
	show_back = false


func build() -> void:
	UI.reset_network()  # back from a LAN game
	var sound := UI.button("", UI.INK.lightened(0.3), Vector2(110, 110))
	var speaker := UI.icon("mute" if Sfx.muted else "sound", Color.WHITE, 100)
	speaker.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	speaker.offset_bottom = -10
	sound.add_child(speaker)
	sound.pressed.connect(func():
		Sfx.set_muted(not Sfx.muted)
		speaker.kind = "mute" if Sfx.muted else "sound"
		speaker.queue_redraw())
	top.add_child(sound)
	top.move_child(sound, 0)
	var chip := UI.button(UI.player_name, UI.INK.lightened(0.3), Vector2(0, 110), 40)
	chip.pressed.connect(func(): UI.go("res://ui/screens/welcome.gd", {"show_back": true}))
	top.add_child(chip)

	var logo := UI.label("GAME\nSTUDIO", 150, UI.COLORS[2])
	logo.add_theme_constant_override("outline_size", 24)
	logo.add_theme_constant_override("line_spacing", -30)
	content.add_child(logo)
	content.add_child(UI.label("Classic games, together", 44, Color(1, 1, 1, 0.8)))

	var ludo := UI.tile(UI.COLORS[0], UI.icon("board", Color.WHITE, 200), "LUDO", "2-4 players", Vector2(940, 250), 96)
	ludo.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "ludo"}))
	content.add_child(ludo)
	var snakes := UI.tile(UI.COLORS[1], UI.icon("ladder", Color.WHITE, 200), "SNAKES & LADDERS", "2-4 players", Vector2(940, 250), 64)
	snakes.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "snakes"}))
	content.add_child(snakes)
	var cards := UI.tile(UI.COLORS[3], UI.icon("cards", Color.WHITE, 200), "COLOR CARDS", "2-4 players", Vector2(940, 250), 80)
	cards.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "cards"}))
	content.add_child(cards)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 30)
	for game in SOON:
		var t := UI.tile(UI.LOCKED, UI.icon("lock", Color.WHITE, 80), game, "Coming soon", Vector2(455, 190), 38)
		t.disabled = true
		grid.add_child(t)
	content.add_child(grid)
