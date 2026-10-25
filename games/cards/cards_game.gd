## Color Cards table: opponents around the edge, draw and discard piles in the middle, your hand
## at the bottom. Same turn loop as snakes_game.gd (host decides, events animate one at a time),
## but hands are secret: only the host keeps the full state. After every action it sends each
## phone its own view (Rules.view_for) and event (Rules.event_for); the screen is drawn only from
## that view, even offline. Clients never run the rules on their own.
extends Node2D

signal shown(ev: Dictionary, v: Dictionary)  # every event this phone receives (tests check secrecy)

const Rules = preload("res://games/cards/cards_rules.gd")
const Ai = preload("res://games/cards/cards_ai.gd")
const Card = preload("res://games/cards/card.gd")
const Hand = preload("res://games/cards/hand.gd")
const Table = preload("res://games/cards/cards_table.gd")
const Seat = preload("res://games/shared/seat.gd")
const Results = preload("res://games/cards/cards_results.gd")
const Fx = preload("res://games/shared/fx.gd")
const Games = preload("res://core/games.gd")
const PLACES := ["1st place", "2nd place", "3rd place"]
## Opponent portraits (top-left corner) and the way their fans point, by how many opponents
## there are, in play order from your left.
const SPOTS := {
	1: [[Vector2(465, 240), Vector2.DOWN]],
	2: [[Vector2(170, 240), Vector2.DOWN], [Vector2(760, 240), Vector2.DOWN]],
	3: [[Vector2(40, 520), Vector2.RIGHT], [Vector2(465, 140), Vector2.DOWN], [Vector2(890, 520), Vector2.LEFT]],
}
const MY_SPOT := Vector2(30, 1290)  # your portrait, bottom-left
const TABLE_Y := 1000.0
const HAND_Y := 1690.0
const HAND_SCALE := 1.1
const LAST_AT := Vector2(955, 1395)  # center of the round LAST CARD button

## Seat type per color: "human", "bot", "off", or "remote" (played on another phone).
## Set before adding to tree. For LAN games set `owners` instead.
var seats := ["human", "bot", "bot", "bot"]
## LAN only: peer id per color, 0 = bot (run by host), -1 = off. Empty = offline.
var owners := []
## Display name per color; filled in when empty.
var names := []
## Avatar per color ({} = default look); filled in when empty.
var avatars := []
## Local player's color. -1 = first human seat.
var me := -1

var state: Dictionary  # the whole game; only the host (or an offline phone) has it, else empty
var view: Dictionary  # what this screen may show: public info + one hand
var busy := false
var waiting_host := false  # client sent an intent, host hasn't answered yet
var pending := []  # [event, view] pairs waiting to be animated
var table_root := Node2D.new()  # piles + hand; shaken on +2/+4 hits
var table := Table.new()
var hand := Hand.new()
var players := {}  # color -> Seat
var hint := Label.new()
var hud := Control.new()  # seats, buttons, hint, overlays
var last_btn: Button
var pass_btn: Button
var _last_pulse: Tween
var _picker: Control  # wild color choice
var _results: Control
var _base := -1  # seat drawn at the bottom; the others sit around from there
var _turn_seen := -1
var _oy := 0.0
var _synced := []  # host: peers whose table is ready for their views


func _ready() -> void:
	if not owners.is_empty():
		var my_id := multiplayer.get_unique_id()
		me = owners.find(my_id)
		for c in 4:
			var o: int = owners[c]
			seats[c] = "off" if o == -1 else "human" if o == my_id else "bot" if o == 0 and multiplayer.is_server() else "remote"
		multiplayer.peer_disconnected.connect(_on_peer_left)
		multiplayer.server_disconnected.connect(_on_host_left)
	var colors := []
	for c in 4:
		if seats[c] != "off":
			colors.append(c)
	if me == -1:
		me = seats.find("human")
	if names.is_empty():
		for c in 4:
			var bot: bool = seats[c] == "bot" or (not owners.is_empty() and owners[c] == 0)
			names.append(UI.player_name if c == me else Games.BOT_NAMES[c] if bot else "Player %d" % (c + 1))
	if avatars.is_empty():  # offline: only you have one; bots and pass-and-play friends get the default
		avatars = [{}, {}, {}, {}]
		if me != -1:
			avatars[me] = UI.avatar
	_base = me if me != -1 else colors[0]
	_build(colors)
	if multiplayer.is_server():
		var order := range(108)
		order.shuffle()
		state = Rules.new_state(colors, order)
		_begin(Rules.view_for(state, me))
	else:
		hint.text = "Dealing..."
		_hello.rpc_id(1)  # the host may have started already; it answers with our current view


