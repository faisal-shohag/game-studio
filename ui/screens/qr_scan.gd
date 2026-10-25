## Scan a host's room QR: asks for the camera, shows a live preview in a square viewfinder and
## reads frames until a Game Studio room code shows up, then goes back to JOIN ROOM to join it.
## Frames are turned gray and thresholded on the GPU (two small SubViewports); the QR reading
## itself runs on a worker thread so the preview stays smooth.
extends "res://ui/screen.gd"

const QrScan = preload("res://core/qr_scan.gd")
const FRAME := 400  # side of the frame that gets decoded, px
const VIEW := 820.0  # on-screen viewfinder side
const EVERY := 0.3  # seconds between decode attempts

const GRAY := """
shader_type canvas_item;
uniform bool y_only = true;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = y_only ? c.r : dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g), 1.0);
}
"""
## Dark where darker than the mean of a 5x5 sample grid ~6 modules wide around it.
const THRESHOLD := """
shader_type canvas_item;
uniform float spread = 0.03;
void fragment() {
	float v = texture(TEXTURE, UV).r;
	float sum = 0.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			sum += texture(TEXTURE, UV + vec2(float(i), float(j)) * spread).r;
		}
	}
	COLOR = vec4(vec3(v < sum / 25.0 - 0.04 ? 0.0 : 1.0), 1.0);
}
"""

var status: Label
var view := TextureRect.new()
var frame := Control.new()  # corner brackets + scan line over the preview
var retry: Button
var _gray_vp := SubViewport.new()
var _bw_vp := SubViewport.new()
var _cam := TextureRect.new()
var _gray_mat := ShaderMaterial.new()
var _feed: CameraFeed
var _task := -1
var _wait := 0.0
var _found := false
var _flash := 0.0


func _init() -> void:
	title = "SCAN QR"


func build() -> void:
	status = UI.label("Starting camera...", 46)
	content.add_child(status)
	var box := Control.new()
	box.custom_minimum_size = Vector2(VIEW, VIEW)
	view.size = Vector2(VIEW, VIEW)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	box.add_child(view)
	frame.size = Vector2(VIEW, VIEW)
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	frame.draw.connect(_draw_frame)
	box.add_child(frame)
	content.add_child(box)
	content.add_child(UI.label("Point at the QR on the host's screen", 40, UI.INK_SOFT))
	retry = UI.button("TRY AGAIN", UI.COLORS[1], Vector2(500, 130), 54)
	retry.pressed.connect(_start)
	retry.hide()
	content.add_child(retry)
	var typed := UI.button("Enter IP instead", UI.CREAM, Vector2(620, 110), 40)
	typed.pressed.connect(func(): UI.back_with({"manual_ip": true}))
	content.add_child(typed)
	# offscreen: camera -> gray square (shown) -> black and white (decoded)
	for vp in [_gray_vp, _bw_vp]:
		vp.size = Vector2i(FRAME, FRAME)
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
	var gray := Shader.new()
	gray.code = GRAY
	_gray_mat.shader = gray
	_cam.material = _gray_mat
	_cam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cam.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_gray_vp.add_child(_cam)
	var bw := TextureRect.new()
	bw.texture = _gray_vp.get_texture()
	bw.size = Vector2(FRAME, FRAME)
	var bw_mat := ShaderMaterial.new()
	bw_mat.shader = Shader.new()
	bw_mat.shader.code = THRESHOLD
	bw.material = bw_mat
	_bw_vp.add_child(bw)
	view.texture = _gray_vp.get_texture()
	_start.call_deferred()


