## Finds and reads a QR code in a camera image: adaptive black/white threshold, the three finder
## squares, then a perspective grid (refined with the alignment square from version 2 up) sampled
## into a module matrix for Qr.read_matrix. Rotated and mirrored codes work.

const Qr = preload("res://core/qr.gd")
const BLOCK := 8  # threshold block side, px
const JOIN_PREFIX := "GSJOIN:"


## Text of the QR code in `img`, or "". With `binarized`, `img` is already black and white (the
## scanner thresholds camera frames on the GPU), which skips the slowest step.
static func decode(img: Image, binarized := false) -> String:
	var gray: Image = img.duplicate()
	if gray.is_compressed():
		gray.decompress()
	gray.convert(Image.FORMAT_L8)
	var w := gray.get_width()
	var h := gray.get_height()
	if w < 21 or h < 21:
		return ""
	var bits := gray.get_data() if binarized else _binarize(gray.get_data(), w, h)
	var finders := _find_finders(bits, w, h)
	for triple in _triples(finders):
		var text := _read(bits, w, h, triple)
		if text != "":
			return text
	return ""


## From a scanned text, the host IP this phone should join, or "" if it isn't one of ours.
## Prefers an address on the same subnet (first three numbers) as one of `local_ips`.
static func join_ip(text: String, local_ips: Array) -> String:
	if not text.begins_with(JOIN_PREFIX):
		return ""
	var ips := Array(text.substr(JOIN_PREFIX.length()).split(",")).filter(func(ip: String): return ip.is_valid_ip_address())
	if ips.is_empty():
		return ""
	for ip in ips:
		var net: String = ip.substr(0, ip.rfind("."))
		for mine in local_ips:
			if mine.substr(0, mine.rfind(".")) == net:
				return ip
	return ips[0]


# --- black and white --------------------------------------------------------------

