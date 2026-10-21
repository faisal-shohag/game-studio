## Middle of the table: draw pile (tap to draw) and a loose discard pile glowing in the color to
## match, with two big curved arrows sweeping round them the way play goes. Shows a "+N" badge
## while a stack waits.
extends Node2D

const Card = preload("res://games/cards/card.gd")
const CardArt = preload("res://games/cards/card_art.gd")
const RADIUS := 270.0  # direction arrows
const ARC := 2.2  # radians each arrow sweeps
const PILE_AT := Vector2(-140, 0)
const DISCARD_AT := Vector2(110, 0)
const SHOWN := 5  # discards kept as nodes

var top_color := Color.WHITE:
	set(v):
		top_color = v
		queue_redraw()
var dir := 1:
	set(v):
		dir = v
		queue_redraw()
var pile_count := 0:
	set(v):
		pile_count = v
		queue_redraw()
var pending := 0:
	set(v):
		pending = v
		queue_redraw()
var discards := []  # Card nodes, top last
var _spin := 0.0
var _boost := 0.0  # extra arrow speed after a Reverse, dying away


func _process(delta: float) -> void:
	_spin += delta * (0.25 + _boost) * dir
	_boost = move_toward(_boost, 0.0, delta * 5.0)
	queue_redraw()


## The arrows whirl round the new way.
func spin_burst() -> void:
	_boost = 9.0


## The cards underneath jostle when a new one lands.
func wobble() -> void:
	for i in discards.size() - 1:
		var d: Node2D = discards[i]
		var rest := tilt(d.id)
		var tw := d.create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(d, "rotation", rest + randf_range(-0.12, 0.12), 0.08)
		tw.tween_property(d, "rotation", rest, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Shows these discards (bottom to top) without animation.
func set_discards(ids: Array) -> void:
	for d in discards:
		d.queue_free()
	discards.clear()
	for id in ids.slice(maxi(0, ids.size() - SHOWN)):
		var card := Card.new()
		card.id = id
		card.face_up = true
		card.position = spot(id)
		card.rotation = tilt(id)
		add_child(card)
		discards.append(card)


## A card that just landed (already a child, already in place) becomes the new top.
func push(card: Node2D) -> void:
	discards.append(card)
	card.z_index = 0
	move_child(card, -1)
	while discards.size() > SHOWN:
		discards.pop_front().queue_free()


func top_id() -> int:
	return discards.back().id if not discards.is_empty() else -1


## Each discard lies a little askew and off-center, the same way every time.
func tilt(id: int) -> float:
	return ((id * 37) % 21 - 10) / 45.0


func spot(id: int) -> Vector2:
	return DISCARD_AT + Vector2((id * 53) % 29 - 14, (id * 31) % 29 - 14)


func pile_rect() -> Rect2:
	return Rect2(to_global(PILE_AT) - CardArt.SIZE / 2, CardArt.SIZE)


func _draw() -> void:
	draw_circle(DISCARD_AT, 150, Color(top_color, 0.3))
	draw_circle(DISCARD_AT, 115, Color(top_color, 0.3))
	for k in 2:
		_arrow(_spin + k * PI)
	var layers := mini(5, ceili(pile_count / 12.0))
	for k in layers:
		CardArt.draw(self, -1, false, Transform2D(0.0, PILE_AT + Vector2(0, -3 * (layers - 1 - k))))
	if pile_count == 0:
		var r := Rect2(PILE_AT - CardArt.SIZE / 2, CardArt.SIZE)
		draw_rect(r, Color(1, 1, 1, 0.25), false, 4)
	# the color to match, as a chip by the discard pile (a wild's color shows here)
	var chip := DISCARD_AT + Vector2(0, 160)
	draw_circle(chip, 30, UI.INK)
	draw_circle(chip, 25, Color.WHITE)
	draw_circle(chip, 19, top_color)
	if pending > 0:
		var at := Vector2((PILE_AT.x + DISCARD_AT.x) / 2, -150)
		draw_circle(at, 52, UI.INK)
		draw_circle(at, 45, UI.COLORS[0])
		CardArt.text(self, "+%d" % pending, at, 50)


## One thick curved arrow starting at angle a, its head the way play goes.
func _arrow(a: float) -> void:
	var col := top_color.lerp(Color.WHITE, 0.15)
	draw_arc(Vector2.ZERO, RADIUS, a, a + ARC, 40, UI.INK, 30, true)
	draw_arc(Vector2.ZERO, RADIUS, a, a + ARC, 40, col, 20, true)
	var end := a + ARC if dir == 1 else a
	var tip := Vector2.from_angle(end) * RADIUS
	var fwd := Vector2.from_angle(end + PI / 2 * dir)
	var side := fwd.orthogonal()
	var head := PackedVector2Array([tip + fwd * 44, tip + side * 34, tip - side * 34])
	var rim := PackedVector2Array([tip + fwd * 52, tip + side * 41 - fwd * 4, tip - side * 41 - fwd * 4])
	draw_colored_polygon(rim, UI.INK)
	draw_colored_polygon(head, col)
