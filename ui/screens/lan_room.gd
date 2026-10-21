## LAN room, for the host and for joined players.
## Host: runs the ENet server, broadcasts the room on UDP, hands seats to joiners, starts the game.
## Joiner: connects to `join_ip` here (not on the find screen) so this node already sits at
## /root/Screen on both phones when the first RPC arrives. Joiners learn the game from the host.
extends "res://ui/screen.gd"

const Games = preload("res://core/games.gd")
const Avatar = preload("res://core/avatar.gd")
const PORT := 7790
const DISCOVERY_PORT := 7791
const HELLO := "GAMESTUDIO"  # broadcast: HELLO|game id|host name
const CORNERS := [0, 1, 3, 2]  # grid order matches board corners

var hosting := false
var join_ip := ""
var game := "ludo"  # host: set by the menu; joiner: taken from the host's _sync
var owners := [1, 0, 0, 0]  # peer id per color; 0 = bot, -1 = off
var names := ["", "", "", ""]  # player names per color (bots/off filled at start)
var avatars := [{}, {}, {}, {}]  # players' avatars per color ({} = bot, off or not sent yet)
var udp := PacketPeerUDP.new()
var status: Label
var info: Label
var grid := GridContainer.new()
var cards := {}  # color -> {button, pawn, name, badge}
var start: Button
var _status_text := ""
var _dots := 0
var _pulse: Tween
var _shown_owners := []


func _init() -> void:
	title = "ROOM"


func build() -> void:
	status = UI.label("", 50)
	content.add_child(status)
	info = UI.label("", 36, Color(1, 1, 1, 0.75))
	content.add_child(info)
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 30)
	for c in CORNERS:
		var b := UI.button("", UI.COLORS[c], Vector2(430, 360))
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		col.offset_bottom = -14
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = MOUSE_FILTER_IGNORE
		var pawn := UI.icon("pawn", UI.COLORS[c], 190)
		pawn.disc = Color(1, 1, 1, 0.35)
		col.add_child(pawn)
		var name_label := UI.label("", 40)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 380
		col.add_child(name_label)
		var badge := UI.label("", 32, Color(1, 1, 1, 0.85))
		col.add_child(badge)
		b.add_child(col)
		b.pressed.connect(_cycle.bind(c))
		grid.add_child(b)
		cards[c] = {"button": b, "pawn": pawn, "name": name_label, "badge": badge}
	content.add_child(grid)
	start = UI.button("START", UI.ACCENT, Vector2(800, 170), 80)
	start.pressed.connect(_on_start)
	content.add_child(start)

	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_fail.bind("Could not connect"))
	multiplayer.server_disconnected.connect(_fail.bind("Host closed the room"))
	var timer := Timer.new()
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start(0.5)

	if hosting:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(PORT, 3) != OK:
			_fail("Could not open the room")
			return
		multiplayer.multiplayer_peer = peer
		names[0] = UI.player_name
		avatars[0] = UI.avatar
		_status_text = "Waiting for friends"
		info.text = "%s room  IP: %s\nTap an empty seat: Bot or Off" % [Games.LIST[game].name, ", ".join(_lan_ips())]
		udp.set_broadcast_enabled(true)
		udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	else:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client(join_ip, PORT) != OK:
			_fail("Could not connect")
			return
		multiplayer.multiplayer_peer = peer
		_status_text = "Joining %s" % join_ip
	_refresh()