## Pixels below 128 are dark, from 255 = light / 0 = dark output. Thresholds are local means over 5x5 blocks of 8x8 px, so gradients and glare from a
## phone screen don't matter; flat blocks count as light unless their neighbours are darker.
static func _binarize(px: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var bw := ceili(w / float(BLOCK))
	var bh := ceili(h / float(BLOCK))
	var avg := PackedInt32Array()
	avg.resize(bw * bh)
	for by in bh:
		for bx in bw:
			var sum := 0
			var lo := 255
			var hi := 0
			var cnt := 0
			for y in range(by * BLOCK, mini(h, by * BLOCK + BLOCK)):
				var row := y * w
				for x in range(bx * BLOCK, mini(w, bx * BLOCK + BLOCK)):
					var v := px[row + x]
					sum += v
					lo = mini(lo, v)
					hi = maxi(hi, v)
					cnt += 1
			var a := sum / cnt
			if hi - lo <= 24:
				a = lo / 2
				if by > 0 and bx > 0:
					var near := (avg[(by - 1) * bw + bx] + 2 * avg[by * bw + bx - 1] + avg[(by - 1) * bw + bx - 1]) / 4
					if lo < near:
						a = near
			avg[by * bw + bx] = a
	var bits := PackedByteArray()
	bits.resize(w * h)
	for by in bh:
		for bx in bw:
			var sum := 0
			for dy in range(-2, 3):
				var yy := clampi(by + dy, 0, bh - 1)
				for dx in range(-2, 3):
					sum += avg[yy * bw + clampi(bx + dx, 0, bw - 1)]
			var t := sum / 25
			for y in range(by * BLOCK, mini(h, by * BLOCK + BLOCK)):
				var row := y * w
				for x in range(bx * BLOCK, mini(w, bx * BLOCK + BLOCK)):
					bits[row + x] = 0 if px[row + x] <= t else 255
	return bits


# --- finder squares ---------------------------------------------------------------

## Candidate finder centers: [{p: Vector2, m: module size, n: hits}].
static func _find_finders(bits: PackedByteArray, w: int, h: int) -> Array:
	var found := []
	for y in range(0, h, 2):
		var counts := [0, 0, 0, 0, 0]
		var state := 0
		var row := y * w
		for x in w + 1:
			var dark := x < w and bits[row + x] < 128
			if dark:
				if state & 1 == 1:
					state += 1
				counts[state] += 1
			elif state == 0 and counts[0] == 0:
				continue  # light before anything dark
			elif state & 1 == 0:
				if state == 4:
					if _ratio_ok(counts) and _confirm(bits, w, h, counts, x, y, found):
						counts = [0, 0, 0, 0, 0]
						state = 0
					else:
						counts = [counts[2], counts[3], counts[4], 1, 0]
						state = 3
				else:
					state += 1
					counts[state] += 1
			else:
				counts[state] += 1
	return found


## Dark-light-dark-light-dark runs in 1:1:3:1:1, give or take half a module.
static func _ratio_ok(c: Array) -> bool:
	var total: int = c[0] + c[1] + c[2] + c[3] + c[4]
	if total < 7 or c.has(0):
		return false
	var m := total / 7.0
	var tol := m * 0.6
	return absf(c[0] - m) < tol and absf(c[1] - m) < tol and absf(c[2] - 3 * m) < 3 * tol \
		and absf(c[3] - m) < tol and absf(c[4] - m) < tol


## A row hit ending at x: check it up-down and left-right through its center, then keep it.
static func _confirm(bits: PackedByteArray, w: int, h: int, counts: Array, x_end: int, y: int, found: Array) -> bool:
	var total: int = counts.reduce(func(a, b): return a + b)
	var cx: float = x_end - counts[4] - counts[3] - counts[2] / 2.0
	var cy := _cross(bits, w, h, int(cx), y, Vector2i(0, 1), counts[2] * 2, total)
	if cy < 0:
		return false
	cx = _cross(bits, w, h, int(cx), int(cy), Vector2i(1, 0), counts[2] * 2, total)
	if cx < 0:
		return false
	var m := total / 7.0
	var p := Vector2(cx, cy)
	for f in found:
		if f.p.distance_to(p) <= f.m * 2 and absf(f.m - m) <= maxf(1.0, f.m * 0.5):
			f.p = (f.p * f.n + p) / (f.n + 1)
			f.m = (f.m * f.n + m) / (f.n + 1)
			f.n += 1
			return true
	found.append({"p": p, "m": m, "n": 1})
	return true


## Runs through (x, y) along `dir` both ways; returns the refined center coordinate along the
## axis (x for horizontal, y otherwise), or -1 if the 1:1:3:1:1 pattern isn't there.
static func _cross(bits: PackedByteArray, w: int, h: int, x: int, y: int, dir: Vector2i, max_run: int, total: float) -> float:
	var at := func(k: int) -> int:
		var xx := x + dir.x * k
		var yy := y + dir.y * k
		return -1 if xx < 0 or yy < 0 or xx >= w or yy >= h else 1 if bits[yy * w + xx] < 128 else 0
	if at.call(0) != 1:
		return -1.0
	var c := [0, 0, 0, 0, 0]
	var k := 0
	while at.call(k) == 1 and c[2] <= max_run:
		c[2] += 1
		k -= 1
	while at.call(k) == 0 and c[1] <= max_run:
		c[1] += 1
		k -= 1
	while at.call(k) == 1 and c[0] <= max_run:
		c[0] += 1
		k -= 1
	k = 1
	while at.call(k) == 1 and c[2] <= max_run * 2:
		c[2] += 1
		k += 1
	while at.call(k) == 0 and c[3] <= max_run:
		c[3] += 1
		k += 1
	while at.call(k) == 1 and c[4] <= max_run:
		c[4] += 1
		k += 1
	var sum: int = c[0] + c[1] + c[2] + c[3] + c[4]
	if 5 * absf(sum - total) >= 2 * total or not _ratio_ok(c):
		return -1.0
	var end := k  # first position past the last dark run
	var center: float = end - c[4] - c[3] - c[2] / 2.0
	return (x if dir.x != 0 and dir.y == 0 else y) + center * (dir.x if dir.y == 0 else dir.y)


## Likely finder triples, best first: similar module sizes and a near right-angled corner.
static func _triples(found: Array) -> Array:
	var pool := found.filter(func(f): return f.n >= 2)
	if pool.size() < 3:
		pool = found.duplicate()
	pool.sort_custom(func(a, b): return a.n > b.n)
	pool = pool.slice(0, 8)
	var scored := []
	for i in pool.size():
		for j in range(i + 1, pool.size()):
			for k in range(j + 1, pool.size()):
				var t := _order([pool[i], pool[j], pool[k]])
				var ms := [pool[i].m, pool[j].m, pool[k].m]
				if ms.max() > ms.min() * 1.6:
					continue
				var a: float = t[1].p.distance_to(t[0].p)  # TL-TR
				var b: float = t[1].p.distance_to(t[2].p)  # TL-BL
				if a < 7 * ms.min() or b < 7 * ms.min() or maxf(a, b) > minf(a, b) * 1.6:
					continue
				var cos := absf((t[0].p - t[1].p).normalized().dot((t[2].p - t[1].p).normalized()))
				if cos > 0.35:
					continue
				scored.append([cos + absf(a - b) / maxf(a, b), t])
	scored.sort_custom(func(x, y): return x[0] < y[0])
	return scored.slice(0, 4).map(func(s): return s[1])


## [top-right, top-left, bottom-left]: top-left is opposite the longest side.
static func _order(t: Array) -> Array:
	var d01: float = t[0].p.distance_to(t[1].p)
	var d12: float = t[1].p.distance_to(t[2].p)
	var d02: float = t[0].p.distance_to(t[2].p)
	var a
	var b
	var c
	if d12 >= d01 and d12 >= d02:
		b = t[0]; a = t[1]; c = t[2]
	elif d02 >= d01 and d02 >= d12:
		b = t[1]; a = t[0]; c = t[2]
	else:
		b = t[2]; a = t[0]; c = t[1]
	# image y points down: make a = top-right, c = bottom-left
	var cross: float = (a.p.x - b.p.x) * (c.p.y - b.p.y) - (a.p.y - b.p.y) * (c.p.x - b.p.x)
	if cross < 0:
		var s = a
		a = c
		c = s
	return [a, b, c]


# --- sampling ---------------------------------------------------------------------

static func _read(bits: PackedByteArray, w: int, h: int, t: Array) -> String:
	var tr: Vector2 = t[0].p
	var tl: Vector2 = t[1].p
	var bl: Vector2 = t[2].p
	var m: float = (t[0].m + t[1].m + t[2].m) / 3.0
	var across := (tl.distance_to(tr) + tl.distance_to(bl)) / 2.0 / m
	var version := clampi(roundi((across + 7 - 17) / 4.0), 1, Qr.MAX_VERSION)
	for v in [version, version - 1, version + 1]:
		if v < 1 or v > Qr.MAX_VERSION:
			continue
		var n := Qr.size_of(v)
		var src := [Vector2(3.5, 3.5), Vector2(n - 3.5, 3.5), Vector2(3.5, n - 3.5)]
		var dst := [tl, tr, bl]
		var grids := []
		if v >= 2:
			var al := _find_alignment(bits, w, h, tl, tr, bl, n, m)
			if al != Vector2.INF:
				grids.append(_homography(src + [Vector2(n - 6.5, n - 6.5)], dst + [al]))
		grids.append(_homography(src + [Vector2(n - 3.5, n - 3.5)], dst + [tr + bl - tl]))  # flat grid
		for hm in grids:
			var mat := _sample(bits, w, h, hm, n)
			var text := Qr.read_matrix(mat)
			if text == "":
				text = Qr.read_matrix(_transpose(mat))  # mirrored image
			if text != "":
				return text
	return ""


## The alignment square near where a flat grid puts it, or INF.
static func _find_alignment(bits: PackedByteArray, w: int, h: int, tl: Vector2, tr: Vector2, bl: Vector2, n: int, m: float) -> Vector2:
	var du := (tr - tl) / (n - 7)
	var dv := (bl - tl) / (n - 7)
	var guess := tl + du * (n - 10) + dv * (n - 10)
	var reach := int(m * 3.5)
	var best := Vector2.INF
	var best_score := 21
	var step := maxi(1, int(m / 3))
	for pass_ in 2:  # coarse, then fine around the best coarse spot
		var around := guess if pass_ == 0 or best == Vector2.INF else best
		var r := reach if pass_ == 0 else step
		for oy in range(-r, r + 1, step if pass_ == 0 else 1):
			for ox in range(-r, r + 1, step if pass_ == 0 else 1):
				var c := around + Vector2(ox, oy)
				var score := _align_score(bits, w, h, c, du, dv)
				if score > best_score:
					best_score = score
					best = c
	return best


## How many of the 25 modules around `c` match an alignment square.
static func _align_score(bits: PackedByteArray, w: int, h: int, c: Vector2, du: Vector2, dv: Vector2) -> int:
	var score := 0
	for j in range(-2, 3):
		for i in range(-2, 3):
			var p := c + du * i + dv * j
			var x := int(p.x)
			var y := int(p.y)
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var dark: bool = bits[y * w + x] < 128
			if dark == (maxi(absi(i), absi(j)) != 1):
				score += 1
	return score


## Module grid sampled at each module's center.
static func _sample(bits: PackedByteArray, w: int, h: int, hm: PackedFloat64Array, n: int) -> Array:
	var rows := []
	for v in n:
		var row := PackedByteArray()
		row.resize(n)
		for u in n:
			var p := _map(hm, u + 0.5, v + 0.5)
			var x := int(p.x)
			var y := int(p.y)
			row[u] = 1 if x >= 0 and y >= 0 and x < w and y < h and bits[y * w + x] < 128 else 0
		rows.append(row)
	return rows


static func _transpose(m: Array) -> Array:
	var n := m.size()
	var out := []
	for y in n:
		var row := PackedByteArray()
		row.resize(n)
		for x in n:
			row[x] = m[x][y]
		out.append(row)
	return out


## Homography taking 4 `src` points to 4 `dst` points: [a b c d e f g h] with
## x' = (a x + b y + c) / (g x + h y + 1), y' = (d x + e y + f) / (g x + h y + 1).
static func _homography(src: Array, dst: Array) -> PackedFloat64Array:
	var a := []
	for i in 4:
		var s: Vector2 = src[i]
		var d: Vector2 = dst[i]
		a.append([s.x, s.y, 1.0, 0.0, 0.0, 0.0, -s.x * d.x, -s.y * d.x, d.x])
		a.append([0.0, 0.0, 0.0, s.x, s.y, 1.0, -s.x * d.y, -s.y * d.y, d.y])
	for col in 8:  # Gaussian elimination with partial pivoting
		var piv := col
		for r in range(col + 1, 8):
			if absf(a[r][col]) > absf(a[piv][col]):
				piv = r
		var tmp = a[col]
		a[col] = a[piv]
		a[piv] = tmp
		var div: float = a[col][col]
		if absf(div) < 1e-9:
			return PackedFloat64Array([1, 0, 0, 0, 1, 0, 0, 0])
		for k in range(col, 9):
			a[col][k] /= div
		for r in 8:
			if r != col:
				var f: float = a[r][col]
				for k in range(col, 9):
					a[r][k] -= f * a[col][k]
	var out := PackedFloat64Array()
	for r in 8:
		out.append(a[r][8])
	return out


static func _map(hm: PackedFloat64Array, x: float, y: float) -> Vector2:
	var z := hm[6] * x + hm[7] * y + 1.0
	return Vector2((hm[0] * x + hm[1] * y + hm[2]) / z, (hm[3] * x + hm[4] * y + hm[5]) / z)
