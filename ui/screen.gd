## Base for menu screens: full-rect, top bar (back arrow + title), centered content column.
## Subclasses override build() and fill `content` (and optionally `top`).
extends Control

var title := ""
var show_back := true
var top := HBoxContainer.new()
var content := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 40
	col.offset_right = -40
	col.offset_top = 70
	col.offset_bottom = -70
	add_child(col)
	top.custom_minimum_size.y = 130
	top.add_theme_constant_override("separation", 20)
	col.add_child(top)
	if show_back:
		var b := UI.button("", UI.INK.lightened(0.3), Vector2(130, 130))
		var arrow := UI.icon("back", Color.WHITE, 110)
		arrow.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		arrow.offset_bottom = -10
		b.add_child(arrow)
		b.pressed.connect(UI.back)
		top.add_child(b)
	var heading := UI.label(title, 80)
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(heading)
	if show_back:
		var spacer := Control.new()  # keeps the title centered
		spacer.custom_minimum_size.x = 130
		top.add_child(spacer)
	var center := CenterContainer.new()
	center.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(center)
	content.add_theme_constant_override("separation", 40)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(content)
	build()
	UI.pop_in(content.get_children())


func build() -> void:
	pass
