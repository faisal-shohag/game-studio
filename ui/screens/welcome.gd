## Profile: first launch, or a tap on the Home name chip. Pick a face or your own photo, and a
## name (pre-filled with a random fun one). Nothing is saved until LET'S PLAY / SAVE.
extends "res://ui/screen.gd"

const Avatar = preload("res://core/avatar.gd")

## Unsaved choices, kept across the photo picker and crop screens (this screen is rebuilt after).
var draft_name := ""
var draft_avatar := {}
var edit := LineEdit.new()
var choice := {}
var preview: Control
var tiles := []  # [button, avatar] per choice tile
var photo := {}  # the photo the photo tile offers, if any


func _init() -> void:
	show_back = false


func build() -> void:
	var first := UI.player_name == ""
	choice = draft_avatar if not draft_avatar.is_empty() else UI.avatar
	photo = choice if choice.has("photo") else UI.avatar if UI.avatar.has("photo") else {}
	preview = UI.icon("avatar", UI.COLORS[0], 250)
	preview.avatar = choice
	preview.bob = true
	content.add_child(preview)
	content.add_child(UI.label("Choose your look", 52))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	for n in Avatar.FACES:
		_tile(grid, {"face": n}, UI.COLORS[n % 4])
	_tile(grid, photo, UI.INK.lightened(0.3), true)
	content.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	edit.text = draft_name if draft_name != "" else UI.player_name if not first else UI.random_name()
	edit.max_length = UI.NAME_MAX
	edit.custom_minimum_size = Vector2(660, 140)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 56)
	edit.select_all_on_focus = true
	edit.text_submitted.connect(func(_t): _done())
	row.add_child(edit)
	var shuffle := UI.button("", UI.COLORS[3], Vector2(140, 140))
	var dice := UI.icon("dice", Color.WHITE, 140)
	dice.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dice.offset_bottom = -12
	shuffle.add_child(dice)
	shuffle.pressed.connect(func(): edit.text = UI.random_name())
	row.add_child(shuffle)
	content.add_child(row)
	var play := UI.button("LET'S PLAY!" if first else "SAVE", UI.COLORS[1], Vector2(800, 160), 72)
	play.pressed.connect(_done)
	content.add_child(play)
	_refresh()


## One choice in the grid. The photo tile shows the photo (or a camera) and opens the picker.
func _tile(grid: GridContainer, a: Dictionary, color: Color, is_photo := false) -> void:
	var b := UI.button("", color, Vector2(190, 190))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_bottom = -12
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var icon: Control
	if is_photo and a.is_empty():
		icon = UI.icon("camera", Color.WHITE, 110)
	else:
		icon = UI.icon("avatar", color, 110 if is_photo else 150)
		icon.avatar = a
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	if is_photo:
		col.add_child(UI.label("PHOTO" if a.is_empty() else "CHANGE", 30))
	b.add_child(col)
	b.pressed.connect(func():
		if is_photo and (a.is_empty() or choice == a):
			_pick_photo()
		else:
			choice = a
			_refresh())
	grid.add_child(b)
	tiles.append([b, a])


func _refresh() -> void:
	preview.avatar = choice
	preview.queue_redraw()
	for t in tiles:
		var b: Button = t[0]
		var picked: bool = t[1] == choice and not choice.is_empty()
		var style: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		style.set_border_width_all(10 if picked else 0)
		style.border_width_bottom = 18 if picked else 12
		style.border_color = Color.WHITE if picked else style.bg_color.darkened(0.3)
		b.add_theme_stylebox_override("normal", style)
		b.add_theme_stylebox_override("hover", style)


func _pick_photo() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		UI.toast("Photos aren't supported here", UI.COLORS[0])
		return
	var filters := PackedStringArray(["image/*"] if OS.get_name() == "Android" else ["*.png, *.jpg, *.jpeg, *.webp ; Photos"])
	DisplayServer.file_dialog_show("Choose a photo", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_picked)


func _on_picked(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if not ok or paths.is_empty() or UI.current != self:
		return
	var img := Avatar.load_source(FileAccess.get_file_as_bytes(paths[0]))
	if img == null:
		UI.toast("Couldn't open that photo", UI.COLORS[0])
		return
	# remember the unsaved name and choice: this screen is rebuilt when the crop screen returns
	UI.current_entry[1] = UI.current_entry[1].merged({"draft_name": edit.text, "draft_avatar": choice}, true)
	UI.go("res://ui/screens/photo_crop.gd", {"image": img})


func _done() -> void:
	var n := edit.text.strip_edges()
	UI.player_name = n if n != "" else UI.random_name()
	UI.avatar = choice
	UI.reset_to("res://ui/screens/home.gd")
