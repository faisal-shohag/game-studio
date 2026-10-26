## Home: logo, game cards, name chip.
extends "res://ui/screen.gd"


func _init() -> void:
	show_back = false


func build() -> void:
	UI.reset_network()  # back from a LAN game
	var sound := UI.icon_button("mute" if Sfx.muted else "sound", 110)
	var speaker: Control = sound.get_child(0)
	sound.pressed.connect(func():
		Sfx.set_muted(not Sfx.muted)
		speaker.kind = "mute" if Sfx.muted else "sound"
		speaker.queue_redraw())
	top.add_child(sound)
	top.move_child(sound, 0)
	# profile chip: your avatar and name; tap to edit
	var chip := UI.button("", UI.CREAM, Vector2(0, 110), 40)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -24
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var face := UI.icon("avatar", UI.COLORS[0], 84)
	face.avatar = UI.avatar
	face.round = true
	face.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(face)
	var label := UI.label(UI.player_name, 40)
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(label)
	chip.add_child(row)
	chip.custom_minimum_size.x = 14 + 84 + 14 + UI.FONT.get_string_size(UI.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x + 40
	chip.pressed.connect(func(): UI.go("res://ui/screens/welcome.gd", {"show_back": true}))
	top.add_child(chip)

	var logo := UI.label("GAME STUDIO", 120, UI.ACCENT)
	logo.add_theme_color_override("font_shadow_color", UI.ACCENT.darkened(0.35))
	logo.add_theme_constant_override("shadow_offset_y", 8)
	content.add_child(logo)
	content.add_child(UI.label("Classic games, together", 44, UI.INK_SOFT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 30)
	for g in [["ludo", "LUDO", "board", 0], ["snakes", "SNAKES &
LADDERS", "ladder", 1], ["cards", "COLOR
CARDS", "cards", 3],
			["carrom", "CARROM", "carrom", 2], ["penfight", "PEN FIGHT", "pen", -1],
			["sholo", "SHOLO GUTI", "sholo", 2], ["dots", "DOTS &
BOXES", "dots", 1]]:
		var color: Color = UI.ACCENT if g[3] < 0 else UI.COLORS[g[3]]
		var card := UI.card_tile(color, UI.icon(g[2], UI.ink_on(color), 150), g[1], Vector2(470, 310), 52)  # 4 rows fit the screen
		card.pressed.connect(UI.go.bind("res://ui/screens/game_mode.gd", {"game": g[0]}))
		grid.add_child(card)
	content.add_child(grid)
