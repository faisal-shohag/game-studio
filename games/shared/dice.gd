## The dice beside the active player's card: a real 3D cube rendered in a small SubViewport.
## Tap to roll. roll(value) tumbles and bounces, then lands with `value` on top
## (the value comes from the host, so every phone shows the same throw result).
extends Control

signal tapped

const INK := Color("5a3420")  # UI.INK; a const so standalone tests run without the autoload
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}
## Which value sits on each side of the cube; opposite sides add up to 7.
const SIDES := {1: Vector3.BACK, 6: Vector3.FORWARD, 3: Vector3.RIGHT, 4: Vector3.LEFT, 2: Vector3.UP, 5: Vector3.DOWN}

var waiting := false:  # human must tap: pulse to invite
	set(v):
		waiting = v
		_pulse(v)
var hop := 0.0:  # bounce height in px, negative = up
	set(v):
		hop = v
		if _view:
			_view.position.y = hop
		queue_redraw()
var cube := Node3D.new()
var _view: SubViewportContainer
var _pulse_tw: Tween


## Cube rotation that puts `value` on top, turned `yaw` radians around the vertical.
static func rest_rotation(value: int, yaw := 0.0) -> Quaternion:
	return Quaternion(Vector3.UP, yaw) * _arc(SIDES[value], Vector3.UP)


## Shortest rotation from one unit vector to another (handles opposite vectors).
static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) < -0.999:
		var perp := Vector3.RIGHT if absf(from.x) < 0.9 else Vector3.UP
		return Quaternion(from.cross(perp).normalized(), PI)
	return Quaternion(from, to)


func _ready() -> void:
	pivot_offset = size / 2
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.size = size
	_view.mouse_filter = MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	_view.add_child(vp)
	add_child(_view)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.transform = Transform3D(Basis(), Vector3(0, 2.6, 2.2)).looking_at(Vector3.ZERO)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.0
	vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	for value in SIDES:
		var n: Vector3 = SIDES[value]
		var quad := QuadMesh.new()  # faces +Z
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _face_texture(value)
		mat.roughness = 0.35
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		quad.material = mat
		var face := MeshInstance3D.new()
		face.mesh = quad
		face.transform = Transform3D(Basis(_arc(Vector3.BACK, n)), n * 0.5)
		cube.add_child(face)
	cube.quaternion = rest_rotation(1, 0.4)
	vp.add_child(cube)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()


func roll(value: int) -> void:
	waiting = false
	var target := rest_rotation(value, randi_range(0, 3) * PI / 2 + randf_range(-0.45, 0.45))
	var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var tw := create_tween().set_parallel()
	# spin fast, slow down, settle exactly on target (2.6 turns so the start doesn't already show it)
	tw.tween_method(func(k: float): cube.quaternion = Quaternion(axis, (1.0 - k) * (1.0 - k) * TAU * 2.6) * target, 0.0, 1.0, 0.9)
	tw.tween_method(func(k: float): hop = -absf(sin(k * TAU)) * 70.0 * (1.0 - k), 0.0, 1.0, 0.9)
	await tw.finished
	hop = 0.0


func _pulse(on: bool) -> void:
	if _pulse_tw:
		_pulse_tw.kill()
		_pulse_tw = null
		scale = Vector2.ONE
	if on:
		_pulse_tw = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse_tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.4)
		_pulse_tw.tween_property(self, "scale", Vector2.ONE, 0.4)


func _draw() -> void:  # soft shadow that shrinks while the dice is in the air
	var k := 1.0 + hop / 140.0
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24
		pts.append(Vector2(size.x / 2, size.y * 0.86) + Vector2(cos(a) * size.x * 0.36, sin(a) * size.y * 0.09) * k)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.3 * k))


## One face: white rounded square on a grey rim (reads as a bevel), dark pips, big red 1.
static func _face_texture(value: int) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color("e8d5b5"))
	var inset := 5.0
	var radius := 24.0
	for y in n:
		for x in n:
			var q := Vector2(clampf(x + 0.5, inset + radius, n - inset - radius), clampf(y + 0.5, inset + radius, n - inset - radius))
			if Vector2(x + 0.5, y + 0.5).distance_to(q) <= radius:
				img.set_pixel(x, y, Color.WHITE)
	var pip_r := 17.0 if value == 1 else 11.0
	var pip_color := Color("f25c54") if value == 1 else INK
	for p in PIPS[value]:
		var c: Vector2 = Vector2(n, n) / 2 + p * 32.0
		for y in range(int(c.y - pip_r) - 1, int(c.y + pip_r) + 2):
			for x in range(int(c.x - pip_r) - 1, int(c.x + pip_r) + 2):
				if Vector2(x + 0.5, y + 0.5).distance_to(c) <= pip_r:
					img.set_pixel(x, y, pip_color)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
