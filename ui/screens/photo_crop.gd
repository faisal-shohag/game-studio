## Frame a picked photo for the avatar: drag to move, pinch (or the slider, or the mouse wheel) to
## zoom. The photo always covers the square. SAVE hands the square back to the profile screen.
extends "res://ui/screen.gd"

const Avatar = preload("res://core/avatar.gd")
const VIEW := 860.0  # side of the square frame
const MAX_ZOOM := 4.0

var image: Image  # set by the profile screen
var view := Control.new()
var slider := HSlider.new()
var _tex: Texture2D
var _cover := 1.0  # scale at which the photo just covers the frame
var _zoom := 1.0  # 1 .. MAX_ZOOM on top of _cover
var _offset := Vector2.ZERO  # photo's top-left corner inside the frame
var _touches := {}  # finger index -> position
var _pinch := 0.0  # finger distance last frame, 0 = not pinching


func _init() -> void:
	title = "MOVE & ZOOM"


func build() -> void:
	_tex = ImageTexture.create_from_image(image)
	_cover = VIEW / minf(image.get_width(), image.get_height())
	_offset = (Vector2(VIEW, VIEW) - Vector2(image.get_size()) * _cover) / 2
	content.add_child(UI.label("Drag to move, pinch to zoom", 44, Color(1, 1, 1, 0.8)))
	view.custom_minimum_size = Vector2(VIEW, VIEW)
	view.clip_contents = true
	view.mouse_filter = MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_view)
	content.add_child(view)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var minus := UI.button("-", UI.INK.lightened(0.3), Vector2(110, 110), 70)
	minus.pressed.connect(func(): slider.value -= 0.4)
	row.add_child(minus)
	slider.min_value = 1.0
	slider.max_value = MAX_ZOOM
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(560, 110)
	slider.add_theme_icon_override("grabber", _dot(56, Color.WHITE))
	slider.add_theme_icon_override("grabber_highlight", _dot(56, UI.COLORS[2]))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.25)
	track.set_corner_radius_all(10)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate()
	fill.bg_color = UI.COLORS[2]
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.value_changed.connect(func(v: float): _set_zoom(v))
	row.add_child(slider)
	var plus := UI.button("+", UI.INK.lightened(0.3), Vector2(110, 110), 70)
	plus.pressed.connect(func(): slider.value += 0.4)
	row.add_child(plus)
	content.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 30)
	var cancel := UI.button("CANCEL", UI.COLORS[0], Vector2(380, 150), 56)
	cancel.pressed.connect(UI.back)
	buttons.add_child(cancel)
	var save := UI.button("SAVE", UI.COLORS[1], Vector2(380, 150), 56)
	save.pressed.connect(_save)
	buttons.add_child(save)
	content.add_child(buttons)


func _draw_view() -> void:
	var s := _cover * _zoom
	view.draw_texture_rect(_tex, Rect2(_offset, Vector2(image.get_size()) * s), false)
	# frame: white border with the avatar's rounded corners hinted inside
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(10)
	frame.border_color = Color.WHITE
	view.draw_style_box(frame, Rect2(Vector2.ZERO, view.size))
	var round := StyleBoxFlat.new()
	round.draw_center = false
	round.set_border_width_all(4)
	round.border_color = Color(1, 1, 1, 0.6)
	round.set_corner_radius_all(int(VIEW * 0.2))
	round.anti_aliasing = true
	view.draw_style_box(round, Rect2(Vector2.ZERO, view.size).grow(-10))


func _input(e: InputEvent) -> void:
	var area := view.get_global_rect()
	if e is InputEventScreenTouch:
		if e.pressed and area.has_point(e.position):
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_pinch = 0.0
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var pts := _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch > 0.0:
				slider.value = _zoom * d / _pinch  # moves the zoom through _set_zoom
			_pinch = d
		else:
			_pan(e.relative)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT and _touches.is_empty() and area.has_point(e.position):
		_pan(e.relative)  # desktop
	elif e is InputEventMouseButton and e.pressed and area.has_point(e.position):
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			slider.value += 0.15
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			slider.value -= 0.15


func _pan(by: Vector2) -> void:
	_offset += by
	_clamp()


## Zooms around the frame's center, keeping the photo under it in place.
func _set_zoom(z: float) -> void:
	z = clampf(z, 1.0, MAX_ZOOM)
	var center := Vector2(VIEW, VIEW) / 2
	var on_photo := (center - _offset) / (_cover * _zoom)
	_zoom = z
	_offset = center - on_photo * _cover * _zoom
	_clamp()


## The photo must cover the whole frame.
func _clamp() -> void:
	var shown := Vector2(image.get_size()) * _cover * _zoom
	_offset = _offset.clamp(Vector2(VIEW, VIEW) - shown, Vector2.ZERO)
	view.queue_redraw()


## The frame in source pixels.
func crop_rect() -> Rect2:
	var s := _cover * _zoom
	return Rect2(-_offset / s, Vector2(VIEW, VIEW) / s)


func _save() -> void:
	UI.back_with({"draft_avatar": {"photo": Avatar.photo_from(image, crop_rect())}})


static func _dot(d: int, color: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(r, r))
			if dist <= r:
				img.set_pixel(x, y, UI.INK if dist > r - 5 else color)
	return ImageTexture.create_from_image(img)