## First view in hand: lay out the table and start the turn loop.
func _begin(v: Dictionary) -> void:
	view = v
	_place_seats()
	if v.discard.size() == 1 and v.counts.values().all(func(n): return n == Rules.HAND):
		busy = true  # events that arrive meanwhile wait in `pending`
		await _deal()
		busy = false
	_refresh()
	_next()


## Seven rounds of cards fly from the pile to every seat, then the first discard turns over.
func _deal() -> void:
	hint.text = "Dealing..."
	var colors: Array = view.colors
	var start := colors.find(_base)
	var dealt: int = view.pile_count + 1 + Rules.HAND * colors.size()
	table.pile_count = dealt
	table.set_discards([])
	var mine := []
	for c in colors:
		players[c].count = 0
	for k in Rules.HAND:
		for i in colors.size():
			var c: int = colors[(start + 1 + i) % colors.size()]  # dealer's left first
			dealt -= 1
			table.pile_count = dealt
			Sfx.play("hop", 0.15)
			if c == me:
				mine.append(view.hand[k])
				hand.set_cards(mine, table.to_global(Table.PILE_AT))
				players[c].count = mine.size()
			else:
				var card := Card.new()
				card.z_index = 10
				table.add_child(card)
				card.position = Table.PILE_AT
				card.fly_to(table.to_local(_seat_pos(c)), randf_range(-0.4, 0.4), 0.3, Seat.FAN_SCALE)
				get_tree().create_timer(0.3).timeout.connect(func():
					card.queue_free()
					players[c].count += 1)
			await get_tree().create_timer(0.07).timeout
	await get_tree().create_timer(0.4).timeout
	var first := Card.new()
	first.id = view.discard[0]
	first.z_index = 10
	table.add_child(first)
	first.position = Table.PILE_AT
	first.flip(0.3)
	await first.fly_to(table.spot(first.id), table.tilt(first.id), 0.35, 1.0)
	table.push(first)
	table.pile_count = view.pile_count
	Sfx.play("hop")


func _build(colors: Array) -> void:
	_oy = maxf(0.0, (get_viewport_rect().size.y - 1920.0) / 2)  # center on tall phones
	add_child(table_root)
	table.position = Vector2(540, TABLE_Y + _oy)
	table_root.add_child(table)
	hand.position = Vector2(540, HAND_Y + _oy)
	hand.scale = Vector2(HAND_SCALE, HAND_SCALE)
	hand.picked.connect(_on_pick)
	table_root.add_child(hand)
	hud.theme = get_tree().root.theme  # themes don't flow through Node2D parents
	hud.size = get_viewport_rect().size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.z_index = 100  # above stacked and flying cards
	add_child(hud)
	for c in colors:
		var seat := Seat.new()
		seat.color = UI.COLORS[c]
		seat.variant = c
		seat.player_name = names[c]
		seat.avatar = avatars[c]
		seat.catch_pressed.connect(_on_catch)
		hud.add_child(seat)
		players[c] = seat
	hint.position = Vector2(0, TABLE_Y + Table.RADIUS + 30 + _oy)
	hint.size = Vector2(1080, 70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 44)
	hud.add_child(hint)
	pass_btn = UI.button("PASS", UI.ACCENT, Vector2(240, 96), 44)
	pass_btn.position = Vector2(420, 1382 + _oy)
	pass_btn.pressed.connect(func(): if _my_turn(): _intent({"do": "pass"}, me))
	pass_btn.hide()
	hud.add_child(pass_btn)
	last_btn = _round_button("LAST\nCARD!", UI.COLORS[0], 190)
	last_btn.position = LAST_AT + Vector2(0, _oy) - last_btn.size / 2
	last_btn.pressed.connect(func(): if _my_turn(): _intent({"do": "last"}, me))
	last_btn.visible = me != -1
	hud.add_child(last_btn)
	var back := UI.icon_button("back", 120)
	back.position = Vector2(30, 50)
	back.pressed.connect(on_back)
	hud.add_child(back)


## Big round chunky button (LAST CARD!): dim and inert until it can be used.
func _round_button(text: String, color: Color, d: float) -> Button:
	var b := UI.button(text, color, Vector2(d, d), 40)
	b.size = Vector2(d, d)
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(state_name).duplicate()
		s.set_corner_radius_all(int(d / 2))
		s.border_color = UI.INK
		s.set_border_width_all(6)
		s.border_width_bottom = 4 if state_name == "pressed" else 14
		if state_name == "disabled":
			s.bg_color = color.darkened(0.45)
		b.add_theme_stylebox_override(state_name, s)
	b.add_theme_constant_override("line_spacing", -12)
	return b


