## Carrom table: the board fills the width, opponents' portraits sit above it, your striker
## slider and portrait below. The board turns so the local player shoots from the bottom.
extends Node2D

const Rules = preload("res://games/carrom/carrom_rules.gd")
const Physics = preload("res://games/carrom/carrom_physics.gd")
const Board = preload("res://games/carrom/carrom_board.gd")
const Seat = preload("res://games/shared/seat.gd")
const Games = preload("res://core/games.gd")
const BOARD_AT := Vector2(540, 1000)
## Opponent portraits (top-left corner) by side relative to yours: right, across, left.
const SPOTS := {1: Vector2(870, 250), 2: Vector2(465, 210), 3: Vector2(60, 250)}
const MY_SPOT := Vector2(30, 1700)
const SLIDER_Y := 1625.0
const SLIDER_X := [130.0, 950.0]  # thumb travel on screen

var variant := "classic"
var seats := ["human", "off", "bot", "off"]
var names := []
var avatars := []
var me := -1

var state: Dictionary
var board := Board.new()
var hud := Control.new()
var players := {}  # seat -> Seat
var slider := Control.new()
var thumb := Control.new()
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
	state = Rules.new_state(variant, colors)
	_build(colors)
	_turn_board(me if me != -1 else colors[0])
	board.pieces = state.pieces
	board.striker = {"x": Rules.striker_at(state.turn, 500).x, "y": Rules.striker_at(state.turn, 500).y}


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)
	board.position = BOARD_AT + Vector2(0, _oy)
	add_child(board)
	hud.theme = get_tree().root.theme
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	for c in colors:
		var seat := Seat.new()
		seat.color = UI.COLORS[c]
		seat.variant = c
		seat.player_name = names[c]
		seat.avatar = avatars[c]
		seat.fan_visible = false
		var man := Rules.man_of(state, c)
		seat.coin = null if man == -1 else Board.KIND_COLORS[man]
		seat.badge = "0"
		hud.add_child(seat)
		players[c] = seat
	slider.position = Vector2(SLIDER_X[0] - 70, SLIDER_Y + _oy - 45)
	slider.size = Vector2(SLIDER_X[1] - SLIDER_X[0] + 140, 90)
	slider.draw.connect(_draw_slider)
	hud.add_child(slider)
	var back := UI.button("", UI.INK.lightened(0.3), Vector2(120, 120))
	var arrow := UI.icon("back", Color.WHITE, 100)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.offset_bottom = -10
	back.add_child(arrow)
	back.position = Vector2(30, 50)
	back.pressed.connect(func(): UI.reset_to("res://ui/screens/home.gd"))
	hud.add_child(back)


## Puts seat `base` at the bottom and the others round the table.
func _turn_board(base: int) -> void:
	board.rotation = base * PI / 2
	for c in players:
		var rel := posmod(c - base, 4)
		players[c].position = (MY_SPOT if rel == 0 else SPOTS[rel]) + Vector2(0, _oy)


func _draw_slider() -> void:
	var r := Rect2(Vector2(20, 22), Vector2(slider.size.x - 40, 46))
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0, 0, 0, 0.3)
	pill.set_corner_radius_all(23)
	pill.anti_aliasing = true
	slider.draw_style_box(pill, r)
	var x := slider.size.x / 2
	slider.draw_circle(Vector2(x, 45), 44, UI.INK)
	Board.draw_piece(slider, Vector2(x, 45), Physics.STRIKER, 0.0, 1.45)
