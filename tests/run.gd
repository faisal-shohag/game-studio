## Runs a test script as a scene so autoloads (UI) exist, unlike `--script` mode.
## Usage: godot --headless --path . tests/run.tscn -- tests/<test>.gd [args]
extends Node


func _ready() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var test: Node = load(path if path.is_absolute_path() else "res://" + path).new()
	add_child(test)
