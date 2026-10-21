## The local player's hand: cards fanned along a gentle arc, overlapping more as it grows,
## sorted by color then number (wilds at the right end). Tap a card to emit picked(id).
extends Node2D

signal picked(id: int)

const Card = preload("res://games/cards/card.gd")
const Rules = preload("res://games/cards/cards_rules.gd")
const WIDTH := 720.0  # spread of card centers at most
const STEP := 120.0  # gap between card centers in a small hand

var cards := {}  # id -> Card
var order := []  # ids, left to right
var enabled := true  # taps reach picked()


## Shows exactly these cards. New ones fly in from `from` (global; INF = appear in place),
## turning face up on the way.
func set_cards(ids: Array, from := Vector2.INF) -> void:
	for id in cards.keys():
		if not id in ids:
			cards[id].queue_free()
			cards.erase(id)
	for id in ids:
		if not cards.has(id):
			var card := Card.new()
			card.id = id
			add_child(card)
			cards[id] = card
			if from != Vector2.INF:
				card.position = to_local(from)
				card.scale = Vector2(0.9, 0.9)
				card.flip.call_deferred(0.3)
			else:
				card.face_up = true
	order = ids.duplicate()
	order.sort_custom(func(a, b): return _rank(a) < _rank(b))
	_layout()


static func _rank(id: int) -> int:
	var c := Rules.color_of(id)
	return ((4 if c == -1 else c) * 16 + Rules.kind_of(id)) * 200 + id


## Hands over a card (to fly it to the pile); it is no longer part of the hand.
func take(id: int) -> Node2D:
	var card: Node2D = cards.get(id)
	if card:
		cards.erase(id)
		order.erase(id)
		_layout()
	return card


## Lifts the cards in `ids`, dims the rest; `active` false = all plain (not your turn).
func mark(ids: Array, active: bool) -> void:
	for id in cards:
		cards[id].lifted = active and id in ids
		cards[id].playable = not active or id in ids


func slot(i: int, n: int) -> Transform2D:
	var step := STEP if n < 2 else minf(STEP, WIDTH / (n - 1))
	var x := (i - (n - 1) / 2.0) * step
	var t := x / 600.0
	return Transform2D(t * 0.35, Vector2(x, t * t * 90.0))


func _layout() -> void:
	var n := order.size()
	for i in n:
		var card: Node2D = cards[order[i]]
		var to := slot(i, n)
		card.z_index = i
		var tw := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", to.origin, 0.3)
		tw.tween_property(card, "rotation", to.get_rotation(), 0.3)
		tw.tween_property(card, "scale", Vector2.ONE, 0.3)


func _unhandled_input(e: InputEvent) -> void:
	if not enabled or not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var at := get_global_mouse_position()
	for i in range(order.size() - 1, -1, -1):  # topmost first
		if cards[order[i]].contains(at):
			get_viewport().set_input_as_handled()
			picked.emit(order[i])
			return
