## Middle of the table: draw pile (tap to draw) and discard pile inside a ring tinted with the
## color to match, with arrows turning the way play goes. Shows a "+N" badge while a stack waits.
extends Node2D

const Card = preload("res://games/cards/card.gd")
const CardArt = preload("res://games/cards/card_art.gd")
const RADIUS := 215.0
const PILE_AT := Vector2(-105, 0)
const DISCARD_AT := Vector2(105, 0)
const SHOWN := 5  # discards kept as nodes

var top_color := Color.WHITE:
	set(v):
		top_color = v
		queue_redraw()
var dir := 1
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


func _process(delta: float) -> void:
	_spin += delta * 0.35 * dir
	queue_redraw()


## Shows these discards (bottom to top) without animation.
func set_discards(ids: Array) -> void:
	for d in discards:
		d.queue_free()
	discards.clear()
	for id in ids.slice(maxi(0, ids.size() - SHOWN)):
		var card := Card.new()
		card.id = id
		card.face_up = true
		card.position = DISCARD_AT
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


## Each discard lies a little askew, the same way every time.
func tilt(id: int) -> float:
	return ((id * 37) % 21 - 10) / 60.0


func pile_rect() -> Rect2:
	return Rect2(to_global(PILE_AT) - CardArt.SIZE / 2, CardArt.SIZE)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 22, Color(0, 0, 0, 0.18))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 96, Color(top_color, 0.85), 16, true)
	for i in 3:  # arrows riding the ring
		var a := _spin + i * TAU / 3
		var p := Vector2.from_angle(a) * RADIUS
		var fwd := Vector2.from_angle(a + PI / 2 * dir)
		var side := fwd.orthogonal()
		var tri := PackedVector2Array([p + fwd * 26, p - fwd * 12 + side * 22, p - fwd * 12 - side * 22])
		draw_colored_polygon(tri, UI.INK)
		draw_colored_polygon(PackedVector2Array([p + fwd * 18, p - fwd * 7 + side * 15, p - fwd * 7 - side * 15]), top_color.lightened(0.3))
	draw_circle(DISCARD_AT, 120, Color(top_color, 0.35))
	var layers := mini(5, ceili(pile_count / 12.0))
	for k in layers:
		CardArt.draw(self, -1, false, Transform2D(0.0, PILE_AT + Vector2(0, -3 * (layers - 1 - k))))
	if pile_count == 0:
		var r := Rect2(PILE_AT - CardArt.SIZE / 2, CardArt.SIZE)
		draw_rect(r, Color(1, 1, 1, 0.25), false, 4)
	if pending > 0:
		var at := Vector2(0, RADIUS - 6)
		draw_circle(at, 52, UI.INK)
		draw_circle(at, 45, UI.COLORS[0])
		CardArt.text(self, "+%d" % pending, at, 50)
