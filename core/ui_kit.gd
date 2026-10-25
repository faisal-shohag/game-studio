## UI kit (autoload "UI"): palette, theme, chunky buttons, icons, screen navigation, settings.
extends Node

const Icon = preload("res://ui/icon.gd")
const Avatar = preload("res://core/avatar.gd")
const COLORS := [Color("f25c54"), Color("6cc551"), Color("ffc93c"), Color("4aa3ff")]
const NAMES := ["Red", "Green", "Yellow", "Blue"]
const INK := Color("5a3420")  # outlines and dark text: warm brown
const INK_SOFT := Color(INK, 0.65)  # subtitles and hints
const CREAM := Color("fff5e4")  # panels, dialogs, plain buttons
const ACCENT := Color("f59a3c")
const LOCKED := Color("d3c2a5")
const BG_TOP := Color("f7e6c8")
const BG_BOTTOM := Color("eac48e")
const FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const SETTINGS_PATH := "user://settings.cfg"
const PHOTO_PATH := "user://avatar.jpg"
const NAME_MAX := 16
const ADJECTIVES := ["Lucky", "Happy", "Brave", "Swift", "Super", "Mighty", "Crazy", "Royal", "Sunny", "Ninja", "Turbo", "Jolly"]
const ANIMALS := ["Tiger", "Panda", "Fox", "Lion", "Owl", "Shark", "Koala", "Eagle", "Bear", "Wolf", "Cobra", "Yak"]

signal _dialog_closed(yes: bool)


## Behind every screen: faint wood grain and a few leaves peeking in at the bottom corners.
class Decor extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7  # same grain every time
		var grain := Color(UI.INK, 0.05)
		for i in 16:
			var y := rng.randf() * size.y
			var amp := rng.randf_range(4, 14)
			var freq := rng.randf_range(0.004, 0.01)
			var pts := PackedVector2Array()
			for x in range(-20, int(size.x) + 40, 40):
				pts.append(Vector2(x, y + sin(x * freq + i) * amp))
			draw_polyline(pts, grain, rng.randf_range(2, 4), true)
		for k in 3:  # knots
			var at := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			for r in [10, 20, 30]:
				draw_set_transform(at, 0.0, Vector2(2.2, 1))
				draw_arc(Vector2.ZERO, r, 0, TAU, 32, grain, 3, true)
		draw_set_transform(Vector2.ZERO)
		for l in [[Vector2(-10, size.y - 120), -0.5], [Vector2(40, size.y - 30), -1.1],
				[Vector2(size.x + 10, size.y - 150), PI + 0.5], [Vector2(size.x - 50, size.y - 20), PI + 1.0]]:
			_leaf(l[0], l[1], 150.0)

	## A leaf from its stem at `at`, pointing along `angle`.
	func _leaf(at: Vector2, angle: float, length: float) -> void:
		var pts := PackedVector2Array()
		for i in 17:  # two arcs meeting at the tip
			var t := i / 16.0
			pts.append(Vector2(t * length, sin(t * PI) * length * 0.28))
		for i in range(15, 0, -1):
			var t := i / 16.0
			pts.append(Vector2(t * length, -sin(t * PI) * length * 0.28))
		var xf := Transform2D(angle, at)
		draw_colored_polygon(xf * pts, Color("8cc063"))
		draw_line(xf * Vector2.ZERO, xf * Vector2(length * 0.9, 0), Color("6a9c45"), 4, true)

var settings := ConfigFile.new()
var history := []  # [what, props] of screens to return to
var current: Node
var current_entry := []
var _dialog: CanvasLayer
## A full-screen layer over the current screen (an enlarged picture...): back closes it first.
var overlay: Node

var player_name: String:
	get:
		return settings.get_value("player", "name", "")
	set(v):
		settings.set_value("player", "name", v)
		settings.save(SETTINGS_PATH)

