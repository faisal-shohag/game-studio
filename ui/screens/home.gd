## Home: logo, game cards, name chip.
extends "res://ui/screen.gd"


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
	# profile chip: your avatar and name; tap to edit
	var chip := UI.button("", UI.INK.lightened(0.3), Vector2(0, 110), 40)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -24
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var face := UI.icon("avatar", UI.COLORS[0], 84)
	face.avatar = UI.avatar
	face.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(face)
	var label := UI.label(UI.player_name, 40)
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(label)
	chip.add_child(row)
	chip.custom_minimum_size.x = 14 + 84 + 14 + UI.FONT.get_string_size(UI.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x + 40
	chip.pressed.connect(func(): UI.go("res://ui/screens/welcome.gd", {"show_back": true}))
	top.add_child(chip)

	var logo := UI.label("GAME\nSTUDIO", 150, UI.COLORS[2])
	logo.add_theme_constant_override("outline_size", 24)
	logo.add_theme_constant_override("line_spacing", -30)
	content.add_child(logo)
	content.add_child(UI.label("Classic games, together", 44, Color(1, 1, 1, 0.8)))

	var ludo := UI.tile(UI.COLORS[0], UI.icon("board", Color.WHITE, 200), "LUDO", "2-4 players", Vector2(940, 220), 96)
	ludo.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "ludo"}))
	content.add_child(ludo)
	var snakes := UI.tile(UI.COLORS[1], UI.icon("ladder", Color.WHITE, 200), "SNAKES & LADDERS", "2-4 players", Vector2(940, 220), 64)
	snakes.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "snakes"}))
	content.add_child(snakes)
	var cards := UI.tile(UI.COLORS[3], UI.icon("cards", Color.WHITE, 200), "COLOR CARDS", "2-4 players", Vector2(940, 220), 80)
	cards.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "cards"}))
	content.add_child(cards)
	var carrom := UI.tile(UI.COLORS[2], UI.icon("carrom", Color.WHITE, 200), "CARROM", "2-4 players", Vector2(940, 220), 96)
	carrom.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "carrom"}))
	content.add_child(carrom)
	var pens := UI.tile(UI.COLORS[0].lerp(UI.COLORS[3], 0.5), UI.icon("pen", Color.WHITE, 200), "PEN FIGHT", "2-4 players", Vector2(940, 220), 96)
	pens.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": "penfight"}))
	content.add_child(pens)
