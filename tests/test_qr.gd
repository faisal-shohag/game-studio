## Run: godot --headless --path . --script tests/test_qr.gd
extends SceneTree

const Qr = preload("res://core/qr.gd")
const QrScan = preload("res://core/qr_scan.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


## A camera-like photo of matrix `m`: `turn` radians, corners nudged by `tilt` px for perspective,
## optional mirror, uneven light, blur and noise. Quiet zone of 4 modules all round.
func photo(m: Array, side: int, turn: float, tilt: float, mirror := false, noise := 20) -> Image:
	var n := m.size()
	var span := n + 8.0
	var half := side * 0.36
	var c := Vector2(side, side) / 2
	var corners := []
	for k in 4:
		var p := Vector2([-1, 1, 1, -1][k], [-1, -1, 1, 1][k]) * half
		p = p.rotated(turn) + Vector2(randf_range(-tilt, tilt), randf_range(-tilt, tilt))
		corners.append(c + p)
	var src := [Vector2(0, 0), Vector2(span, 0), Vector2(span, span), Vector2(0, span)]
	var inv := QrScan._homography(corners, src)  # image -> module coords
	var px := PackedByteArray()
	px.resize(side * side)
	for y in side:
		for x in side:
			var q := QrScan._map(inv, x + 0.5, y + 0.5) - Vector2(4, 4)
			var u := int(floor(q.x))
			var v := int(floor(q.y))
			if mirror:
				u = n - 1 - u
			var dark: bool = u >= 0 and v >= 0 and u < n and v < n and m[v][u] == 1
			var light := 70.0 + 120.0 * x / side  # light falls off across the picture
			var val := (light * 0.25 if dark else light) + randf_range(-noise, noise)
			px[y * side + x] = clampi(int(val), 0, 255)
	var blurred := px.duplicate()  # 3x3 box blur: the camera is never quite sharp
	for y in range(1, side - 1):
		for x in range(1, side - 1):
			var s := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					s += px[(y + dy) * side + x + dx]
			blurred[y * side + x] = s / 9
	return Image.create_from_data(side, side, false, Image.FORMAT_L8, blurred)


func _init() -> void:
	seed(7)
	# Reed-Solomon known answer: "HELLO WORLD" as 1-M data codewords (ISO 18004 / Thonky example)
	var hello := PackedByteArray([32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17])
	check(Qr.rs_encode(hello, 10) == PackedByteArray([196, 35, 39, 119, 235, 215, 231, 226, 93, 23]), "RS EC for HELLO WORLD")

	# error correction: up to n_ec/2 bad codewords fixed, more refused
	for trial in 40:
		var data := PackedByteArray()
		for i in 28:
			data.append(randi() % 256)
		var block := data + Qr.rs_encode(data, 16)
		var bad := block.duplicate()
		var spots := range(block.size())
		spots.shuffle()
		for i in 8:
			bad[spots[i]] ^= 1 + randi() % 255
		check(Qr.rs_correct(bad, 16) and bad == block, "8 errors fixed (trial %d)" % trial)
	var refused := 0
	for trial in 40:
		var data := PackedByteArray()
		for i in 28:
			data.append(randi() % 256)
		var bad := data + Qr.rs_encode(data, 16)
		var spots := range(bad.size())
		spots.shuffle()
		for i in 9:
			bad[spots[i]] ^= 1 + randi() % 255
		if not Qr.rs_correct(bad, 16):
			refused += 1
	check(refused >= 38, "9 errors refused (%d of 40)" % refused)

	# round trips through every version
	var sizes := {10: 1, 20: 2, 40: 3, 60: 4, 80: 5, 100: 6}
	for length in sizes:
		var text := ""
		for i in length:
			text += char(33 + (i * 7) % 90)
		var m := Qr.encode(text)
		check(m.size() == Qr.size_of(sizes[length]), "%d bytes -> version %d" % [length, sizes[length]])
		check(Qr.read_matrix(m) == text, "round trip %d bytes" % length)
	check(Qr.encode("x".repeat(107)).is_empty(), "too long for version 6")
	var join := "GSJOIN:192.168.0.122,10.0.0.7"
	var jm := Qr.encode(join)
	check(Qr.read_matrix(jm) == join, "join payload round trip")
	var dirty := jm.duplicate(true)  # a few smudged modules
	for k in 12:
		var y := 9 + randi() % (dirty.size() - 9)
		var x := 9 + randi() % (dirty.size() - 9)
		dirty[y][x] ^= 1
	check(Qr.read_matrix(dirty) == join, "smudged modules corrected")
	check(Qr.read_matrix(Qr._grid(25)) == "" and Qr.read_matrix([]) == "", "blank matrix")

	# camera-like pictures
	var cases := [[0.0, 0.0, false], [0.3, 6.0, false], [PI / 2, 0.0, false], [PI, 10.0, false],
		[-0.5, 14.0, false], [0.2, 4.0, true], [2.2, 8.0, false]]
	for k in cases.size():
		var cs: Array = cases[k]
		var img := photo(jm, 360, cs[0], cs[1], cs[2])
		check(QrScan.decode(img) == join, "photo %d (turn %.1f, tilt %d, mirror %s)" % [k, cs[0], cs[1], cs[2]])
	var big := Qr.encode("GSJOIN:" + "192.168.100.200,".repeat(4) + "10.0.0.1")
	check(QrScan.decode(photo(big, 480, 0.25, 8.0)) == Qr.read_matrix(big), "photo of a version %d code" % ((big.size() - 17) / 4))
	var small := Qr.encode("GSJOIN:10.0.0.2")
	check(QrScan.decode(photo(small, 240, 0.4, 3.0)) == "GSJOIN:10.0.0.2", "small photo of a version 1 code")
	var blank := Image.create(300, 300, false, Image.FORMAT_L8)
	blank.fill(Color(0.8, 0.8, 0.8))
	check(QrScan.decode(blank) == "", "blank picture")
	var noise := PackedByteArray()
	for i in 300 * 300:
		noise.append(randi() % 256)
	check(QrScan.decode(Image.create_from_data(300, 300, false, Image.FORMAT_L8, noise)) == "", "noise")

	# which host IP to join
	check(QrScan.join_ip("GSJOIN:192.168.0.5,10.0.0.9", ["10.0.0.33"]) == "10.0.0.9", "same subnet wins")
	check(QrScan.join_ip("GSJOIN:192.168.0.5,10.0.0.9", ["172.16.0.2"]) == "192.168.0.5", "else the first")
	check(QrScan.join_ip("GSJOIN:nope,1.2.3", []) == "" and QrScan.join_ip("https://example.com", []) == "", "junk")

	# black-and-white frames (as the scanner's GPU threshold makes them) skip the CPU threshold
	var shot := photo(jm, 400, 0.3, 6.0)
	var bw := Image.create_from_data(400, 400, false, Image.FORMAT_L8, QrScan._binarize(shot.get_data(), 400, 400))
	check(QrScan.decode(bw, true) == join, "pre-thresholded frame")
	var t := Time.get_ticks_msec()
	QrScan.decode(shot)
	var full := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	QrScan.decode(bw, true)
	print("qr: ", "OK" if fails == 0 else "%d failed" % fails,
		" (decode 400 px: %d ms, pre-thresholded: %d ms)" % [full, Time.get_ticks_msec() - t])
	quit(1 if fails else 0)
