## Run: godot --headless --path . --script tests/test_avatar.gd
extends SceneTree

const Avatar = preload("res://core/avatar.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


## 600x400 picture split into red / green / blue / yellow quadrants.
func quadrants() -> Image:
	var img := Image.create(600, 400, false, Image.FORMAT_RGB8)
	img.fill_rect(Rect2i(0, 0, 300, 200), Color.RED)
	img.fill_rect(Rect2i(300, 0, 300, 200), Color.GREEN)
	img.fill_rect(Rect2i(0, 200, 300, 200), Color.BLUE)
	img.fill_rect(Rect2i(300, 200, 300, 200), Color.YELLOW)
	return img


func near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.25


func _init() -> void:
	for n in Avatar.FACES:
		check(Avatar.clean({"face": n}) == {"face": n}, "face %d accepted" % n)
	check(Avatar.clean({"face": 8}).is_empty() and Avatar.clean({"face": -1}).is_empty(), "face out of range")
	check(Avatar.clean({"face": "3"}).is_empty() and Avatar.clean({"face": 2.0}).is_empty(), "face of the wrong type")
	check(Avatar.clean(null).is_empty() and Avatar.clean([1]).is_empty() and Avatar.clean({}).is_empty(), "not an avatar")
	check(Avatar.clean({"face": 1, "photo": PackedByteArray()}).is_empty(), "extra keys")

	var img := quadrants()
	var photo := Avatar.photo_from(img, Rect2(100, 0, 400, 400))
	check(photo.size() > 0 and photo.size() <= Avatar.MAX_BYTES, "photo is small (%d bytes)" % photo.size())
	check(Avatar.clean({"photo": photo}) == {"photo": photo}, "own photo accepted")
	var back := Avatar.decode(photo)
	check(back != null and back.get_size() == Vector2i(Avatar.SIZE, Avatar.SIZE), "photo is %dx%d" % [Avatar.SIZE, Avatar.SIZE])
	if back:
		check(near(back.get_pixel(10, 10), Color.RED) and near(back.get_pixel(117, 10), Color.GREEN), "crop keeps the top quadrants")
		check(near(back.get_pixel(10, 117), Color.BLUE) and near(back.get_pixel(117, 117), Color.YELLOW), "crop keeps the bottom quadrants")
	var corner := Avatar.decode(Avatar.photo_from(img, Rect2(300, 200, 200, 200)))
	check(corner != null and near(corner.get_pixel(64, 64), Color.YELLOW), "crop region maps to source pixels")

	var junk := PackedByteArray()
	junk.resize(500)
	junk.fill(7)
	check(Avatar.clean({"photo": junk}).is_empty(), "not an image")
	var big := Image.create(600, 600, false, Image.FORMAT_RGB8)
	big.fill(Color.DARK_CYAN)
	check(Avatar.clean({"photo": big.save_jpg_to_buffer(0.9)}).is_empty(), "photo too large in pixels")
	var huge := PackedByteArray()
	huge.resize(Avatar.MAX_BYTES + 1)
	huge[0] = 0xFF
	huge[1] = 0xD8
	check(Avatar.clean({"photo": huge}).is_empty(), "photo too many bytes")
	check(Avatar.load_source(quadrants().save_png_to_buffer()) != null, "png source loads")
	var giant := Image.create(4000, 3000, false, Image.FORMAT_RGB8)
	var src := Avatar.load_source(giant.save_jpg_to_buffer(0.5))
	check(src != null and maxi(src.get_width(), src.get_height()) == Avatar.MAX_SOURCE, "huge photos are shrunk")

	print("avatar: ", "OK" if fails == 0 else "%d failed" % fails)
	quit(1 if fails else 0)
