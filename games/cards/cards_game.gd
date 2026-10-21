## Color Cards table: opponents around the edge, draw and discard piles in the middle, your hand
## at the bottom. Same turn loop as snakes_game.gd (host decides, events animate one at a time),
## but hands are secret: the screen is drawn only from `view` (Rules.view_for), never from the
## full state, so each phone can be sent just its own view.
extends Node2D

const Rules = preload("res://games/cards/cards_rules.gd")
const Ai = preload("res://games/cards/cards_ai.gd")
const Card = preload("res://games/cards/card.gd")
const Hand = preload("res://games/cards/hand.gd")
const Table = preload("res://games/cards/cards_table.gd")
const Fan = preload("res://games/cards/card_fan.gd")
const PlayerPanel = preload("res://games/shared/player_panel.gd")
const WinOverlay = preload("res://games/shared/win_overlay.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const PLACES := ["1st place", "2nd place", "3rd place"]
const PANEL_SIZE := Vector2(400, 190)
## Opponent card spots by how many opponents there are, in play order from your left.
const SPOTS := {1: [Vector2(340, 230)], 2: [Vector2(30, 640), Vector2(650, 640)],
	3: [Vector2(30, 640), Vector2(340, 230), Vector2(650, 640)]}
const SPECTATOR_SPOT := Vector2(340, 1500)  # all-bot games: the bottom seat's card
const TABLE_Y := 1050.0
const HAND_Y := 1650.0
const ROW_Y := 1345.0  # LAST CARD / PASS / CATCH buttons

## Seat type per color: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "bot", "bot", "bot"]
## LAN only: peer id per color, 0 = bot (run by host), -1 = off. Empty = offline.
var owners := []
## Display name per color; filled in when empty.
var names := []
## Local player's color. -1 = first human seat.
var me := -1

var state: Dictionary  # the whole game; only the host (or an offline phone) has it
var view: Dictionary  # what this screen may show: public info + one hand
var busy := false
var waiting_host := false  # client sent an intent, host hasn't answered yet
var pending := []  # [event, view] pairs waiting to be animated
var table_root := Node2D.new()  # piles + hand; shaken on +2/+4 hits
var table := Table.new()
var hand := Hand.new()
var panels := {}  # color -> PlayerPanel
var fans := {}  # color -> card fan under its panel
var hint := Label.new()
var hud := Control.new()  # panels, buttons, hint, overlays
var last_btn: Button
var pass_btn: Button
var catch_btn: Button
var plus4 := [0, 0, 0, 0]  # per color, for the results screen
var _picker: Control  # wild color choice
var _results: Control
var _base := -1  # seat drawn at the bottom; the others sit around from there
var _turn_seen := -1
var _oy := 0.0


func _ready() -> void:
	if not owners.is_empty():
		var my_id := multiplayer.get_unique_id()
		me = owners.find(my_id)
		for c in 4:
			var o: int = owners[c]
			seats[c] = "off" if o == -1 else "human" if o == my_id else "bot" if o == 0 and multiplayer.is_server() else "remote"
	var colors := []
	for c in 4:
		if seats[c] != "off":
			colors.append(c)
	var order := range(108)
	order.shuffle()
	state = Rules.new_state(colors, order)
	if me == -1:
		me = seats.find("human")
	if names.is_empty():
		for c in 4:
			var bot: bool = seats[c] == "bot" or (not owners.is_empty() and owners[c] == 0)
			names.append(UI.player_name if c == me else Games.BOT_NAMES[c] if bot else "Player %d" % (c + 1))
	_base = me if me != -1 else colors[0]
	view = Rules.view_for(state, me)
	_build(colors)
	_place_panels()
	_refresh()
	_next()


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	add_child(table_root)
	table.position = Vector2(540, TABLE_Y + _oy)
	table_root.add_child(table)
	hand.position = Vector2(540, HAND_Y + _oy)
	hand.picked.connect(_on_pick)
	table_root.add_child(hand)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.z_index = 100  # above stacked and flying cards
	add_child(hud)
	for c in colors:
		var panel := PlayerPanel.new()
		panel.color = UI.COLORS[c]
		panel.player_name = names[c]
		panel.size = PANEL_SIZE
		var fan := Fan.new()
		fan.position = Vector2(PANEL_SIZE.x / 2, PANEL_SIZE.y + 30)
		panel.add_child(fan)
		hud.add_child(panel)
		panels[c] = panel
		fans[c] = fan
	hint.position = Vector2(0, TABLE_Y + Table.RADIUS + 25 + _oy)
	hint.size = Vector2(1080, 70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 44)
	hud.add_child(hint)
	last_btn = _row_button("LAST CARD!", UI.COLORS[0], 30, func(): _intent({"do": "last"}, me))
	pass_btn = _row_button("PASS", UI.ACCENT, 390, func(): _intent({"do": "pass"}, me))
	catch_btn = _row_button("CATCH!", UI.COLORS[2], 750, _on_catch)
	var back := UI.button("", UI.INK.lightened(0.3), Vector2(120, 120))
	var arrow := UI.icon("back", Color.WHITE, 100)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.offset_bottom = -10
	back.add_child(arrow)
	back.position = Vector2(30, 50)
	back.pressed.connect(on_back)
	hud.add_child(back)


func _row_button(text: String, color: Color, x: float, on_press: Callable) -> Button:
	var b := UI.button(text, color, Vector2(300, 120), 44)
	b.position = Vector2(x, ROW_Y + _oy)
	b.pressed.connect(func(): if _my_turn() or b == catch_btn: on_press.call())
	b.hide()
	hud.add_child(b)
	return b


func _to_menu() -> void:
	UI.reset_to("res://ui/screens/home.gd")


func on_back() -> void:
	if _picker:
		_close_picker()
	elif view.phase == "over":
		_to_menu()
	elif await UI.confirm("Leave game?", "Your progress will be lost." if owners.is_empty() else "You will leave the room."):
		_to_menu()


## Opponents sit around the bottom seat in play order: left, top, right.
func _place_panels() -> void:
	var colors: Array = view.colors
	var i := colors.find(_base)
	var others := []
	for k in range(1, colors.size()):
		others.append(colors[(i + k) % colors.size()])
	for k in others.size():
		panels[others[k]].position = SPOTS[others.size()][k] + Vector2(0, _oy)
		panels[others[k]].show()
	panels[_base].visible = me == -1
	panels[_base].position = SPECTATOR_SPOT + Vector2(0, _oy)


## Where color c's cards come from and go to on screen.
func _seat_pos(c: int) -> Vector2:
	if c == _base and not panels[c].visible:
		return hand.global_position
	return panels[c].position + PANEL_SIZE / 2


## Redraws everything from `view` (no animation).
func _refresh() -> void:
	table.top_color = UI.COLORS[view.top_color]
	table.dir = view.dir
	table.pile_count = view.pile_count
	table.pending = view.pending
	if table.top_id() != view.discard.back():
		table.set_discards(view.discard)
	hand.set_cards(view.hand)
	var over: bool = view.phase == "over"
	for c in panels:
		var panel: PlayerPanel = panels[c]
		var n: int = view.counts[c]
		panel.active = c == view.turn and not over
		panel.status = "1 card" if n == 1 else "%d cards" % n
		var place: int = view.winners.find(c)
		panel.note = PLACES[place] if place != -1 and place < PLACES.size() else ""
		fans[c].count = n
	_controls()


## Buttons, playable cards and the hint for whoever is looking at the phone.
func _controls() -> void:
	var mine := _my_turn()
	var acts := Rules.legal(view, view.hand) if mine else []
	var ids := acts.filter(func(a): return a.do == "play").map(func(a): return a.id)
	hand.mark(ids, mine)
	last_btn.visible = acts.any(func(a): return a.do == "last")
	pass_btn.visible = mine and view.phase == "drawn"
	catch_btn.visible = view.phase != "over" and view.catchable not in [-1, me] and me != -1
	var c: int = view.turn
	if view.phase == "over":
		hint.text = "%s wins!" % names[view.winners[0]]
	elif mine:
		if view.pending > 0:
			hint.text = "Stack it, or tap the deck for +%d" % view.pending if not ids.is_empty() else "Tap the deck to take %d" % view.pending
		elif view.phase == "drawn":
			hint.text = "Play the new card, or pass"
		else:
			hint.text = "Your turn!" if not ids.is_empty() else "No match: tap the deck"
	elif seats[c] == "human":
		hint.text = ""  # their own move is still landing
	elif seats[c] == "remote":
		hint.text = "Waiting for %s..." % names[c]
	else:
		hint.text = "%s is thinking..." % names[c]


func _my_turn() -> bool:
	return (me != -1 and view.turn == me and seats[me] == "human" and view.phase != "over"
		and not busy and not waiting_host and pending.is_empty() and _picker == null)


func _next() -> void:
	if not pending.is_empty():
		_animate.callv(pending.pop_front())
		return
	var c: int = view.turn
	var who: String = seats[c]
	if view.phase == "over":
		_refresh()
		if _results == null:
			_show_results()
		return
	_refresh()
	if who == "human" and c != _turn_seen:
		Sfx.play("your_turn", 0.0)
	_turn_seen = c
	if who == "bot":
		panels[c].note = "Thinking..."
		await _pause(0.9 if view.catchable != -1 else 0.6)  # a beat to catch a forgetful player
		if not is_inside_tree():
			return
		if state.turn == c and state.phase != "over":
			_intent(Ai.pick(Rules.view_for(state, c)), c)
		elif not pending.is_empty():
			_next()


func _pause(sec: float) -> void:
	busy = true
	await get_tree().create_timer(sec).timeout
	busy = false


## Local player or bot wants to act. Host (or offline) decides; clients ask host.
func _intent(action: Dictionary, c: int) -> void:
	if multiplayer.is_server():
		_host_do(action, c, 0)
	else:
		waiting_host = true
		_request.rpc_id(1, action)


@rpc("any_peer", "reliable")
func _request(action: Dictionary) -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		_host_do(action, owners.find(sender), sender)


## Host applies the action and shows the result. sender 0 = local; else must own seat c.
func _host_do(action: Dictionary, c: int, sender: int) -> void:
	if c == -1 or (sender != 0 and owners[c] != sender):
		return
	var ev := Rules.apply(state, c, action)
	if ev.is_empty():
		return
	if ev.do == "play" and ev.catchable:
		_bots_catch(c)
	_show(Rules.event_for(ev, me), Rules.view_for(state, me))


## One bot opponent may notice the missing call and shout CATCH after a moment.
func _bots_catch(target: int) -> void:
	var bots: Array = state.colors.filter(func(b): return b != target and seats[b] == "bot")
	if bots.is_empty() or not Ai.wants_catch():
		return
	var b: int = bots.pick_random()
	await get_tree().create_timer(randf_range(0.4, 1.3)).timeout
	if is_inside_tree() and state.catchable == target:
		_intent({"do": "catch", "target": target}, b)


func _show(ev: Dictionary, v: Dictionary) -> void:
	waiting_host = false
	pending.append([ev, v])
	if not busy:
		_next()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if table.pile_rect().has_point(get_global_mouse_position()) and _my_turn():
			get_viewport().set_input_as_handled()
			if view.phase == "play":
				_intent({"do": "draw"}, me)


func _on_pick(id: int) -> void:
	if not _my_turn():
		return
	if not Rules.can_play(view, id):
		Sfx.play("no_move", 0.0)
		var card: Node2D = hand.cards[id]
		var tw := card.create_tween()
		for k in 4:
			tw.tween_property(card, "rotation", card.rotation + (0.08 if k % 2 == 0 else -0.08), 0.05)
		tw.tween_property(card, "rotation", card.rotation, 0.05)
		return
	if Rules.color_of(id) == -1:
		_open_picker(id)
	else:
		_intent({"do": "play", "id": id, "color": Rules.color_of(id)}, me)


func _on_catch() -> void:
	if view.catchable not in [-1, me]:
		_intent({"do": "catch", "target": view.catchable}, me)


# --- animation ----------------------------------------------------------------

func _animate(ev: Dictionary, v: Dictionary) -> void:
	busy = true
	_controls()
	var c: int = ev.color
	var col: Color = UI.COLORS[c]
	panels[c].note = ""
	match ev.do:
		"play":
			await _fly_play(ev)
			Sfx.play("hop")
			var k := Rules.kind_of(ev.id)
			if k == Rules.WILD4:
				plus4[c] += 1
			table.top_color = UI.COLORS[ev.top_color]
			if ev.out:
				Fx.burst(table_root, _seat_pos(c), col)
				Sfx.play("home", 0.0)
				if v.phase != "over":
					_popup("%s: %s!" % [names[c], PLACES[v.winners.find(c)]], col, true)
			elif k == Rules.SKIP or ev.skipped != -1:
				_popup("Skip!" if k == Rules.SKIP else "Reverse!", col)
			elif k == Rules.REVERSE:
				_popup("Reverse!", col)
			elif k == Rules.DRAW2 or k == Rules.WILD4:
				_popup("+%d!" % ev.pending, col)
			elif k == Rules.WILD:
				_popup(UI.NAMES[ev.top_color] + "!", UI.COLORS[ev.top_color])
		"draw":
			Sfx.play("dice")
			if ev.reshuffled:
				_popup("Shuffle!", UI.COLORS[3])
			table.pile_count = v.pile_count
			await _fly_draw(c, ev.n, v)
			if ev.stack:
				Sfx.play("capture")
				Fx.shake(table_root)
				_popup("%s takes %d!" % [names[c], ev.n], col)
			elif not ev.can_play:
				Sfx.play("no_move", 0.0)
				if c == me:
					_popup("No match", col)
		"pass":
			panels[c].note = "Pass"
			Sfx.play("no_move", 0.0)
		"last":
			Sfx.play("home", 0.0)
			_popup("LAST CARD!", col, true)
			await get_tree().create_timer(0.6).timeout
		"catch":
			Sfx.play("capture")
			Fx.shake(table_root)
			_popup("Caught! +%d" % ev.n, UI.COLORS[ev.by])
			await _fly_draw(c, ev.n, v)
	view = v
	_refresh()
	if ev.do == "draw" and not ev.can_play and not ev.stack:
		panels[c].note = "No luck"
	busy = false
	_next()


func _fly_play(ev: Dictionary) -> void:
	var card: Node2D = hand.take(ev.id) if ev.color == me else null
	if card:
		card.lifted = false
		card.playable = true
		card.reparent(table)
	else:
		card = Card.new()
		card.id = ev.id
		table.add_child(card)
		card.global_position = _seat_pos(ev.color)
		card.scale = Vector2(0.4, 0.4)
		card.flip(0.3)
	card.z_index = 10
	await card.fly_to(Table.DISCARD_AT, table.tilt(ev.id), 0.35, 1.0)
	table.push(card)


## n cards fly from the pile: into the hand (face up) for the me, else to the player's card.
func _fly_draw(c: int, n: int, v: Dictionary) -> void:
	var from := table.to_global(Table.PILE_AT)
	if c == me:
		hand.set_cards(v.hand, from)
		await get_tree().create_timer(0.45).timeout
		return
	for k in mini(n, 6):
		var card := Card.new()
		card.z_index = 10
		table.add_child(card)
		card.position = Table.PILE_AT
		var to := table.to_local(_seat_pos(c))
		card.fly_to(to, 0.0, 0.35, 0.35)
		get_tree().create_timer(0.36).timeout.connect(card.queue_free)
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.3).timeout