func _lan_ips() -> Array:
	return Array(IP.get_local_addresses()).filter(func(ip: String):
		return ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."))


## Every 0.5 s: animate the waiting dots; host also re-broadcasts the room every second.
func _tick() -> void:
	_dots = (_dots + 1) % 4
	status.text = _status_text + ".".repeat(_dots)
	if hosting and _dots % 2 == 0:
		udp.put_packet(("%s|%s|%s" % [HELLO, game, UI.player_name]).to_utf8_buffer())


func _fail(why: String) -> void:
	_status_text = why
	status.text = why
	UI.toast(why, UI.COLORS[0])
	Sfx.play("no_move", 0.0)
	await get_tree().create_timer(1.5).timeout
	if UI.current == self:
		UI.back()


func _on_connected() -> void:
	_status_text = "Waiting for host to start"
	_hello.rpc_id(1, UI.player_name, UI.avatar)
	_refresh()


func _on_peer_joined(id: int) -> void:
	if not hosting:
		return
	var free := owners.find(0)
	if free == -1:
		free = owners.find(-1)
	if free == -1:  # room full
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	owners[free] = id
	names[free] = "Player"
	avatars[free] = {}
	_sync.rpc(game, owners, names, avatars)


func _on_peer_left(id: int) -> void:
	if hosting and id in owners:
		var c := owners.find(id)
		var who: String = names[c]
		owners[c] = 0
		names[c] = ""
		avatars[c] = {}
		_sync.rpc(game, owners, names, avatars)
		_announce.rpc("%s left" % who, false)


## Joiner tells the host its name and avatar. Untrusted input: the name is trimmed and
## length-capped, the avatar checked (anything odd becomes the default look).
@rpc("any_peer", "reliable")
func _hello(player_name: String, avatar: Dictionary) -> void:
	var c := owners.find(multiplayer.get_remote_sender_id())
	if not hosting or c == -1:
		return
	var clean := player_name.strip_edges().left(UI.NAME_MAX)
	names[c] = clean if clean != "" else "Player"
	avatars[c] = Avatar.clean(avatar)
	_sync.rpc(game, owners, names, avatars)
	_announce.rpc("%s joined!" % names[c], true)


@rpc("authority", "call_local", "reliable")
func _announce(text: String, joined: bool) -> void:
	UI.toast(text, UI.COLORS[1] if joined else UI.COLORS[0])
	Sfx.play("home" if joined else "no_move", 0.0)


## Host toggles empty seats between Bot and Off.
func _cycle(c: int) -> void:
	if hosting and owners[c] <= 0:
		owners[c] = -1 if owners[c] == 0 else 0
		_sync.rpc(game, owners, names, avatars)


@rpc("authority", "call_local", "reliable")
func _sync(g: String, o: Array, n: Array, a: Array) -> void:
	if g in Games.LIST:
		game = g
	owners = o
	names = n
	avatars = a
	_refresh()


func _refresh() -> void:
	var me := multiplayer.get_unique_id()
	var joined := hosting or (multiplayer.multiplayer_peer is ENetMultiplayerPeer
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	grid.visible = joined
	if joined and not hosting:
		info.text = "%s's %s room" % [names[owners.find(1)], Games.LIST[game].name]
	for c in cards:
		var card: Dictionary = cards[c]
		var o: int = owners[c]
		card.name.text = names[c] if o > 0 else Games.BOT_NAMES[c] if o == 0 else "Empty seat"
		card.badge.text = "YOU" if o == me else "HOST" if o == 1 else "PLAYER" if o > 0 else "BOT" if o == 0 else "OFF"
		var faces: bool = Games.LIST[game].faces  # a joiner only learns the game here
		var own: Dictionary = avatars[c] if o > 0 else {}  # people show their avatar, bots the game's look
		card.pawn.kind = "avatar" if not own.is_empty() else "face" if faces else "pawn"
		card.pawn.avatar = own
		card.pawn.count = c
		card.pawn.disc = Color(1, 1, 1, 0.0 if faces or not own.is_empty() else 0.35)
		card.pawn.bob = o == me
		card.pawn.queue_redraw()
		card.button.modulate.a = 0.45 if o == -1 else 1.0
		if not _shown_owners.is_empty() and o > 0 and _shown_owners[c] <= 0:  # someone just sat down
			card.button.scale = Vector2(1.15, 1.15)
			card.button.create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).tween_property(card.button, "scale", Vector2.ONE, 0.6)
	_shown_owners = owners.duplicate()
	start.visible = hosting
	var ready := owners.count(-1) <= 2
	start.disabled = not ready
	if ready and hosting and _pulse == null:
		_pulse = UI.pulse(start)
	elif not ready and _pulse:
		_pulse.kill()
		_pulse = null
		start.scale = Vector2.ONE


func _on_start() -> void:
	multiplayer.refuse_new_connections = true
	var full := names.duplicate()
	for c in 4:
		if owners[c] == 0:
			full[c] = Games.BOT_NAMES[c]
	_start.rpc(game, owners, full, avatars)


@rpc("authority", "call_local", "reliable")
func _start(g: String, o: Array, n: Array, a: Array) -> void:
	if not g in Games.LIST:  # host's app has a game this phone doesn't
		_fail("Update the app to play this game")
		return
	UI.go(Games.LIST[g].scene, {"owners": o, "names": n, "avatars": a})  # becomes /root/Screen on every phone
