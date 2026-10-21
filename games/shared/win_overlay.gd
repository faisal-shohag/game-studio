## End-of-game screen over the board: rotating sun rays, ribbon title, podium that rises
## 3rd -> 2nd -> 1st, crown on the winner, per-player stats, reward count-up, confetti,
## and Play Again / Home buttons.
extends Control

signal play_again
signal home

const PLACE_TEXT := ["1st", "2nd", "3rd", "4th"]
const REWARD := [100, 50, 25, 10]  # cosmetic stars for now; no currency yet
# podium slot per place: [center x, block height]
const SLOTS := [[540.0, 320.0], [275.0, 230.0], [805.0, 165.0]]

var ranking := []  # colors, winner first
var names := []
var me := -1  # local player's color, -1 = none (all bots)
var stats := []  # per color: one line of game-specific numbers ("Captures 2    Sixes 5")
var can_restart := true  # LAN clients wait for the host instead
var _ray_angle := 0.0
var _rays_at := Vector2.ZERO


func _ready() -> void:
	size = get_viewport_rect().size
	mouse_filter = MOUSE_FILTER_STOP  # board underneath no longer reacts
	var oy := maxf(0.0, (size.y - 1920.0) / 2)
	_rays_at = Vector2(540, oy + 700)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	var winner: int = ranking[0]
	var won := winner == me
	Sfx.play("win" if won or me == -1 else "lose", 0.0)

	# ribbon title drops in
	var ribbon := Panel.new()
	var style := UI.box(UI.COLORS[winner], 16, 40)
	style.border_color = UI.INK
	style.set_border_width_all(6)
	style.border_width_bottom = 18
	ribbon.add_theme_stylebox_override("panel", style)
	ribbon.size = Vector2(980, 180)
	ribbon.position = Vector2(50, -260)
	var title := UI.label("YOU WIN!" if won else "%s WINS!" % names[winner].to_upper(), 84)
	title.size = Vector2(980, 160)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ribbon.add_child(title)
	add_child(ribbon)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(ribbon, "position:y", oy + 150, 0.6)
	if me != -1 and not won:
		var sub := UI.label("You finished %s" % PLACE_TEXT[ranking.find(me)], 52, Color(1, 1, 1, 0.9))
		sub.size = Vector2(1080, 70)
		sub.position = Vector2(0, oy + 350)
		add_child(sub)

	# podium: blocks rise from the floor, pawn + name pop on top, crown on 1st
	var floor_y := oy + 1150
	var shown := mini(3, ranking.size())
	for place in range(shown - 1, -1, -1):
		var c: int = ranking[place]
		var x: float = SLOTS[place][0]
		var h: float = SLOTS[place][1]
		var delay := (shown - 1 - place) * 0.35 + 0.4
		var block := Panel.new()
		var bs := UI.box(UI.COLORS[c], 14, 24)
		bs.border_color = UI.INK
		bs.set_border_width_all(5)
		block.add_theme_stylebox_override("panel", bs)
		block.size = Vector2(240, h)
		block.position = Vector2(x - 120, floor_y - h)
		block.pivot_offset = Vector2(120, h)
		block.scale = Vector2(1, 0)
		var num := UI.label(str(place + 1), 130)
		num.size = Vector2(240, minf(h, 200))
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		block.add_child(num)
		add_child(block)
		var pawn := UI.icon("pawn", UI.COLORS[c], 200)
		pawn.position = Vector2(x - 100, floor_y - h - 196)
		var name_label := UI.label(names[c], 38)
		name_label.size = Vector2(320, 50)
		name_label.position = Vector2(x - 160, floor_y - h - 250 - (70 if place == 0 else 0))
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for n in [pawn, name_label]:
			n.modulate.a = 0.0
			add_child(n)
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(block, "scale:y", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pawn, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(name_label, "modulate:a", 1.0, 0.15)
		if place == 0:
			var crown := UI.icon("crown", Color.WHITE, 130)
			crown.position = Vector2(x - 65, floor_y - h - 300)
			crown.pivot_offset = Vector2(65, 65)
			crown.scale = Vector2.ZERO
			add_child(crown)
			tw.tween_property(crown, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): pawn.bob = true; crown.bob = true)

	# last place under the podium (4-player games)
	var y := floor_y + 30
	if ranking.size() == 4:
		var last := UI.label("4th   %s" % names[ranking[3]], 40, UI.COLORS[ranking[3]].lightened(0.35))
		last.size = Vector2(1080, 56)
		last.position = Vector2(0, y)
		add_child(last)
		y += 70
	# stats: one row per player, in finishing order
	for c in ranking:
		var row := UI.label("%s    %s" % [names[c], stats[c]], 34, UI.COLORS[c].lightened(0.35))
		row.size = Vector2(1080, 50)
		row.position = Vector2(0, y)
		add_child(row)
		y += 52

	# reward count-up for the local player
	if me != -1:
		var star := UI.icon("star", UI.COLORS[2], 90)
		star.position = Vector2(380, y + 10)
		add_child(star)
		var stars := UI.label("+0", 64, UI.COLORS[2], HORIZONTAL_ALIGNMENT_LEFT)
		stars.size = Vector2(300, 100)
		stars.position = Vector2(485, y + 6)
		add_child(stars)
		var reward: int = REWARD[ranking.find(me)]
		var tw := create_tween()
		tw.tween_interval(1.6)
		tw.tween_method(func(v: int): stars.text = "+%d" % v, 0, reward, 1.0)

	# buttons
	var by := size.y - oy - 230
	var again := UI.button("PLAY AGAIN" if can_restart else "WAITING...", UI.COLORS[1], Vector2(480, 150), 54)
	again.disabled = not can_restart
	again.position = Vector2(40, by)
	again.pressed.connect(play_again.emit)
	add_child(again)
	var leave := UI.button("HOME", UI.ACCENT, Vector2(480, 150), 54)
	leave.position = Vector2(560, by)
	leave.pressed.connect(home.emit)
	add_child(leave)

	_confetti(oy)


func _process(delta: float) -> void:
	_ray_angle += delta * 0.25
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.15, 0.85))
	for i in 12:
		var a := _ray_angle + i * TAU / 12
		draw_colored_polygon(PackedVector2Array([_rays_at, _rays_at + Vector2.from_angle(a) * 1600,
			_rays_at + Vector2.from_angle(a + TAU / 24) * 1600]), Color(1, 1, 1, 0.06))


func _confetti(oy: float) -> void:
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	colors.colors = PackedColorArray(UI.COLORS)
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	for side in [0.0, 1080.0]:  # two corner bursts
		var burst := _particles(colors)
		burst.position = Vector2(side, oy + 200)
		burst.one_shot = true
		burst.explosiveness = 0.9
		burst.amount = 70
		burst.direction = Vector2(1 if side == 0.0 else -1, -1.2)
		burst.spread = 35.0
		burst.initial_velocity_min = 700.0
		burst.initial_velocity_max = 1200.0
		burst.gravity = Vector2(0, 900)
	var rain := _particles(colors)  # light confetti that keeps falling
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


func _particles(colors: Gradient) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.lifetime = 2.5
	p.color_initial_ramp = colors
	p.scale_amount_min = 10.0
	p.scale_amount_max = 18.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	add_child(p)
	p.emitting = true
	return p
