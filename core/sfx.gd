## Sound effects (autoload "Sfx"): Sfx.play("hop"). A name with several files plays a random one.
## Sounds are Kenney CC0 (see assets/sfx/LICENSE.txt).
extends Node

const SOUNDS := {
	"dice": ["dice_1", "dice_2", "dice_3"],
	"hop": ["hop_1", "hop_2", "hop_3"],
	"capture": ["capture"],
	"home": ["home"],
	"tap": ["tap"],
	"no_move": ["no_move"],
	"your_turn": ["your_turn"],
	"win": ["win"],
	"lose": ["lose"],
}
const POOL := 8  # overlapping sounds (hops + dice + taps)

var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	muted = UI.settings.get_value("audio", "muted", false)
	for key in SOUNDS:
		_streams[key] = SOUNDS[key].map(func(f): return load("res://assets/sfx/%s.ogg" % f))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(key: String, pitch_jitter := 0.06) -> void:
	if muted:
		return
	var p: AudioStreamPlayer = _players[0]
	for candidate in _players:
		if not candidate.playing:
			p = candidate
			break
	p.stream = _streams[key].pick_random()
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()


func set_muted(v: bool) -> void:
	muted = v
	UI.settings.set_value("audio", "muted", v)
	UI.settings.save(UI.SETTINGS_PATH)