## The player's avatar ({"face": n} or {"photo": jpeg bytes}). Before one is chosen, a random face.
var avatar: Dictionary:
	get:
		if _avatar.is_empty():
			var face: int = settings.get_value("player", "face", -2)
			if face == -1 and FileAccess.file_exists(PHOTO_PATH):
				_avatar = Avatar.clean({"photo": FileAccess.get_file_as_bytes(PHOTO_PATH)})
			elif face >= 0:
				_avatar = Avatar.clean({"face": face})
			if _avatar.is_empty():
				_avatar = {"face": randi() % Avatar.FACES}
		return _avatar
	set(v):
		if v.has("photo"):
			var f := FileAccess.open(PHOTO_PATH, FileAccess.WRITE)
			f.store_buffer(v.photo)
			f.close()
			settings.set_value("player", "face", -1)
		else:
			settings.set_value("player", "face", v.get("face", 0))
		settings.save(SETTINGS_PATH)
		_avatar = v
var _avatar := {}


func _ready() -> void:
	settings.load(SETTINGS_PATH)
	get_tree().quit_on_go_back = false  # Android back goes through back(); project setting alone didn't stick
	get_tree().root.theme = _make_theme()
	ThemeDB.fallback_font = FONT  # for controls the root theme can't reach
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, BG_TOP)
	grad.gradient.set_color(1, BG_BOTTOM)
	grad.fill_from = Vector2(0.5, 0)
	grad.fill_to = Vector2(0.5, 1)
	var bg := TextureRect.new()
	bg.texture = grad
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = -1
	layer.add_child(bg)
	var decor := Decor.new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(decor)
	add_child(layer)


func random_name() -> String:
	return "%s %s %d" % [ADJECTIVES.pick_random(), ANIMALS.pick_random(), randi_range(10, 99)]


# --- navigation ---------------------------------------------------------------

## Open a screen on top of the history. `what`: res path, PackedScene or script.
## `props` are set on the new node before it enters the tree.
func go(what, props := {}) -> void:
	if current:
		history.append(current_entry)
	_show(what, props, 1)


## Open a screen and forget the history (Home, after a game).
func reset_to(what, props := {}) -> void:
	history.clear()
	_show(what, props, -1)


## Reopen the current screen fresh (Play Again). `overrides` replace some props.
func restart(overrides := {}) -> void:
	var props: Dictionary = current_entry[1].duplicate()
	props.merge(overrides, true)
	_show(current_entry[0], props, 1)


## Back to the previous screen, reopening it with some props changed (a picker handing back
## its result: the screen it returns to was freed and is rebuilt from these props).
func back_with(props: Dictionary) -> void:
	if not history.is_empty():
		history.back()[1] = history.back()[1].merged(props, true)
	back()


## Android back / back arrow. A screen can take over with `on_back()`.
func back() -> void:
	if _dialog:
		_dialog_closed.emit(false)
	elif is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	elif current and current.has_method("on_back"):
		current.on_back()
	elif history.is_empty():
		get_tree().quit()
	else:
		var e: Array = history.pop_back()
		_show(e[0], e[1], -1)


