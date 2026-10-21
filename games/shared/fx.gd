## Table-game juice shared by every game: popup words, table shake, confetti burst and rain.


## Big bouncy word centered at height `y` ("Captured!", "Bonus roll!"), then floats up and fades.
static func popup(hud: Control, text: String, color: Color, y: float, big := false) -> void:
	var l := UI.label(text, 100 if big else 84)
	l.add_theme_color_override("font_outline_color", color.darkened(0.45))
	l.add_theme_constant_override("outline_size", 26)
	l.size = Vector2(1080, 150)
	l.position = Vector2(0, y - 75)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.3, 0.3)
	hud.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1 if big else 0.45)
	tw.tween_property(l, "position:y", l.position.y - 90, 0.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


static func shake(node: Node2D, strength := 12.0) -> void:
	var tw := node.create_tween()
	for k in 6:
		var s := strength * (1.0 - k / 8.0)  # dies down
		tw.tween_property(node, "position", Vector2(randf_range(-s, s), randf_range(-s, s)), 0.04)
	tw.tween_property(node, "position", Vector2.ZERO, 0.04)


## Confetti pop (pawn reached home, ladder climbed).
static func burst(parent: Node, at: Vector2, color: Color) -> void:
	var fx := CPUParticles2D.new()
	fx.position = at
	fx.z_index = 10
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 32
	fx.lifetime = 0.9
	fx.direction = Vector2.UP
	fx.spread = 180.0
	fx.initial_velocity_min = 250.0
	fx.initial_velocity_max = 480.0
	fx.gravity = Vector2(0, 700)
	fx.scale_amount_min = 6.0
	fx.scale_amount_max = 12.0
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.3))
	ramp.set_color(1, Color(UI.COLORS[2], 0.0))
	fx.color_ramp = ramp
	parent.add_child(fx)
	fx.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(fx.queue_free)


## Results-screen confetti: two corner bursts plus a light rain that keeps falling.
static func confetti(parent: Node, oy: float) -> void:
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	colors.colors = PackedColorArray(UI.COLORS)
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	for side in [0.0, 1080.0]:  # two corner bursts
		var burst := _particles(parent, colors)
		burst.position = Vector2(side, oy + 200)
		burst.one_shot = true
		burst.explosiveness = 0.9
		burst.amount = 70
		burst.direction = Vector2(1 if side == 0.0 else -1, -1.2)
		burst.spread = 35.0
		burst.initial_velocity_min = 700.0
		burst.initial_velocity_max = 1200.0
		burst.gravity = Vector2(0, 900)
	var rain := _particles(parent, colors)
	rain.position = Vector2(540, -30)
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(560, 10)
	rain.amount = 50
	rain.lifetime = 5.0
	rain.direction = Vector2.DOWN
	rain.spread = 15.0
	rain.initial_velocity_min = 150.0
	rain.initial_velocity_max = 260.0
	rain.gravity = Vector2(0, 60)


static func _particles(parent: Node, colors: Gradient) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.lifetime = 2.5
	p.color_initial_ramp = colors
	p.scale_amount_min = 10.0
	p.scale_amount_max = 18.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	parent.add_child(p)
	p.emitting = true
	return p
