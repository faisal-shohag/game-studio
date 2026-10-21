## Pen Fight table: the desk fills the width, opponents' portraits sit above it, yours below with
## the hint beside it. The desk never turns: this phone's player is at the bottom and pass-and-play
## friends flick from their own sides of it.
extends Node2D

const Rules = preload("res://games/penfight/pen_rules.gd")
const Physics = preload("res://games/penfight/pen_physics.gd")
const Desk = preload("res://games/penfight/penfight_desk.gd")
const Seat = preload("res://games/shared/seat.gd")
const Games = preload("res://core/games.gd")
const DESK_AT := Vector2(540, 990)
const DESK_SCALE := 0.94
## Opponent portraits (top-left corner) by place round the desk from yours: right, across, left.
const SPOTS := {"right": Vector2(880, 110), "across": Vector2(465, 95), "left": Vector2(215, 110)}
const MY_SPOT := Vector2(30, 1700)

var variant := "turns"
var rounds := 1
## Seat type per seat: "human", "bot", "off". Set before adding to tree.
var seats := ["human", "off", "bot", "off"]
var names := []
var avatars := []
var me := -1

var view: Dictionary
var table := Node2D.new()
var desk := Desk.new()
var hud := Control.new()
var players := {}  # seat -> Seat
var hint := Label.new()
var status := Label.new()
var _oy := 0.0


func _ready() -> void:
	var colors := []
	for c in 4:
		if seats[c] != "off":
			colors.append(c)
	if me == -1:
		me = seats.find("human")
	if names.is_empty():
		for c in 4:
			names.append(UI.player_name if c == me else Games.BOT_NAMES[c] if seats[c] == "bot" else "Player %d" % (c + 1))
	if avatars.is_empty():
		avatars = [{}, {}, {}, {}]
		if me != -1:
			avatars[me] = UI.avatar
	view = Rules.new_state(variant, rounds, colors)
	for c in colors:
		Rules.pick(view, c, Physics.TYPES[c])
	_build(colors)
	_refresh()


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	add_child(table)
	desk.position = DESK_AT + Vector2(0, _oy)
	desk.scale = Vector2(DESK_SCALE, DESK_SCALE)
	for c in colors:
		desk.colors[c] = UI.COLORS[c]
	table.add_child(desk)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var n := colors.size()
	for k in n:
		var c: int = colors[k]
		var seat := Seat.new()
		seat.color = UI.COLORS[c]
		seat.variant = c
		seat.player_name = names[c]
		seat.avatar = avatars[c]
		seat.fan_visible = false
		seat.coin = UI.COLORS[c]
		var rel := posmod(k - colors.find(me if me != -1 else colors[0]), n)
		seat.position = (MY_SPOT if rel == 0 else SPOTS[_side(rel, n)]) + Vector2(0, _oy)
		hud.add_child(seat)
		players[c] = seat
	hint.position = Vector2(200, 1715 + _oy)
	hint.size = Vector2(860, 70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 46)
	hud.add_child(hint)
	status.position = Vector2(200, 1790 + _oy)
	status.size = Vector2(860, 56)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 34)
	status.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hud.add_child(status)
	var back := UI.button("", UI.INK.lightened(0.3), Vector2(120, 120))
	var arrow := UI.icon("back", Color.WHITE, 100)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.offset_bottom = -10
	back.add_child(arrow)
	back.position = Vector2(30, 50)
	back.pressed.connect(on_back)
	hud.add_child(back)


## Where a player `rel` places round the desk from you sits: 2 players face each other,
## 3 sit in a triangle, 4 in a square.
static func _side(rel: int, n: int) -> String:
	if n == 2:
		return "across"
	if n == 3:
		return ["", "right", "left"][rel]
	return ["", "right", "across", "left"][rel]


func on_back() -> void:
	UI.reset_to("res://ui/screens/home.gd")


func _refresh() -> void:
	desk.pens = view.world.pens.duplicate(true)
	for c in players:
		players[c].badge = str(view.round_wins[c])
	hint.text = "Knock the others off!"
	status.text = "Round %d" % view.round
