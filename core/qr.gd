## QR codes, small and self-contained: byte mode, error correction level M, versions 1-6 (up to
## 106 bytes; no version-info blocks needed). encode() builds the module matrix, read_matrix()
## turns a sampled matrix back into text, fixing damaged codewords with Reed-Solomon.
## Layout follows ISO/IEC 18004 (and Nayuki's reference implementation).
## A matrix is an Array of PackedByteArray rows, 1 = dark module.

const MAX_VERSION := 6
## Per version (index 1..6), level M: [EC codewords per block, blocks, data codewords per block].
const BLOCKS := [[], [10, 1, 16], [16, 1, 28], [26, 1, 44], [18, 2, 32], [24, 2, 43], [16, 4, 27]]
## Alignment pattern centers per version (only one lands clear of the finders up to v6).
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34]]
const LEVEL_M := 0  # format bits for level M

static var _exp := PackedByteArray()
static var _log := PackedByteArray()


# --- GF(256) and Reed-Solomon -------------------------------------------------

static func _tables() -> void:
	if not _exp.is_empty():
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]


static func _mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp[_log[a] + _log[b]]


static func _div(a: int, b: int) -> int:
	if a == 0:
		return 0
	return _exp[(_log[a] + 255 - _log[b]) % 255]


## EC codewords for `data` (highest-degree first), generator roots alpha^0..alpha^(n-1).
static func rs_encode(data: PackedByteArray, n_ec: int) -> PackedByteArray:
	_tables()
	var gen := PackedByteArray([1])  # highest degree first
	for i in n_ec:
		var next := PackedByteArray()
		next.resize(gen.size() + 1)
		for j in gen.size():
			next[j] ^= gen[j]
			next[j + 1] ^= _mul(gen[j], _exp[i])
		gen = next
	var rem := PackedByteArray()
	rem.resize(n_ec)
	for d in data:
		var factor: int = d ^ rem[0]
		for j in n_ec - 1:
			rem[j] = rem[j + 1] ^ _mul(gen[j + 1], factor)
		rem[n_ec - 1] = _mul(gen[n_ec], factor)
	return rem


## Fixes up to n_ec/2 wrong codewords of a block (data + EC) in place. False if it can't.
static func rs_correct(block: PackedByteArray, n_ec: int) -> bool:
	_tables()
	var n := block.size()
	var synd := PackedByteArray()  # lowest degree first
	synd.resize(n_ec)
	var clean := true
	for j in n_ec:
		var s := 0
		for i in n:
			s = _mul(s, _exp[j]) ^ block[i]
		synd[j] = s
		clean = clean and s == 0
	if clean:
		return true
	# Berlekamp-Massey: error locator (lowest degree first)
	var lam := [1]
	var prev := [1]
	var l := 0
	var m := 1
	var b := 1
	for k in n_ec:
		var d: int = synd[k]
		for i in range(1, l + 1):
			if i < lam.size():
				d ^= _mul(lam[i], synd[k - i])
		if d == 0:
			m += 1
			continue
		var coef := _div(d, b)
		var next := lam.duplicate()
		while next.size() < prev.size() + m:
			next.append(0)
		for i in prev.size():
			next[i + m] ^= _mul(prev[i], coef)
		if 2 * l <= k:
			prev = lam
			l = k + 1 - l
			b = d
			m = 1
		else:
			m += 1
		lam = next
	if l * 2 > n_ec:
		return false
	# Chien search: positions whose locator root shows up
	var spots := []
	for i in n:
		var p := n - 1 - i  # power of x for block[i]
		var xinv: int = _exp[(255 - p) % 255]
		if _eval(lam, xinv) == 0:
			spots.append(i)
	if spots.size() != l:
		return false
	# Forney (first root alpha^0): e = X * omega(X^-1) / lambda'(X^-1)
	var omega := []
	omega.resize(n_ec)
	omega.fill(0)
	for i in n_ec:
		for j in lam.size():
			if i - j >= 0:
				omega[i] ^= _mul(synd[i - j], lam[j])
	var deriv := []
	for j in range(1, lam.size()):
		deriv.append(lam[j] if j % 2 == 1 else 0)
	for i in spots:
		var p: int = n - 1 - i
		var x: int = _exp[p % 255]
		var xinv: int = _exp[(255 - p) % 255]
		var den := _eval(deriv, xinv)
		if den == 0:
			return false
		block[i] ^= _mul(x, _div(_eval(omega, xinv), den))
	for j in n_ec:  # trust nothing: it must check out now
		var s := 0
		for i in n:
			s = _mul(s, _exp[j]) ^ block[i]
		if s != 0:
			return false
	return true