## Modal yes/no card over everything. Back (or the left button) answers no.
func confirm(title: String, text: String, yes := "LEAVE", no := "STAY") -> bool:
	if _dialog:
		return false
	var view := get_viewport().get_visible_rect().size
	_dialog = CanvasLayer.new()
	_dialog.layer = 50
	var root := Control.new()
	root.theme = get_tree().root.theme  # themes don't flow through CanvasLayers
	root.size = view
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.45)
	dim.size = view
	root.add_child(dim)
	var center := CenterContainer.new()
	center.size = view
	root.add_child(center)
	var card := PanelContainer.new()
	var style := box(CREAM, 14, 48)
	style.set_content_margin_all(56)
	card.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 36)
	col.add_child(label(title, 80))
	col.add_child(label(text, 44, INK_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	var b_no := button(no, COLORS[1], Vector2(340, 140))
	b_no.pressed.connect(_dialog_closed.emit.bind(false))
	row.add_child(b_no)
	var b_yes := button(yes, COLORS[0], Vector2(340, 140))
	b_yes.pressed.connect(_dialog_closed.emit.bind(true))
	row.add_child(b_yes)
	col.add_child(row)
	card.add_child(col)
	center.add_child(card)
	_dialog.add_child(root)
	get_tree().root.add_child(_dialog)
	card.resized.connect(func(): card.pivot_offset = card.size / 2)
	card.scale = Vector2(0.7, 0.7)
	card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(card, "scale", Vector2.ONE, 0.25)
	var answer: bool = await _dialog_closed
	_dialog.queue_free()
	_dialog = null
	return answer


## Pill message that slides down from the top, waits, and slides away.
func toast(text: String, color := INK) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	var pill := Button.new()  # a Button only for its auto-sized styled box; it ignores taps
	pill.theme = get_tree().root.theme
	pill.text = text
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_font_size_override("font_size", 46)
	pill.add_theme_stylebox_override("normal", box(color, 10, 60))
	pill.add_theme_color_override("font_color", ink_on(color))
	layer.add_child(pill)
	get_tree().root.add_child(layer)
	await get_tree().process_frame  # let the pill size itself
	var w := get_viewport().get_visible_rect().size.x
	pill.position = Vector2((w - pill.size.x) / 2, -200)
	var tw := pill.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pill, "position:y", 70.0, 0.35)
	tw.tween_interval(1.8)
	tw.tween_property(pill, "position:y", -200.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(layer.queue_free)


func reset_network() -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


var _back_frame := -1


func _notification(what: int) -> void:
	# one Android back press arrives twice in the same frame (window + tree); act once
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and Engine.get_process_frames() != _back_frame:
		_back_frame = Engine.get_process_frames()
		back()


func _show(what, props: Dictionary, dir: int) -> void:
	if what is String:
		what = load(what)
	var node: Node = what.instantiate() if what is PackedScene else what.new()
	for k in props:
		node.set(k, props[k])
	var old := current
	current = node
	current_entry = [what, props]
	if old:
		old.name = "Leaving"  # free up /root/Screen: LAN RPCs need the same path on every phone
		old.process_mode = Node.PROCESS_MODE_DISABLED
		var out := create_tween()
		out.tween_property(old, "modulate:a", 0.0, 0.15)
		out.tween_callback(old.queue_free)
	node.name = "Screen"
	get_tree().root.add_child(node)
	if node is CanvasItem:
		node.position.x = get_viewport().get_visible_rect().size.x * 0.3 * dir
		node.modulate.a = 0.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "position:x", 0.0, 0.28)
		tw.tween_property(node, "modulate:a", 1.0, 0.2)


# --- widgets ------------------------------------------------------------------

func box(color: Color, lip := 12, radius := 40) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_width_bottom = lip
	s.border_color = color.darkened(0.3)
	s.set_content_margin_all(24)
	s.content_margin_bottom = 24 + lip
	s.shadow_color = Color(INK, 0.18)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 6)
	return s


## Chunky colored button: thick bottom lip, pushed-in look while pressed.
func paint(b: Button, color: Color) -> void:
	b.add_theme_stylebox_override("normal", box(color))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.08)))
	var pressed := box(color.darkened(0.05), 4)
	pressed.content_margin_top += 8
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", box(LOCKED))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := ink_on(color)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, fc)
	b.add_theme_color_override("font_shadow_color", _shadow_on(color))


## Text color that reads on `bg`: brown on light colors (cream, yellow), white on the rest.
func ink_on(bg: Color) -> Color:
	return INK if bg.get_luminance() > 0.7 else Color.WHITE


## Soft drop shadow under white text on a colored surface; none under brown text.
func _shadow_on(bg: Color) -> Color:
	return Color(0, 0, 0, 0) if ink_on(bg) == INK else Color(bg.darkened(0.45), 0.6)