func _popup(text: String, color: Color, big := false) -> void:
	Fx.popup(hud, text, color, table.position.y, big)


# --- overlays -----------------------------------------------------------------

func _open_picker(id: int) -> void:
	_picker = ColorRect.new()
	_picker.color = Color(0, 0, 0, 0.6)
	_picker.size = hud.size
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_picker())
	var title := UI.label("Pick a color", 72)
	title.size = Vector2(1080, 100)
	title.position = Vector2(0, TABLE_Y + _oy - 420)
	_picker.add_child(title)
	for k in 4:
		var b := UI.button("", UI.COLORS[k], Vector2(300, 260))
		b.position = Vector2(225 + (k % 2) * 330, TABLE_Y + _oy - 290 + (k / 2) * 290)
		b.pressed.connect(func():
			_close_picker()
			_intent({"do": "play", "id": id, "color": k}, me))
		_picker.add_child(b)
	hud.add_child(_picker)
	UI.pop_in(_picker.get_children())
	_controls()


func _close_picker() -> void:
	if _picker:
		_picker.queue_free()
		_picker = null
		_controls()


func _show_results() -> void:
	_results = WinOverlay.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():  # left during the pause
		return
	hint.hide()
	for b in [last_btn, pass_btn, catch_btn]:
		b.hide()
	_results.ranking = Rules.ranking(view)
	_results.names = names
	_results.me = me
	_results.stats = range(4).map(func(c): return "Cards left %d    +4s %d" % [view.counts.get(c, 0), plus4[c]])
	_results.can_restart = owners.is_empty() or multiplayer.is_server()
	_results.play_again.connect(_play_again)
	_results.home.connect(_to_menu)
	hud.add_child(_results)


func _play_again() -> void:
	UI.restart()
