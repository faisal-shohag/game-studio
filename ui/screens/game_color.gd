## Any board game: pick colors by tapping pawns. vs Computer: tap yours, bots fill in.
## Pass & Play: tap in order for P1, P2, ... (tap again to undo).
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
const CORNERS := [0, 1, 3, 2]  # grid order matches board corners: red TL, green TR, blue BL, yellow BR

var game := "ludo"
var mode := "bots"
var count := 4
var picks := []
var cards := {}  # color -> {button, pawn, badge}
var play: Button
var play_pulse: Tween


func _init() -> void:
	title = "PICK COLOR"


func build() -> void:
	var hint := "Tap your color" if mode == "bots" else "Tap a color for each player"
	content.add_child(UI.label(hint, 52))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 36)
	for c in CORNERS:
		var b := UI.button("", UI.COLORS[c], Vector2(430, 430))
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		col.offset_bottom = -14
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = MOUSE_FILTER_IGNORE
		var pawn := UI.icon("pawn", UI.COLORS[c], 260)
		pawn.disc = Color(1, 1, 1, 0.35)
		col.add_child(pawn)
		var badge := UI.label_on(UI.COLORS[c], "", 56)
		col.add_child(badge)
		b.add_child(col)
		b.pressed.connect(_tap.bind(c))
		grid.add_child(b)
		cards[c] = {"button": b, "pawn": pawn, "badge": badge}
	content.add_child(grid)
	play = UI.button("PLAY", UI.ACCENT, Vector2(800, 180), 84)
	play.pressed.connect(_play)
	content.add_child(play)
	_refresh()


## Start the game. Pass & Play: P1 uses the saved name, others "Player N".
func _play() -> void:
	var props := {"seats": _seats(), "me": picks[0]}
	if mode == "local":
		var names := ["", "", "", ""]
		for k in picks.size():
			names[picks[k]] = UI.player_name if k == 0 else "Player %d" % (k + 1)
		props["names"] = names
	UI.go(Games.LIST[game].scene, props)


func _tap(c: int) -> void:
	if mode == "bots":
		picks = [c]
	elif c in picks:
		picks.erase(c)
	elif picks.size() < count:
		picks.append(c)
	_refresh()


## vs Computer seats: you at `you`, bots filling the opposite corner first, like real Ludo.
static func bot_seats(you: int, count: int) -> Array:
	var seats := ["off", "off", "off", "off"]
	seats[you] = "human"
	for k in [2, 1, 3].slice(0, count - 1):
		seats[(you + k) % 4] = "bot"
	return seats


func _seats() -> Array:
	var seats := ["off", "off", "off", "off"]
	if mode == "bots":
		if not picks.is_empty():
			seats = bot_seats(picks[0], count)
	else:
		for c in picks:
			seats[c] = "human"
	return seats


func _refresh() -> void:
	var seats := _seats()
	var any := seats.count("off") < 4
	for c in cards:
		var card: Dictionary = cards[c]
		var badge := ""
		if seats[c] == "human":
			badge = "YOU" if mode == "bots" else "P%d" % (picks.find(c) + 1)
		elif seats[c] == "bot":
			badge = "BOT"
		card.badge.text = badge
		card.pawn.bob = seats[c] == "human"
		var style := UI.box(UI.COLORS[c])
		if seats[c] == "human":  # thick brown frame on picked colors
			style.set_border_width_all(12)
			style.border_width_bottom = 20
			style.border_color = UI.INK
		card.button.add_theme_stylebox_override("normal", style)
		card.button.add_theme_stylebox_override("hover", style)
		card.button.modulate.a = 0.5 if any and seats[c] == "off" else 1.0
	var ready := picks.size() == (1 if mode == "bots" else count)
	play.disabled = not ready
	if ready and play_pulse == null:
		play_pulse = UI.pulse(play)
	elif not ready and play_pulse:
		play_pulse.kill()
		play_pulse = null
		play.scale = Vector2.ONE
