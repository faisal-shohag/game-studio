## First launch (or tap on the name chip): ask the player's name, pre-filled with a random fun one.
extends "res://ui/screen.gd"

var edit := LineEdit.new()


func _init() -> void:
	show_back = false


func build() -> void:
	var mascot := UI.icon("pawn", UI.COLORS[0], 320)
	mascot.bob = true
	content.add_child(mascot)
	content.add_child(UI.label("What's your name?", 84))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	edit.text = UI.player_name if UI.player_name != "" else UI.random_name()
	edit.max_length = UI.NAME_MAX
	edit.custom_minimum_size = Vector2(660, 150)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 56)
	edit.select_all_on_focus = true
	edit.text_submitted.connect(func(_t): _done())
	row.add_child(edit)
	var shuffle := UI.button("", UI.COLORS[3], Vector2(150, 150))
	var dice := UI.icon("dice", Color.WHITE, 150)
	dice.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dice.offset_bottom = -12
	shuffle.add_child(dice)
	shuffle.pressed.connect(func(): edit.text = UI.random_name())
	row.add_child(shuffle)
	content.add_child(row)
	content.add_child(UI.label("Tap the dice for a new name", 40, Color(1, 1, 1, 0.75)))
	var play := UI.button("LET'S PLAY!", UI.COLORS[1], Vector2(800, 180), 76)
	play.pressed.connect(_done)
	content.add_child(play)


func _done() -> void:
	var n := edit.text.strip_edges()
	UI.player_name = n if n != "" else UI.random_name()
	UI.reset_to("res://ui/screens/home.gd")