## Polynomial (lowest degree first) at x.
static func _eval(poly: Array, x: int) -> int:
	var y := 0
	for i in range(poly.size() - 1, -1, -1):
		y = _mul(y, x) ^ poly[i]
	return y


# --- layout shared by encoder and reader ----------------------------------------

static func size_of(version: int) -> int:
	return 17 + 4 * version


## Matrix of zeros.
static func _grid(n: int) -> Array:
	var rows := []
	for y in n:
		var row := PackedByteArray()
		row.resize(n)
		rows.append(row)
	return rows


## Draws finders, timing, alignment, dark module and blank format areas into `m`, and marks
## them all in `fn` (function modules hold no data).
static func _function_patterns(version: int, m: Array, fn: Array) -> void:
	var n := size_of(version)
	var put := func(x: int, y: int, dark: bool) -> void:
		m[y][x] = 1 if dark else 0
		fn[y][x] = 1
	for i in n:
		put.call(6, i, i % 2 == 0)
		put.call(i, 6, i % 2 == 0)
	for c in [Vector2i(3, 3), Vector2i(n - 4, 3), Vector2i(3, n - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c.x + dx
				var y: int = c.y + dy
				if x >= 0 and x < n and y >= 0 and y < n:
					var d := maxi(absi(dx), absi(dy))
					put.call(x, y, d != 2 and d != 4)
	var al: Array = ALIGN[version]
	for i in al.size():
		for j in al.size():
			if (i == 0 and j == 0) or (i == 0 and j == al.size() - 1) or (i == al.size() - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					put.call(al[i] + dx, al[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_format_bits(m, fn, 0)  # reserve the format areas
	put.call(8, n - 8, true)


## The 15 format bits for level M and this mask.
static func _format_word(mask: int) -> int:
	var data := LEVEL_M << 3 | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	return (data << 10 | rem) ^ 0x5412


## Where format bit i goes, both copies: [[x, y], [x, y]].
static func _format_spots(n: int, i: int) -> Array:
	var a: Vector2i
	if i <= 5:
		a = Vector2i(8, i)
	elif i == 6:
		a = Vector2i(8, 7)
	elif i == 7:
		a = Vector2i(8, 8)
	elif i == 8:
		a = Vector2i(7, 8)
	else:
		a = Vector2i(14 - i, 8)
	var b := Vector2i(n - 1 - i, 8) if i < 8 else Vector2i(8, n - 15 + i)
	return [a, b]


static func _format_bits(m: Array, fn: Array, word: int) -> void:
	var n: int = m.size()
	for i in 15:
		for p in _format_spots(n, i):
			m[p.y][p.x] = (word >> i) & 1
			fn[p.y][p.x] = 1


static func _masked(mask: int, x: int, y: int) -> bool:
	match mask:
		0: return (x + y) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (x + y) % 3 == 0
		4: return (x / 3 + y / 2) % 2 == 0
		5: return x * y % 2 + x * y % 3 == 0
		6: return (x * y % 2 + x * y % 3) % 2 == 0
		_: return ((x + y) % 2 + x * y % 3) % 2 == 0


## Non-function cells in the order data bits fill them (two-column zigzag from the bottom right).
static func _data_cells(fn: Array) -> Array:
	var n: int = fn.size()
	var cells := []
	var right := n - 1
	while right >= 1:
		if right == 6:
			right = 5
		var upward := ((right + 1) & 2) == 0
		for vert in n:
			var y := n - 1 - vert if upward else vert
			for j in 2:
				var x := right - j
				if fn[y][x] == 0:
					cells.append(Vector2i(x, y))
		right -= 2
	return cells


# --- encoder --------------------------------------------------------------------

## The text as a QR matrix, or [] if it doesn't fit in version 6.
static func encode(text: String) -> Array:
	var bytes := text.to_utf8_buffer()
	var version := 0
	for v in range(1, MAX_VERSION + 1):
		var spec: Array = BLOCKS[v]
		if 4 + 8 + bytes.size() * 8 <= spec[1] * spec[2] * 8:
			version = v
			break
	if version == 0:
		return []
	var spec: Array = BLOCKS[version]
	var capacity: int = spec[1] * spec[2]
	# bit stream: byte mode, count, data, terminator, pad
	var bits := []
	var push := func(value: int, length: int) -> void:
		for i in range(length - 1, -1, -1):
			bits.append((value >> i) & 1)
	push.call(0b0100, 4)
	push.call(bytes.size(), 8)
	for b in bytes:
		push.call(b, 8)
	push.call(0, mini(4, capacity * 8 - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var data := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var b := 0
		for k in 8:
			b = b << 1 | bits[i + k]
		data.append(b)
	var pad := 0
	while data.size() < capacity:
		data.append(0xEC if pad % 2 == 0 else 0x11)
		pad += 1
	# blocks + EC, interleaved
	var stream := _interleave(data, spec)
	var n := size_of(version)
	var best := []
	var best_score := INF
	for mask in 8:
		var m := _grid(n)
		var fn := _grid(n)
		_function_patterns(version, m, fn)
		var cells := _data_cells(fn)
		for i in cells.size():
			var c: Vector2i = cells[i]
			var bit := (stream[i >> 3] >> (7 - (i & 7))) & 1 if i < stream.size() * 8 else 0
			m[c.y][c.x] = bit ^ (1 if _masked(mask, c.x, c.y) else 0)
		_format_bits(m, fn, _format_word(mask))
		var score := _penalty(m)
		if score < best_score:
			best_score = score
			best = m
	return best


static func _interleave(data: PackedByteArray, spec: Array) -> PackedByteArray:
	var n_ec: int = spec[0]
	var blocks: int = spec[1]
	var per: int = spec[2]
	var parts := []
	var ecs := []
	for b in blocks:
		var part := data.slice(b * per, (b + 1) * per)
		parts.append(part)
		ecs.append(rs_encode(part, n_ec))
	var out := PackedByteArray()
	for i in per:
		for b in blocks:
			out.append(parts[b][i])
	for i in n_ec:
		for b in blocks:
			out.append(ecs[b][i])
	return out


## Standard mask penalty (runs, 2x2 boxes, finder look-alikes, dark balance).
static func _penalty(m: Array) -> int:
	var n: int = m.size()
	var score := 0
	var dark := 0
	for pass_ in 2:
		for a in n:
			var run := 1
			var line := ""
			for b in n:
				var v: int = m[a][b] if pass_ == 0 else m[b][a]
				line += str(v)
				if pass_ == 0:
					dark += v
				if b > 0:
					var prev: int = m[a][b - 1] if pass_ == 0 else m[b - 1][a]
					if v == prev:
						run += 1
						if run == 5:
							score += 3
						elif run > 5:
							score += 1
					else:
						run = 1
			score += 40 * (line.count("10111010000") + line.count("00001011101"))
	for y in n - 1:
		for x in n - 1:
			var v: int = m[y][x]
			if v == m[y][x + 1] and v == m[y + 1][x] and v == m[y + 1][x + 1]:
				score += 3
	var percent := dark * 100 / (n * n)
	score += absi(percent - 50) / 5 * 10
	return score


# --- reader ---------------------------------------------------------------------

## Text from a sampled module matrix (any of versions 1-6), or "" if it isn't a valid code.
static func read_matrix(m: Array) -> String:
	var n: int = m.size()
	var version := (n - 17) / 4
	if version < 1 or version > MAX_VERSION or size_of(version) != n:
		return ""
	# format: nearest valid word to either copy
	var mask := -1
	var best := 4
	for copy in 2:
		var word := 0
		for i in 15:
			var p: Vector2i = _format_spots(n, i)[copy]
			word |= (m[p.y][p.x] & 1) << i
		for k in 8:
			var d := _popcount(word ^ _format_word(k))
			if d < best:
				best = d
				mask = k
	if mask == -1:
		return ""
	var blank := _grid(n)
	var fn := _grid(n)
	_function_patterns(version, blank, fn)
	var cells := _data_cells(fn)
	var spec: Array = BLOCKS[version]
	var n_ec: int = spec[0]
	var blocks: int = spec[1]
	var per: int = spec[2]
	var total := blocks * (per + n_ec)
	var stream := PackedByteArray()
	stream.resize(total)
	for i in mini(cells.size(), total * 8):
		var c: Vector2i = cells[i]
		var bit: int = (m[c.y][c.x] & 1) ^ (1 if _masked(mask, c.x, c.y) else 0)
		stream[i >> 3] |= bit << (7 - (i & 7))
	# de-interleave, correct, join the data parts
	var data := PackedByteArray()
	for b in blocks:
		var block := PackedByteArray()
		for i in per:
			block.append(stream[i * blocks + b])
		for i in n_ec:
			block.append(stream[per * blocks + i * blocks + b])
		if not rs_correct(block, n_ec):
			return ""
		data.append_array(block.slice(0, per))
	# byte-mode segment
	var mode := data[0] >> 4
	if mode != 0b0100:
		return ""
	var count := (data[0] & 0x0F) << 4 | data[1] >> 4
	if 1 + count >= data.size():
		return ""
	var out := PackedByteArray()
	for i in count:
		out.append((data[1 + i] & 0x0F) << 4 | data[2 + i] >> 4)
	return out.get_string_from_utf8()


static func _popcount(x: int) -> int:
	var c := 0
	while x:
		c += x & 1
		x >>= 1
	return c
