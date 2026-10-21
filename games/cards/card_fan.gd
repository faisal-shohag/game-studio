## An opponent's hand: a small fan of card backs, one per card (up to MAX).
extends Node2D

const CardArt = preload("res://games/cards/card_art.gd")
const MAX := 12
const SCALE := 0.34

var count := 0:
	set(v):
		count = v
		queue_redraw()


func _draw() -> void:
	var n := mini(count, MAX)
	for i in n:
		var t := (i - (n - 1) / 2.0) / 6.0
		var xf := Transform2D(t * 0.5, Vector2(t * 120, absf(t) * 14)).scaled_local(Vector2(SCALE, SCALE))
		CardArt.draw(self, -1, false, xf)
