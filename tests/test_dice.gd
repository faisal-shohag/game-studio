## Run: godot --headless --path . --script tests/test_dice.gd
## The 3D dice must land with the rolled value's face pointing straight up, for any yaw.
extends SceneTree

const Dice = preload("res://games/shared/dice.gd")


func _init() -> void:
	var fails := 0
	for value in range(1, 7):
		for yaw in [0.0, 0.4, -0.45, 2.0]:
			var up: Vector3 = Dice.rest_rotation(value, yaw) * Dice.SIDES[value]
			if up.dot(Vector3.UP) < 0.999:
				fails += 1
				printerr("FAIL: value %d yaw %.2f -> face points %s" % [value, yaw, up])
	print("dice: ", "OK" if fails == 0 else "%d failed" % fails)
	quit(1 if fails else 0)