## Label colored to read on a `bg` surface it sits on.
func label_on(bg: Color, text: String, font_size := 52, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := label(text, font_size, ink_on(bg), align)
	l.add_theme_color_override("font_shadow_color", _shadow_on(bg))
	return l


func button(text: String, color := ACCENT, min_size := Vector2(720, 150), font_size := 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	paint(b, color)
	bouncy(b)
	return b


## Big menu tile: icon on the left, title + subtitle on the right.
func tile(color: Color, icon_node: Control, title: String, subtitle := "", min_size := Vector2(900, 220), title_size := 64) -> Button:
	var b := button("", color, min_size)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 36
	row.offset_right = -36
	row.offset_bottom = -12
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_node)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(label_on(color, title, title_size, HORIZONTAL_ALIGNMENT_LEFT))
	if subtitle != "":
		var sub := label_on(color, subtitle, maxi(int(title_size * 0.55), 30), HORIZONTAL_ALIGNMENT_LEFT)
		sub.modulate.a = 0.9
		col.add_child(sub)
	row.add_child(col)
	b.add_child(row)
	return b


## Square game card: big icon on top, title under it (Home grid).
func card_tile(color: Color, icon_node: Control, title: String, min_size := Vector2(470, 400), title_size := 56) -> Button:
	var b := button("", color, min_size)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -12
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon_node)
	var l := label_on(color, title, title_size)
	l.add_theme_constant_override("line_spacing", -12)
	col.add_child(l)
	b.add_child(col)
	return b


## Round cream button with a brown icon (back, sound).
func icon_button(kind: String, size := 120) -> Button:
	var b := button("", CREAM, Vector2(size, size))
	for s in ["normal", "hover", "pressed", "disabled"]:
		(b.get_theme_stylebox(s) as StyleBoxFlat).set_corner_radius_all(size / 2)
	var i := icon(kind, INK, int(size * 0.8))
	i.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	i.offset_bottom = -10
	b.add_child(i)
	return b


func label(text: String, font_size := 52, color := INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func icon(kind: String, color := Color.WHITE, size := 120, count := 1) -> Control:
	var i := Icon.new()
	i.kind = kind
	i.color = color
	i.count = count
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


## Squish on press, spring back on release.
func bouncy(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size / 2)
	if c is BaseButton:
		c.pressed.connect(Sfx.play.bind("tap"))
		c.button_down.connect(func(): _scale(c, 0.92))
		c.button_up.connect(func(): _scale(c, 1.0))


func _scale(c: Control, s: float) -> void:
	c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(c, "scale", Vector2(s, s), 0.15)


## Staggered pop-in for a screen's widgets.
func pop_in(nodes: Array) -> void:
	for i in nodes.size():
		var n: CanvasItem = nodes[i]
		n.modulate.a = 0.0
		var tw := n.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.08 + i * 0.07)
		tw.tween_property(n, "modulate:a", 1.0, 0.2)


## Endless gentle pulse (e.g. the PLAY button). Returns the tween so it can be killed.
func pulse(c: Control) -> Tween:
	var tw := c.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2(1.06, 1.06), 0.5)
	tw.tween_property(c, "scale", Vector2.ONE, 0.5)
	return tw


## Board frame from the reference: soft orange glow, orange rim with a darker lip, cream inside
## `inset` pixels in.
func draw_frame(ci: CanvasItem, r: Rect2, inset := 18.0, radius := 44) -> void:
	for k in 3:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(ACCENT, 0.12)
		glow.set_corner_radius_all(radius + 30 - k * 10)
		glow.anti_aliasing = true
		ci.draw_style_box(glow, r.grow(30 - k * 10))
	var rim := box(ACCENT, 10, radius)
	rim.anti_aliasing = true
	ci.draw_style_box(rim, r)
	var inner := StyleBoxFlat.new()
	inner.bg_color = CREAM
	inner.set_corner_radius_all(maxi(radius - int(inset), 8))
	inner.anti_aliasing = true
	ci.draw_style_box(inner, r.grow(-inset))


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 52
	for type in ["Label", "Button"]:
		t.set_constant("shadow_offset_x", type, 0)
		t.set_constant("shadow_offset_y", type, 4)
	t.set_color("font_color", "Label", INK)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_color("font_shadow_color", "Button", Color(0, 0, 0, 0.18))
	t.set_color("font_disabled_color", "Button", Color(INK, 0.5))
	t.set_stylebox("normal", "Button", box(ACCENT))
	t.set_stylebox("hover", "Button", box(ACCENT.lightened(0.08)))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.05), 4))
	t.set_stylebox("disabled", "Button", box(LOCKED))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var field := box(CREAM, 8, 36)
	field.border_color = Color("e0c9a3")
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(COLORS[3], 0.3))
	return t