func _start() -> void:
	retry.hide()
	if OS.get_name() == "Android" and not "android.permission.CAMERA" in OS.get_granted_permissions():
		status.text = "Allow the camera to scan"
		OS.request_permission("android.permission.CAMERA")
		while true:
			var res: Array = await get_tree().on_request_permissions_result
			if res[0] == "android.permission.CAMERA":
				if not res[1]:
					_fail("Camera permission is needed")
					return
				break
	CameraServer.monitoring_feeds = true
	var t0 := Time.get_ticks_msec()
	while CameraServer.get_feed_count() == 0 and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		_fail("No camera found")
		return
	_feed = feeds[0]
	for f in feeds:
		if f.get_position() == CameraFeed.FEED_BACK:
			_feed = f
			break
	_pick_format()
	_feed.feed_is_active = true
	await _feed.frame_changed
	if not is_inside_tree():
		return
	var sep := _feed.get_datatype() == CameraFeed.FEED_YCBCR_SEP
	var tex := CameraTexture.new()
	tex.camera_feed_id = _feed.get_id()
	tex.which_feed = CameraServer.FEED_Y_IMAGE if sep else CameraServer.FEED_RGBA_IMAGE
	tex.camera_is_active = true
	_gray_mat.set_shader_parameter("y_only", _feed.get_datatype() != CameraFeed.FEED_RGB)
	_cam.texture = tex
	# fill the square, upright for a portrait phone (the sensor is landscape)
	var landscape := tex.get_width() >= tex.get_height()
	var turn := OS.get_name() == "Android" and landscape
	_cam.size = Vector2(FRAME, FRAME)
	_cam.pivot_offset = _cam.size / 2
	_cam.rotation = PI / 2 if turn else 0.0
	status.text = "Looking for a QR code..."


## Smallest offered format that is still at least 480 px tall, if the camera lists any.
func _pick_format() -> void:
	var formats := _feed.get_formats()
	var best := -1
	for i in formats.size():
		var f: Dictionary = formats[i]
		var short := mini(f.get("width", 0), f.get("height", 0))
		if short >= 480 and (best == -1 or short < mini(formats[best].get("width", 0), formats[best].get("height", 0))):
			best = i
	if best != -1:
		_feed.set_format(best, {})


func _fail(why: String) -> void:
	status.text = why
	retry.visible = why != "No camera found"
	Sfx.play("no_move", 0.0)


func _process(delta: float) -> void:
	frame.queue_redraw()
	_flash = maxf(0.0, _flash - delta)
	if _found or _feed == null or not _feed.feed_is_active or _task != -1:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = EVERY
	var img := _bw_vp.get_texture().get_image()
	_task = WorkerThreadPool.add_task(func(): _decoded.call_deferred(QrScan.decode(img, true)))


func _decoded(text: String) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _found or text == "":
		return
	var ip := QrScan.join_ip(text, Array(IP.get_local_addresses()))
	if ip == "":
		status.text = "That's not a Game Studio room"
		return
	_found = true
	_flash = 0.6
	status.text = "Joining..."
	Sfx.play("home", 0.0)
	Input.vibrate_handheld(60)
	await get_tree().create_timer(0.35).timeout
	if is_inside_tree():
		UI.back_with({"scanned": ip})


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _feed:
		_feed.feed_is_active = false
	CameraServer.monitoring_feeds = false


func _draw_frame() -> void:
	var s := VIEW
	var col := UI.COLORS[1] if _found or _flash > 0.0 else Color.WHITE
	var edge := StyleBoxFlat.new()  # rounded clip look: thick dark rim
	edge.draw_center = false
	edge.set_border_width_all(14)
	edge.border_color = UI.INK
	edge.set_corner_radius_all(48)
	edge.anti_aliasing = true
	frame.draw_style_box(edge, Rect2(Vector2(-10, -10), Vector2(s + 20, s + 20)))
	var arm := 120.0
	var inset := 40.0
	for k in 4:
		var c := Vector2(inset if k in [0, 3] else s - inset, inset if k < 2 else s - inset)
		var dx := 1.0 if k in [0, 3] else -1.0
		var dy := 1.0 if k < 2 else -1.0
		frame.draw_polyline(PackedVector2Array([c + Vector2(0, arm * dy), c, c + Vector2(arm * dx, 0)]), col, 14, true)
	if _feed and _feed.feed_is_active and not _found:
		var y := inset + (s - 2 * inset) * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 500.0))
		frame.draw_line(Vector2(inset + 20, y), Vector2(s - inset - 20, y), Color(UI.COLORS[0], 0.8), 6, true)