func _to_menu() -> void:
	UI.reset_to("res://ui/screens/home.gd")


func on_back() -> void:
	if _picker:
		_close_picker()
	elif view.get("phase") == "over":
		_to_menu()
	elif await UI.confirm("Leave game?", "Your progress will be lost." if owners.is_empty() else "You will leave the room."):
		_to_menu()


## You sit bottom-left; opponents sit round the table in play order: left, top, right.
func _place_seats() -> void:
	var colors: Array = view.colors
	var i := colors.find(_base)
	var others := []
	for k in range(1, colors.size()):
		others.append(colors[(i + k) % colors.size()])
	for k in others.size():
		var spot: Array = SPOTS[others.size()][k]
		players[others[k]].position = spot[0] + Vector2(0, _oy)
		players[others[k]].facing = spot[1]
	players[_base].position = MY_SPOT + Vector2(0, _oy)
	players[_base].fan_visible = me == -1  # all-bot games: the bottom bot's hand shows as a fan
	players[_base].facing = Vector2.RIGHT


## Where color c's cards come from and go to on screen.
func _seat_pos(c: int) -> Vector2:
	return hand.global_position if c == me else players[c].fan_center()


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
	for c in players:
		var seat: Seat = players[c]
		seat.active = c == view.turn and not over
		seat.count = view.counts[c]
		var place: int = view.winners.find(c)
		seat.note = PLACES[place] if place != -1 and place < PLACES.size() else ""
	_controls()


## Buttons, playable cards and the hint for whoever is looking at the phone.
func _controls() -> void:
	var mine := _my_turn()
	var acts := Rules.legal(view, view.hand) if mine else []
	var ids := acts.filter(func(a): return a.do == "play").map(func(a): return a.id)
	hand.mark(ids, mine)
	var can_call := acts.any(func(a): return a.do == "last")
	last_btn.disabled = not can_call
	if can_call and _last_pulse == null:
		_last_pulse = UI.pulse(last_btn)
	elif not can_call and _last_pulse:
		_last_pulse.kill()
		_last_pulse = null
		last_btn.scale = Vector2.ONE
	pass_btn.visible = mine and view.phase == "drawn"
	for pc in players:
		players[pc].show_catch(view.phase != "over" and view.catchable == pc and pc != me and me != -1)
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
	elif seats[c] == "remote" and owners[c] != 0:
		hint.text = "Waiting for %s..." % names[c]
	else:
		hint.text = "%s is thinking..." % names[c]


