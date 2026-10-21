## One card on the table: face or back, flips, flies, lifts when playable, dims when not.
extends Node2D

const CardArt = preload("res://games/cards/card_art.gd")

var id := -1:
	set(v):
		id = v
		queue_redraw()
var face_up := false:
	set(v):
		face_up = v
		queue_redraw()
var playable := true:  # false = dimmed
	set(v):
		playable = v
		modulate = Color.WHITE if v else Color(0.55, 0.55, 0.65)
var lifted := false:  # raised out of the hand
	set(v):
		if v != lifted:
			lifted = v
			create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(self, "lift", 40.0 if v else 0.0, 0.2)
var lift := 0.0:
	set(v):
		lift = v
		queue_redraw()
var turn := 1.0:  # horizontal squash while flipping
	set(v):
		turn = v
		queue_redraw()


func _draw() -> void:
	CardArt.draw(self, id, face_up, Transform2D.IDENTITY.scaled(Vector2(maxf(turn, 0.01), 1.0)), lift)


## Turns over in place (squash to an edge, swap, open up).
func flip(dur := 0.25) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "turn", 0.0, dur / 2)
	tw.tween_callback(func(): face_up = not face_up)
	tw.tween_property(self, "turn", 1.0, dur / 2)
	await tw.finished


## Glides to a spot (parent coords) and angle.
func fly_to(pos: Vector2, rot := 0.0, dur := 0.35, s := scale.y) -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", pos, dur)
	tw.tween_property(self, "rotation", rot, dur)
	tw.tween_property(self, "scale", Vector2(s, s), dur)
	await tw.finished


func contains(global_point: Vector2) -> bool:
	var p := to_local(global_point) + Vector2(0, lift)
	return Rect2(-CardArt.SIZE / 2, CardArt.SIZE).has_point(p)
