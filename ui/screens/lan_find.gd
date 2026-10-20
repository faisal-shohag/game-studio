## Find a LAN room: radar while listening for host broadcasts, a card per room found,
## or type the host's IP.
extends "res://ui/screen.gd"

const Room = preload("res://ui/screens/lan_room.gd")

var udp := PacketPeerUDP.new()
var rooms := VBoxContainer.new()
var found := {}  # ip -> card
var manual := HBoxContainer.new()
var ip_edit := LineEdit.new()


## Pulsing rings around a wifi dot.
class Radar extends Control:
	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2
		var t := Time.get_ticks_msec() / 1000.0
		for k in 3:
			var p := fmod(t * 0.5 + k / 3.0, 1.0)
			draw_arc(c, 70 + p * 120, 0, TAU, 64, Color(1, 1, 1, (1.0 - p) * 0.7), 8, true)
		draw_circle(c, 70, UI.COLORS[3])
		draw_arc(c, 70, 0, TAU, 64, UI.INK, 8, true)
		for r in [1, 2]:
			draw_arc(c + Vector2(0, 18), r * 18, -PI * 0.78, -PI * 0.22, 16, Color.WHITE, 8)
		draw_circle(c + Vector2(0, 18), 7, Color.WHITE)


func _init() -> void:
	title = "JOIN ROOM"


func build() -> void:
	UI.reset_network()  # back from a room
	# shortcut: some Android phones drop broadcasts without a MulticastLock (needs a plugin); typed IP covers that
	udp.bind(Room.DISCOVERY_PORT)
	var radar := Radar.new()
	radar.custom_minimum_size = Vector2(400, 400)
	content.add_child(radar)
	content.add_child(UI.label("Looking for rooms...", 50))
	rooms.add_theme_constant_override("separation", 24)
	content.add_child(rooms)
	var link := UI.button("Can't find it? Enter IP", UI.INK.lightened(0.3), Vector2(720, 110), 40)
	content.add_child(link)
	manual.add_theme_constant_override("separation", 20)
	ip_edit.placeholder_text = "192.168.x.x"
	ip_edit.custom_minimum_size = Vector2(520, 130)
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_edit.add_theme_font_size_override("font_size", 50)
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	ip_edit.text_submitted.connect(func(t): _join(t.strip_edges()))
	manual.add_child(ip_edit)
	var go := UI.button("JOIN", UI.COLORS[1], Vector2(240, 130), 54)
	go.pressed.connect(func(): _join(ip_edit.text.strip_edges()))
	manual.add_child(go)
	manual.hide()
	content.add_child(manual)
	link.pressed.connect(func():
		link.hide()
		manual.show()
		ip_edit.grab_focus())


func _process(_delta: float) -> void:
	while udp.get_available_packet_count() > 0:
		var parts := udp.get_packet().get_string_from_utf8().split("|")
		var ip := udp.get_packet_ip()
		if parts[0] != Room.HELLO or ip in found:
			continue
		var host_name := parts[1].strip_edges().left(UI.NAME_MAX) if parts.size() > 1 else ""
		var card := UI.tile(UI.COLORS[1], UI.icon("wifi", Color.WHITE, 140),
			"%s's room" % (host_name if host_name != "" else "Friend"), "Tap to join  " + ip, Vector2(900, 200), 54)
		card.pressed.connect(_join.bind(ip))
		rooms.add_child(card)
		found[ip] = card
		card.scale = Vector2(0.6, 0.6)
		card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(card, "scale", Vector2.ONE, 0.35)
		Sfx.play("your_turn", 0.0)


func _join(ip: String) -> void:
	if not ip.is_valid_ip_address():
		UI.toast("That IP doesn't look right", UI.COLORS[0])
		return
	UI.go("res://ui/screens/lan_room.gd", {"join_ip": ip})
