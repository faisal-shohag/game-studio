## Games with rule sets (Carrom, Pen Fight): pick one before the player count (or, with friends,
## before creating a room: a room keeps the rules it was made with). Games with match lengths also
## get a ROUNDS toggle here; the choice is remembered.
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
## variant -> [color, title, one-line rules]
const INFO := {
	"classic": [3, "CLASSIC", "White vs black. Cover the queen!"],
	"freestyle": [0, "FREESTYLE", "Every coin scores. Queen 50!"],
	"turns": [3, "TURNS", "Take turns. Knock them off!"],
	"realtime": [0, "REAL-TIME", "No turns. Flick any time!"],
}
const SOON := ["realtime"]  # shown locked for now

var game := "carrom"
var mode := "bots"  # bots | local | lan
var rounds := 0  # chosen match length, for games that have them
var _seg := []  # [rounds, button]


func _init() -> void:
	title = "RULES"


func build() -> void:
	content.add_child(UI.label("Which game?", 52))
	var options: Array = Games.LIST[game].get("rounds", [])
	if not options.is_empty():
		rounds = UI.settings.get_value(game, "rounds", options[-1])
		if not rounds in options:
			rounds = options[-1]
	for v in Games.LIST[game].variants:
		var info: Array = INFO[v]
		var soon: bool = v in SOON
		var t := UI.tile(UI.COLORS[info[0]], UI.icon(game, Color.WHITE, 200), info[1], "Coming soon" if soon else info[2], Vector2(940, 300), 80)
		t.disabled = soon
		t.pressed.connect(_pick.bind(v))
		content.add_child(t)
	if not options.is_empty():
		content.add_child(_rounds_toggle(options))


func _pick(v: String) -> void:
	var props := {"game": game, "variant": v}
	if rounds > 0:
		props.rounds = rounds
	if mode == "lan":
		UI.go("res://ui/screens/lan_menu.gd", props)
	else:
		props.mode = mode
		UI.go("res://ui/screens/game_players.gd", props)


## ROUNDS  [1 ROUND | BEST OF 3]
func _rounds_toggle(options: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.add_child(UI.label("ROUNDS", 44, Color(1, 1, 1, 0.85)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	for n in options:
		var b := UI.button("1 ROUND" if n == 1 else "BEST OF %d" % n, UI.INK.lightened(0.3), Vector2(420, 130), 52)
		b.pressed.connect(_set_rounds.bind(n))
		row.add_child(b)
		_seg.append([n, b])
	col.add_child(row)
	_set_rounds(rounds, false)
	return col


func _set_rounds(n: int, save := true) -> void:
	rounds = n
	for s in _seg:
		UI.paint(s[1], UI.ACCENT if s[0] == n else UI.INK.lightened(0.3))
	if save:
		UI.settings.set_value(game, "rounds", n)
		UI.settings.save(UI.SETTINGS_PATH)
