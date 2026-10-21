## Pen pick before the first round: four cards with a drawn pen that bobs, its stat bars (Weight,
## Reach, Grip, Size) and a one-line tip. Tap a card to pick it. `chosen` starts out highlighted
## (your last pick).
extends Control

signal picked(type: String)

const Physics = preload("res://games/penfight/pen_physics.gd")
const Desk = preload("res://games/penfight/penfight_desk.gd")
const BLURB := {"gel": "Light and quick", "metal": "Heavy, hard to shift", "marker": "Long reach", "highlighter": "Fat and sturdy"}
## stat label -> pen field
const STATS := [["Weight", "mass"], ["Reach", "length"], ["Grip", "grip"], ["Size", "radius"]]
const CARD := Vector2(480, 590)

var title := "Pick your pen"
var color := Color.WHITE  # the picker's color: pens are drawn in it
var chosen := ""
var _cards := []


func _ready() -> void:
	size = get_viewport_rect().size
	mouse_filter = MOUSE_FILTER_STOP  # the desk underneath doesn't react
	var oy := maxf(0.0, (size.y - 1920.0) / 2)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.size = size
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	var head := UI.label(title, 80)
	head.size = Vector2(1080, 110)
	head.position = Vector2(0, oy + 320)
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(head)
	for k in Physics.TYPES.size():
		var type: String = Physics.TYPES[k]
		var card := UI.button("", UI.INK.lightened(0.25), CARD)
		card.position = Vector2(40 + (k % 2) * (CARD.x + 40), oy + 450 + (k / 2) * (CARD.y + 40))
		card.size = CARD
		if type == chosen:
			var ring := card.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			ring.set_border_width_all(8)
			ring.border_width_bottom = 14
			ring.border_color = UI.COLORS[2]
			card.add_theme_stylebox_override("normal", ring)
		var art := Control.new()
		art.size = CARD
		art.mouse_filter = MOUSE_FILTER_IGNORE
		art.draw.connect(_draw_card.bind(art, type))
		card.add_child(art)
		card.pressed.connect(func(): picked.emit(type))
		add_child(card)
		_cards.append(art)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func _process(_delta: float) -> void:
	for art in _cards:
		art.queue_redraw()


func _draw_card(art: Control, type: String) -> void:
	var p := Physics.spec(type)
	var k := Physics.TYPES.find(type)
	var bob := sin(Time.get_ticks_msec() / 260.0 + k * 1.3) * 7.0
	Desk.draw_pen(art, Vector2(CARD.x / 2, 110 + bob), -0.12, type, color, 1.0, 0.0, 1.35)
	art.draw_string_outline(UI.FONT, Vector2(0, 250), p.name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 60, 14, UI.INK)
	art.draw_string(UI.FONT, Vector2(0, 250), p.name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 60, Color.WHITE)
	art.draw_string(UI.FONT, Vector2(0, 300), BLURB[type], HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 34, Color(1, 1, 1, 0.75))
	for i in STATS.size():
		var y := 345.0 + i * 54
		art.draw_string(UI.FONT, Vector2(36, y + 12), STATS[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
		var bar := Rect2(176, y - 12, CARD.x - 176 - 36, 26)
		var fill := bar
		fill.size.x *= stat(type, STATS[i][1])
		art.draw_rect(bar, Color(0, 0, 0, 0.3))
		art.draw_rect(fill, UI.COLORS[[0, 3, 1, 2][i]])


## A pen's stat as 0.25..1 across the four pens.
static func stat(type: String, field: String) -> float:
	var lo := INF
	var hi := -INF
	for t in Physics.TYPES:
		var v: float = Physics.spec(t)[field]
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var mine: float = Physics.spec(type)[field]
	return 0.25 + 0.75 * (mine - lo) / maxf(hi - lo, 0.0001)
