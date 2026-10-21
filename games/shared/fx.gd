## Table-game juice shared by every board game: popup words, table shake, confetti burst.


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


static func shake(node: Node2D) -> void:
	var tw := node.create_tween()
	for k in 6:
		tw.tween_property(node, "position", Vector2(randf_range(-12, 12), randf_range(-12, 12)), 0.04)
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
