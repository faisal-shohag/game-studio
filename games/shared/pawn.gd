## A Ludo pin on the table: hops square to square, bobs with an arrow when movable,
## spins back to base when captured.
extends Node2D

const PawnArt = preload("res://games/shared/pawn_art.gd")
const SIZE := 0.62  # ~60 px tall on a 66 px square
const FOOT := 20.0  # pin stands slightly below the square's center

var color := Color.WHITE
var base_scale := 1.0:  # < 1 when sharing a square
	set(v):
		base_scale = v
		queue_redraw()
var lift := 0.0:  # jump height, negative = up
	set(v):
		lift = v
		queue_redraw()
var squash := 0.0:  # 0..1 landing squish
	set(v):
		squash = v
		queue_redraw()
var spin := 0.0:
	set(v):
		spin = v
		queue_redraw()
var movable := false:
	set(v):
		movable = v
		set_process(v)
		queue_redraw()


func _ready() -> void:
	set_process(movable)


func _process(_delta: float) -> void:
	queue_redraw()


## Visual center, for tap hit-testing.
func hit_point() -> Vector2:
	return global_position + Vector2(0, -12 * base_scale)


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var foot := Vector2(0, FOOT * base_scale)
	if movable:
		var p := 0.5 + 0.5 * sin(t * 7)
		var ring := PawnArt.ellipse(foot, 30 + 5 * p, 11 + 2 * p)
		ring.append(ring[0])
		draw_polyline(ring, Color.WHITE, 5, true)
	var s := Vector2(1 + 0.3 * squash, 1 - 0.3 * squash) * base_scale
	draw_set_transform(foot + Vector2(0, lift), spin, s)
	PawnArt.draw(self, Vector2.ZERO, SIZE, color)
	draw_set_transform(Vector2.ZERO)
	if movable:  # bouncing arrow above the head
		var y := -66 * base_scale - 10 * absf(sin(t * 5))
		var arrow := PackedVector2Array([Vector2(-15, y - 22), Vector2(15, y - 22), Vector2(0, y)])
		draw_colored_polygon(arrow, Color.WHITE)
		arrow.append(arrow[0])
		draw_polyline(arrow, UI.INK, 4, true)


## One hop to `to` (table coords), with a squash on landing.
func hop_to(to: Vector2, dur := 0.16, height := 28.0) -> void:
	var tw := create_tween()
	tw.tween_method(_hop_step.bind(position, to, height), 0.0, 1.0, dur)
	await tw.finished
	squash = 1.0
	create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).tween_property(self, "squash", 0.0, 0.35)


## Captured: big spinning arc back to the base.
func fly_to(to: Vector2) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_method(_hop_step.bind(position, to, 160.0), 0.0, 1.0, 0.55)
	tw.tween_property(self, "spin", TAU * 2, 0.55).from(0.0)
	await tw.finished
	spin = 0.0


func _hop_step(k: float, from: Vector2, to: Vector2, height: float) -> void:
	position = from.lerp(to, k)
	lift = -sin(k * PI) * height
