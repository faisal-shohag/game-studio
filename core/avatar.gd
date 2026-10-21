## Player avatars: one of the cartoon faces or the player's own photo. An avatar is a small
## Dictionary so it can travel over LAN RPCs:
##   {"face": n}           preset look, n in 0..FACES-1
##   {"photo": bytes}      a SIZE x SIZE JPEG (a few KB)
##   {}                    none: the game shows its own default (pawn or seat face)

const FaceArt = preload("res://games/shared/face_art.gd")
const FACES := 8
const SIZE := 128  # stored / sent photo side, px
const MAX_BYTES := 24 * 1024  # largest photo accepted from a peer
const MAX_SOURCE := 2048  # picked photos are shrunk to this before cropping

static var _textures := {}  # bytes hash -> ImageTexture


## Avatar from an untrusted peer: anything that isn't a valid face or small photo becomes {}.
static func clean(a) -> Dictionary:
	if typeof(a) != TYPE_DICTIONARY:
		return {}
	if a.size() == 1 and a.has("face") and typeof(a.face) == TYPE_INT and a.face >= 0 and a.face < FACES:
		return {"face": a.face}
	if a.size() == 1 and a.has("photo") and typeof(a.photo) == TYPE_PACKED_BYTE_ARRAY and a.photo.size() <= MAX_BYTES:
		var img := decode(a.photo)
		if img and img.get_width() <= 256 and img.get_height() <= 256:
			return {"photo": a.photo}
	return {}


## PNG, JPEG or WebP bytes -> Image, or null.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	return img if err == OK and not img.is_empty() else null


## A picked photo, shrunk so cropping stays fast. null if it isn't an image.
static func load_source(bytes: PackedByteArray) -> Image:
	var img := decode(bytes)
	if img == null:
		return null
	var longest := maxi(img.get_width(), img.get_height())
	if longest > MAX_SOURCE:
		var k := float(MAX_SOURCE) / longest
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_BILINEAR)
	return img


## The square `region` of `img` (source pixels) as a SIZE x SIZE JPEG.
static func photo_from(img: Image, region: Rect2) -> PackedByteArray:
	var r := Rect2i(region).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var out := img.get_region(r)
	out.convert(Image.FORMAT_RGB8)
	out.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return out.save_jpg_to_buffer(0.85)


static func texture(a: Dictionary) -> Texture2D:
	if not a.has("photo"):
		return null
	var key: int = hash(a.photo)
	if not _textures.has(key):
		var img := decode(a.photo)
		_textures[key] = ImageTexture.create_from_image(img) if img else null
	return _textures[key]


## Draws the avatar as a rounded tile (or a circle) of side `size` at `center`, `color` behind
## faces. Returns false (drawing nothing) for an empty avatar, so callers can draw their default.
static func draw(ci: CanvasItem, center: Vector2, size: float, a: Dictionary, color: Color, round := false, happy := true) -> bool:
	if a.has("face"):
		if round:
			ci.draw_circle(center, size * 0.5 + 3, FaceArt.OUTLINE)
			ci.draw_circle(center, size * 0.5, color.lightened(0.45))
			FaceArt.draw(ci, center + Vector2(0, size * 0.04), size * 0.82, color, a.face, happy)
		else:
			FaceArt.draw(ci, center, size, color, a.face, happy)
		return true
	var tex := texture(a)
	if tex == null:
		return false
	var rim := _shape(center, size * 0.5 + 3, round)
	ci.draw_colored_polygon(rim, FaceArt.OUTLINE)
	ci.draw_colored_polygon(_shape(center, size * 0.5, round), Color.WHITE)
	var inner := _shape(center, size * 0.5 - maxf(2.0, size * 0.04), round)
	var half := size * 0.5 - maxf(2.0, size * 0.04)
	var uvs := PackedVector2Array()
	for p in inner:
		uvs.append((p - center) / (2 * half) + Vector2(0.5, 0.5))
	ci.draw_colored_polygon(inner, Color.WHITE, uvs, tex)
	return true


## Outline of a circle, or a square with rounded corners, of half-size h.
static func _shape(center: Vector2, h: float, round: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if round:
		for i in 40:
			pts.append(center + Vector2.from_angle(TAU * i / 40) * h)
		return pts
	var r := h * 0.4
	for k in 4:
		var corner := center + Vector2(h - r if k in [0, 3] else -(h - r), h - r if k < 2 else -(h - r))
		for i in 7:
			pts.append(corner + Vector2.from_angle(k * PI / 2 + i * PI / 12) * r)
	return pts