func _my_turn() -> bool:
	return (me != -1 and not view.is_empty() and view.turn == me and seats[me] == "human" and view.phase != "over"
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
		Input.vibrate_handheld(40)
	_turn_seen = c
	if who == "bot":
		players[c].note = "Thinking..."
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
		if sender != 0:
			_rejected.rpc_id(sender)
		return
	if ev.do == "play" and ev.catchable:
		_bots_catch(c)
	for pc in state.colors:  # each phone gets only its own seat's view
		var peer: int = owners[pc] if not owners.is_empty() else 0
		if peer > 1 and peer in _synced:
			_show.rpc_id(peer, Rules.event_for(ev, pc), Rules.view_for(state, pc))
	_show(Rules.event_for(ev, me), Rules.view_for(state, me))


## Client's table is ready: send its view (the game may already be under way).
@rpc("any_peer", "reliable")
func _hello() -> void:
	var peer := multiplayer.get_remote_sender_id()
	var c := owners.find(peer)
	if multiplayer.is_server() and c != -1 and not peer in _synced:
		_synced.append(peer)
		_show.rpc_id(peer, {"do": "sync"}, Rules.view_for(state, c))


## The host turned our action down (someone else caught first, ...): let the player try again.
@rpc("authority", "reliable")
func _rejected() -> void:
	waiting_host = false
	if not busy:
		_controls()


## One bot opponent may notice the missing call and shout CATCH after a moment.
func _bots_catch(target: int) -> void:
	var bots: Array = state.colors.filter(func(b): return b != target and seats[b] == "bot")
	if bots.is_empty() or not Ai.wants_catch():
		return
	var b: int = bots.pick_random()
	await get_tree().create_timer(randf_range(0.4, 1.3)).timeout
	if is_inside_tree() and state.catchable == target:
		_intent({"do": "catch", "target": target}, b)


@rpc("authority", "reliable")
func _show(ev: Dictionary, v: Dictionary) -> void:
	shown.emit(ev, v)
	waiting_host = false
	if ev.do == "sync":
		_begin(v)
		return
	pending.append([ev, v])
	if not busy and not view.is_empty():
		_next()


func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server():
		return
	_synced.erase(id)
	for c in 4:
		if owners[c] == id:
			owners[c] = 0
			seats[c] = "bot"
	if not busy and pending.is_empty() and view.phase != "over":
		_next()


func _on_host_left() -> void:
	busy = true
	hint.text = "Host left the game"


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
	players[c].note = ""
	match ev.do:
		"play":
			await _fly_play(ev)
			Sfx.play("hop")
			table.wobble()
			var k := Rules.kind_of(ev.id)
			if k == Rules.REVERSE:
				table.dir = v.dir
				table.spin_burst()
			table.top_color = UI.COLORS[ev.top_color]
			if ev.out:
				Fx.burst(table_root, _seat_pos(c), col)
				Sfx.play("home", 0.0)
				if v.phase != "over":
					_popup("%s: %s!" % [names[c], PLACES[v.winners.find(c)]], col, true)
			elif k == Rules.SKIP or k == Rules.REVERSE:
				_stamp("SKIP!" if k == Rules.SKIP else "REVERSE!", col)
			elif k == Rules.WILD4:
				_stamp("+%d!" % ev.pending, UI.COLORS[ev.top_color])
			elif k == Rules.DRAW2:
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
			players[c].note = "Pass"
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
		players[c].note = "No luck"
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
		card.scale = Vector2(Seat.FAN_SCALE, Seat.FAN_SCALE)
		card.flip(0.3)
	card.z_index = 10
	await card.fly_to(table.spot(ev.id), table.tilt(ev.id), 0.35, 1.0)
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
		card.fly_to(to, 0.0, 0.35, Seat.FAN_SCALE)
		get_tree().create_timer(0.36).timeout.connect(card.queue_free)
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.3).timeout


func _popup(text: String, color: Color, big := false) -> void:
	Fx.popup(hud, text, color, table.position.y, big)


## A big tilted stamp slammed onto the table (Skip, Reverse, +4).
func _stamp(text: String, color: Color) -> void:
	var stamp := PanelContainer.new()
	var style := UI.box(color, 0, 36)
	style.set_border_width_all(12)
	style.border_color = UI.CREAM
	style.set_content_margin_all(28)
	style.content_margin_bottom = 20
	stamp.add_theme_stylebox_override("panel", style)
	var l := UI.label_on(color, text, 120)
	stamp.add_child(l)
	stamp.modulate.a = 0.0
	hud.add_child(stamp)
	await get_tree().process_frame  # let it size itself
	stamp.position = Vector2(540, table.position.y) - stamp.size / 2
	stamp.pivot_offset = stamp.size / 2
	stamp.rotation = -0.2
	stamp.scale = Vector2(2.6, 2.6)
	var tw := stamp.create_tween()
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.1)
	tw.tween_callback(Fx.shake.bind(table_root))
	tw.tween_interval(0.6)
	tw.tween_property(stamp, "modulate:a", 0.0, 0.3)
	tw.tween_callback(stamp.queue_free)


# --- overlays -----------------------------------------------------------------

func _open_picker(id: int) -> void:
	_picker = ColorRect.new()
	_picker.color = Color(UI.BG_TOP, 0.92)
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
	_results = Results.new()  # set first so _next can't open it twice
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():  # left during the pause
		return
	hint.hide()
	for b in [last_btn, pass_btn]:
		b.hide()
	_results.ranking = Rules.ranking(view)
	_results.names = names
	_results.avatars = avatars
	_results.me = me
	_results.reveal = view.get("reveal", {})
	_results.can_restart = owners.is_empty() or multiplayer.is_server()
	_results.play_again.connect(_play_again)
	_results.home.connect(_to_menu)
	hud.add_child(_results)


func _play_again() -> void:
	if owners.is_empty():
		UI.restart()
	else:
		var n := names.duplicate()
		for c in 4:
			if owners[c] == 0:  # players who left are bots now
				n[c] = Games.BOT_NAMES[c]
		var a := avatars.duplicate()
		for c in 4:
			if owners[c] == 0:
				a[c] = {}
		_restart.rpc(owners, n, a)


@rpc("authority", "call_local", "reliable")
func _restart(o: Array, n: Array, a: Array) -> void:
	UI.restart({"owners": o, "names": n, "avatars": a})
